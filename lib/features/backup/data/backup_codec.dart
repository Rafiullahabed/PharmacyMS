import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../../../core/data/schema.dart';
import '../domain/backup.dart';
import 'stored_zip.dart';

Object? boundedJson(String text) {
  var depth = 0, quoted = false, escaped = false;
  for (final rune in text.runes) {
    if (escaped) {
      escaped = false;
      continue;
    }
    if (quoted && rune == 92) {
      escaped = true;
      continue;
    }
    if (rune == 34) {
      quoted = !quoted;
      continue;
    }
    if (!quoted) {
      if (rune == 123 || rune == 91) depth++;
      if (rune == 125 || rune == 93) depth--;
      if (depth > 32) {
        throw const BackupException(
          'The backup contains unsupported nested data.',
        );
      }
    }
  }
  return jsonDecode(text);
}

class BackupCodec {
  static Uint8List encode(
    BackupTables tables, {
    required DateTime createdUtc,
    required String timezone,
    required int offsetMinutes,
    int schema = schemaVersion,
    String appVersion = backupAppVersion,
  }) {
    final portable = {
      for (final table in tables.entries)
        table.key: [
          for (final row in table.value)
            {
              for (final cell in row.entries)
                cell.key: cell.value is int ? '${cell.value}' : cell.value,
            },
        ],
    };
    final data = Uint8List.fromList(
      utf8.encode(jsonEncode({'tables': portable})),
    );
    if (data.length > maxPayloadBytes ||
        tables.values.fold<int>(0, (n, r) => n + r.length) > maxBackupRecords) {
      throw const BackupException(
        'The backup exceeds the supported size or record limit. No file was exported.',
      );
    }
    final manifest = BackupManifest(
      schema: schema,
      appVersion: appVersion,
      createdUtc: createdUtc,
      timezone: timezone,
      offsetMinutes: offsetMinutes,
      counts: {for (final t in tables.entries) t.key: t.value.length},
      checksum: sha256.convert(data).toString(),
      payloadBytes: data.length,
    );
    return StoredZip.encode({
      'manifest.json': Uint8List.fromList(
        utf8.encode(jsonEncode(manifest.toJson())),
      ),
      'data.json': data,
    });
  }

  static BackupDocument decode(Uint8List bytes) {
    try {
      final files = StoredZip.decode(bytes);
      final m =
          boundedJson(utf8.decode(files['manifest.json']!))
              as Map<String, dynamic>;
      if (m['format_version'] is int &&
              m['format_version'] > backupFormatVersion ||
          m['schema_version'] is int && m['schema_version'] > schemaVersion) {
        throw const BackupException(
          'This backup needs a newer version of Pharmacy Companion. Update the app, then select it again.',
        );
      }
      if (m['format'] != 'pharmacy-companion-backup' ||
          m['format_version'] != 1 ||
          m['integer_encoding'] != 'decimal-strings' ||
          m['schema_version'] is! int ||
          m['schema_version'] < 1 ||
          m['checksum_algorithm'] != 'SHA-256') {
        throw const BackupException(
          'Unsupported backup format. Select a Pharmacy Companion backup.',
        );
      }
      final schema = m['schema_version'] as int,
          expected = backupTablesFor(schema);
      final payload = files['data.json']!;
      if (m['payload_bytes'] != payload.length ||
          m['payload_sha256'] != sha256.convert(payload).toString()) {
        throw const BackupException(
          'The backup checksum does not match. The file may be damaged; choose another copy.',
        );
      }
      final created = DateTime.parse(m['created_utc'] as String);
      if (!created.isUtc ||
          created.toIso8601String() != m['created_utc'] ||
          m['app_version'] is! String ||
          (m['app_version'] as String).length > 80 ||
          m['timezone'] is! String ||
          (m['timezone'] as String).length > 100 ||
          m['utc_offset_minutes'] is! int ||
          (m['utc_offset_minutes'] as int).abs() > 24 * 60) {
        throw const FormatException();
      }
      final root = boundedJson(utf8.decode(payload)) as Map<String, dynamic>;
      final tables = root['tables'] as Map<String, dynamic>,
          counts = m['counts'] as Map<String, dynamic>;
      if (root.length != 1 ||
          tables.length != expected.length ||
          counts.length != expected.length) {
        throw const FormatException();
      }
      var total = 0;
      final parsed = <String, List<BackupRow>>{},
          parsedCounts = <String, int>{};
      for (final table in expected) {
        final rows = tables[table] as List;
        if (counts[table] is! int || counts[table] != rows.length) {
          throw const FormatException();
        }
        total += rows.length;
        if (total > maxBackupRecords) {
          throw const BackupException(
            'The backup exceeds the 250,000 record limit.',
          );
        }
        parsed[table] = rows
            .map((r) => Map<String, Object?>.from(r as Map))
            .toList();
        parsedCounts[table] = rows.length;
      }
      return BackupDocument(
        BackupManifest(
          schema: schema,
          appVersion: m['app_version'],
          createdUtc: created,
          timezone: m['timezone'],
          offsetMinutes: m['utc_offset_minutes'],
          counts: parsedCounts,
          checksum: m['payload_sha256'],
          payloadBytes: payload.length,
        ),
        parsed,
      );
    } on BackupException {
      rethrow;
    } catch (_) {
      throw const BackupException(
        'The backup is damaged or has invalid metadata. Choose another copy.',
      );
    }
  }
}
