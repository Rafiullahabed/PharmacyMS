import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import '../../../core/data/app_database.dart';
import '../../../core/data/schema.dart';
import '../../../core/domain/dates.dart';
import '../../../core/domain/entity.dart';
import '../../../core/domain/validation.dart';
import '../../settings/data/sqlite_settings_repository.dart';
import '../domain/backup.dart';
import 'backup_codec.dart';
import 'backup_integrity.dart';

/// Restore replaces all logical data inside one FULL-synchronous SQLite
/// transaction. The existing connection stays valid; crash recovery uses
/// SQLite's journal instead of a platform-dependent multi-file rename.
class SqliteBackupRepository implements BackupRepository {
  SqliteBackupRepository(this.database, this.clock, {this.failureHook});
  final AppDatabase database;
  final AppClock clock;

  /// Test-only fault injection; never supplied by production composition.
  final Future<void> Function(String stage)? failureHook;
  final _previews = <String, ({String path, String digest})>{};
  bool _busy = false;
  Database get db => database.connection;
  Directory get directory =>
      Directory(p.join(p.dirname(db.path), 'portable_backups'));
  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_busy) {
      throw const BackupException('Another backup operation is still running.');
    }
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }

  Future<void> _fault(String stage) async {
    await failureHook?.call(stage);
  }

  Future<Uint8List> _encode(BackupTables tables) async {
    final utc = clock.nowUtc().toUtc(), local = clock.nowUtc().toLocal();
    return compute(_encodeBackup, (
      tables: tables,
      utc: utc,
      timezone: local.timeZoneName,
      offset: local.timeZoneOffset.inMinutes,
    ));
  }

  Future<void> _write(File file, Uint8List bytes) async {
    await directory.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  /// Housekeeping only touches owned private copies, never chosen source files.
  /// Keep the newest two safety snapshots and all copies younger than a day;
  /// exported preparations expire after seven days. Active previews survive.
  Future<void> _cleanPrivateCopies() async {
    try {
      if (!await directory.exists()) return;
      final now = clock.nowUtc();
      final files = <({File file, DateTime modified})>[];
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is File) {
          files.add((file: entry, modified: (await entry.stat()).modified));
        }
      }
      files.sort((a, b) => b.modified.compareTo(a.modified));
      var safetyCount = 0;
      const uuid =
          r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
      for (final entry in files) {
        final name = p.basename(entry.file.path),
            age = now.difference(entry.modified);
        if (RegExp('^safety-$uuid\\.zip\$').hasMatch(name)) {
          safetyCount++;
          if (safetyCount > 2 && age > const Duration(days: 1)) {
            await entry.file.delete();
          }
        } else if (RegExp('^import-$uuid\\.sqlite\$').hasMatch(name)) {
          if (age > const Duration(days: 1) &&
              !_previews.values.any((v) => v.path == entry.file.path)) {
            await database.factory.deleteDatabase(entry.file.path);
          }
        } else if (RegExp(
              '^$uuid-pharmacy-backup-[0-9]{8}-[0-9]{6}\\.zip\$',
            ).hasMatch(name) &&
            age > const Duration(days: 7)) {
          await entry.file.delete();
        }
      }
    } catch (_) {
      // Cleanup must not prevent export, validation, or report a failed restore.
    }
  }

  @override
  Future<BackupStatus?> status() async {
    final pref = await SqliteSettingsRepository(
      db,
      clock,
    ).preference(backupStatusKey);
    if (pref == null) return null;
    try {
      final v = jsonDecode(pref.value) as Map;
      return BackupStatus(
        DateTime.parse(v['created_utc'] as String),
        v['filename'] as String,
        ExportOutcome.values.byName(v['outcome'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> recordOutcome(PreparedBackup backup, ExportOutcome outcome) =>
      SqliteSettingsRepository(db, clock).setPreference(
        backupStatusKey,
        jsonEncode({
          'created_utc': backup.manifest.createdUtc.toIso8601String(),
          'filename': backup.filename,
          'outcome': outcome.name,
        }),
      );

  @override
  Future<PreparedBackup> prepare({
    BackupProgress? progress,
  }) => _exclusive(() async {
    await _cleanPrivateCopies();
    progress?.call('Reading a consistent snapshot…');
    final tables = await db.transaction((tx) async {
      await validateBackupDatabase(tx);
      return readBackupTables(tx);
    });
    progress?.call('Preparing backup file…');
    final bytes = await _encode(tables),
        manifest = (await compute(BackupCodec.decode, bytes)).manifest;
    final local = clock.nowUtc().toLocal();
    String two(int n) => '$n'.padLeft(2, '0');
    final filename =
        'pharmacy-backup-${local.year}${two(local.month)}${two(local.day)}-${two(local.hour)}${two(local.minute)}${two(local.second)}.zip';
    final file = File(p.join(directory.path, '${const Uuid().v4()}-$filename'));
    await _write(file, bytes);
    final result = PreparedBackup(file.path, filename, manifest);
    await recordOutcome(result, ExportOutcome.prepared);
    return result;
  });

  @override
  Future<RestorePreview> validate(
    Uint8List bytes,
    String filename, {
    BackupProgress? progress,
  }) => _exclusive(() async {
    await _cleanPrivateCopies();
    progress?.call('Checking backup format and checksum…');
    final document = await compute(BackupCodec.decode, bytes);
    final token = const Uuid().v4(),
        stagePath = p.join(directory.path, 'import-$token.sqlite');
    await directory.create(recursive: true);
    Database? stage;
    try {
      progress?.call('Validating records in a temporary database…');
      stage = await database.factory.openDatabase(
        stagePath,
        options: OpenDatabaseOptions(
          version: document.manifest.schema,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys=ON');
          },
          onCreate: (db, version) => migrate(db, 0, version),
        ),
      );
      final current = stage;
      await current.transaction((tx) async {
        final rows = await decodeBackupRows(tx, document.tables);
        await replaceRows(tx, rows);
      });
      await stage.close();
      stage = null;
      progress?.call('Migrating and checking histories…');
      final migrated = await AppDatabase.open(
        factory: database.factory,
        path: stagePath,
        clock: clock,
      );
      stage = migrated.connection;
      final verified = await stage.transaction((tx) async {
        if (document.manifest.schema == 1) {
          // Schema 1 had no counters. Migration 2 initializes from live entries;
          // retained corrections can refer to later, now-deleted sequences.
          var historicalMaximum = 0;
          for (final audit in await tx.query('correction_audits')) {
            for (final key in ['previous_value', 'new_value']) {
              if (audit[key] == null) continue;
              final snapshot = boundedJson(audit[key] as String) as Map;
              final sequence = snapshot['sequence'] as int;
              if (sequence > historicalMaximum) historicalMaximum = sequence;
            }
          }
          await tx.rawUpdate(
            "UPDATE sequence_counters SET value=max(value,?) WHERE name='ledger_entries'",
            [historicalMaximum],
          );
        }
        await validateBackupDatabase(tx);
        return readBackupTables(tx);
      });
      final digest = await compute(_tablesDigest, verified);
      await _fault('validated');
      await stage.close();
      stage = null;
      _previews[token] = (path: stagePath, digest: digest);
      return RestorePreview(
        token,
        p.basename(filename.replaceAll('\\', '/')),
        document.manifest,
      );
    } catch (error) {
      await stage?.close();
      await database.factory.deleteDatabase(stagePath);
      if (error is BackupException) rethrow;
      if (error is ValidationException) {
        throw BackupException(
          'Invalid backup: ${error.message} Current data has not been replaced.',
        );
      }
      throw const BackupException(
        'The backup could not be validated. It may contain invalid records or there may be insufficient device storage. Current data is unchanged.',
      );
    }
  });
  @override
  Future<void> discard(RestorePreview preview) async {
    final staged = _previews.remove(preview.token);
    if (staged != null) await database.factory.deleteDatabase(staged.path);
  }

  @override
  Future<void> restore(
    RestorePreview preview, {
    BackupProgress? progress,
  }) => _exclusive(() async {
    final stagedInfo = _previews[preview.token];
    if (stagedInfo == null) {
      throw const BackupException(
        'Select and validate the backup again before restoring.',
      );
    }
    final staged = await AppDatabase.open(
      factory: database.factory,
      path: stagedInfo.path,
      clock: clock,
    );
    late BackupTables incoming;
    try {
      incoming = await staged.connection.transaction((tx) async {
        await validateBackupDatabase(tx);
        return readBackupTables(tx);
      });
    } finally {
      await staged.close();
    }
    final digest = await compute(_tablesDigest, incoming);
    requireBackup(
      digest == stagedInfo.digest,
      'the staged backup changed after preview; select the original file again',
    );
    final operationId = const Uuid().v4();
    try {
      await db.transaction((tx) async {
        progress?.call('Creating internal safety snapshot…');
        await validateBackupDatabase(tx);
        final safetyBytes = await _encode(await readBackupTables(tx));
        await _fault('before_snapshot');
        await _write(
          File(p.join(directory.path, 'safety-$operationId.zip')),
          safetyBytes,
        );
        await _fault('after_snapshot');
        progress?.call('Replacing local data…');
        await replaceRows(tx, incoming);
        await _fault('after_replace');
        await validateBackupDatabase(tx);
        final now = clock.nowUtc().millisecondsSinceEpoch;
        final existing = await tx.query(
          'app_settings',
          where: 'preference_key=?',
          whereArgs: [restoreStatusKey],
        );
        final row = <String, Object?>{
          ...existing.isEmpty
              ? EntityMeta.create(clock).toRow()
              : existing.single,
          'preference_key': restoreStatusKey,
          'version': 1,
          'value': jsonEncode({
            'operation_id': operationId,
            'restored_utc': clock.nowUtc().toUtc().toIso8601String(),
            'payload_sha256': preview.manifest.checksum,
          }),
        };
        if (existing.isEmpty) {
          await tx.insert('app_settings', row);
        } else {
          row['updated_at'] = now < (row['updated_at'] as int)
              ? row['updated_at']
              : now;
          await tx.update(
            'app_settings',
            row,
            where: 'id=?',
            whereArgs: [row['id']],
          );
        }
        await _fault('before_commit');
      });
      await _fault('after_commit');
    } catch (_) {
      // Reconcile an ambiguous acknowledgment without applying replacement twice.
      final pref = await SqliteSettingsRepository(
        db,
        clock,
      ).preference(restoreStatusKey);
      bool committed = false;
      try {
        committed =
            pref != null &&
            (jsonDecode(pref.value) as Map)['operation_id'] == operationId;
      } catch (_) {
        /* No matching commit. */
      }
      if (!committed) {
        throw const BackupException(
          'Restore did not complete. The previous data was retained by the database transaction. Check available storage and try again.',
        );
      }
    }
    // Cleanup cannot turn a durably committed replacement into a reported failure.
    try {
      await discard(preview);
    } catch (_) {
      /* Stale staging is cleaned at the next backup operation. */
    }
    await _cleanPrivateCopies();
  });
}

// Top-level workers send only plain data, never a repository, widget callback,
// database connection or timer captured by an enclosing async closure.
Uint8List _encodeBackup(
  ({BackupTables tables, DateTime utc, String timezone, int offset}) input,
) => BackupCodec.encode(
  input.tables,
  createdUtc: input.utc,
  timezone: input.timezone,
  offsetMinutes: input.offset,
);

String _tablesDigest(BackupTables tables) =>
    sha256.convert(utf8.encode(jsonEncode(tables))).toString();
