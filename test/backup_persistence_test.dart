import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import 'package:pharmacyms/core/data/schema.dart';
import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/core/domain/money.dart';
import 'package:pharmacyms/features/backup/data/backup_codec.dart';
import 'package:pharmacyms/features/backup/data/backup_integrity.dart';
import 'package:pharmacyms/features/backup/data/native_backup_files.dart';
import 'package:pharmacyms/features/backup/data/sqlite_backup_repository.dart';
import 'package:pharmacyms/features/backup/data/stored_zip.dart';
import 'package:pharmacyms/features/backup/domain/backup.dart';
import 'package:pharmacyms/features/debtors/domain/debt.dart';
import 'support/inventory_database.dart';

String id() => const Uuid().v4();
void main() {
  late InventoryDatabase f;
  late SqliteBackupRepository repo;
  setUp(() async {
    f = InventoryDatabase();
    await f.open();
    repo = SqliteBackupRepository(f.database, f.clock);
  });
  tearDown(() => f.close());
  Future<BackupTables> snapshot() =>
      f.database.connection.transaction(readBackupTables);
  Future<Uint8List> encode(
    BackupTables tables, {
    int schema = schemaVersion,
    String zone = 'Asia/Kabul',
  }) async => BackupCodec.encode(
    tables,
    createdUtc: f.clock.nowUtc(),
    timezone: zone,
    offsetMinutes: 270,
    schema: schema,
  );
  Future<void> populate() async {
    final settings = f.services.settings,
        inv = f.services.inventory,
        debts = f.services.debtors;
    final unit = await settings.saveUnit(name: 'عدد');
    final product = await inv.createProduct(
      name: 'Amoxicillin دارو',
      unitId: unit.meta.id,
      minimumStock: 10,
      warningDays: 5,
      notes: 'متن\nدو خط\u200c ☃',
    );
    await inv.createBatch(
      productId: product.meta.id,
      receivedDate: f.clock.today(),
      openingQuantity: 8,
      production: DateSpec(
        calendar: DateCalendar.gregorian,
        year: 2024,
        month: 2,
        day: 29,
      ),
      expiry: DateSpec(
        calendar: DateCalendar.solarHijri,
        year: 1403,
        month: 12,
      ),
    );
    final b = await inv.createBatch(
      productId: product.meta.id,
      receivedDate: f.clock.today(),
      openingQuantity: 12,
    );
    await inv.adjust(
      operationId: id(),
      batchId: b.meta.id,
      delta: -3,
      note: 'Manual',
    );
    await settings.saveUnit(id: unit.meta.id, name: unit.name, inactive: true);
    await f.services.dailyRecords.save(
      operationId: id(),
      date: f.clock.today(),
      sales: Money.fromMinor(Money.maxMinor),
      profit: Money.parse('-0.01'),
      note: 'فارسی Arabic ١٢',
    );
    final customer = await debts.createCustomer(
      name: 'احمد',
      phone: '۰۰۷۰ ۱۲۳',
      note: 'دوست',
    );
    final first = await debts.addEntry(
      operationId: id(),
      customerId: customer.meta.id,
      date: f.clock.today(),
      kind: LedgerKind.debt,
      amount: Money.parse('500'),
      description: 'Amoxicillin برای خانواده',
    );
    await debts.addEntry(
      operationId: id(),
      customerId: customer.meta.id,
      date: f.clock.today(),
      kind: LedgerKind.debt,
      amount: Money.parse('300'),
    );
    final payment = await debts.addEntry(
      operationId: id(),
      customerId: customer.meta.id,
      date: f.clock.today(),
      kind: LedgerKind.payment,
      amount: Money.parse('200'),
    );
    await debts.editEntry(
      operationId: id(),
      id: first.meta.id,
      date: first.date,
      kind: first.kind,
      amount: first.amount,
      description: 'تصحیح\nAmoxicillin',
      reason: 'Note corrected',
    );
    await debts.deleteEntry(
      payment.meta.id,
      operationId: id(),
      reason: 'Mistake',
    );
    await debts.addEntry(
      operationId: id(),
      customerId: customer.meta.id,
      date: f.clock.today(),
      kind: LedgerKind.payment,
      amount: Money.parse('200'),
    );
    final settled = await debts.createCustomer(name: 'Settled');
    await debts.archiveCustomer(
      settled.meta.id,
      archived: true,
      operationId: id(),
    );
    await settings.setPreference('display.preference', 'فارسی', version: 2);
  }

  BackupTables operational(BackupTables rows) => {
    ...rows,
    'app_settings': rows['app_settings']!
        .where((r) => r['preference_key'] != restoreStatusKey)
        .toList(),
  };

  test(
    'complete portable round trip preserves all rows, money, Unicode, dates, audits, references and receipts',
    () async {
      await populate();
      final before = await snapshot();
      final prepared = await repo.prepare();
      final bytes = await File(prepared.path).readAsBytes(),
          decoded = BackupCodec.decode(bytes);
      if (const bool.fromEnvironment('PHASE6_NATIVE_FIXTURE')) {
        await Directory('build').create(recursive: true);
        await File('build/phase6-native-fixture.zip').writeAsBytes(bytes);
      }
      expect(decoded.manifest.schema, schemaVersion);
      expect(
        decoded.manifest.counts.keys.toSet(),
        backupTablesFor(schemaVersion).toSet(),
      );
      expect(
        decoded.tables['daily_records']!.single['sales_minor'],
        '${Money.maxMinor}',
      );
      expect((await repo.status())!.outcome, ExportOutcome.prepared);
      await f.services.debtors.createCustomer(name: 'Should be replaced');
      final preview = await repo.validate(bytes, 'portable.zip');
      expect(await f.count('customers'), 3);
      await repo.restore(preview);
      expect(operational(await snapshot()), before);
      await f.reopen();
      expect(operational(await snapshot()), before);
      final c = (await f.services.debtors.searchCustomers(
        filter: CustomerFilter.outstanding,
      )).items.single;
      expect(c.balance.minor, 60000);
      final batch = (await f.services.inventory.batches(
        before['products']!.single['id'] as String,
      )).where((b) => b.expiry != null).single;
      expect(batch.expiry!.calendar, DateCalendar.solarHijri);
      expect(batch.expiry!.precision, DatePrecision.month);
      await validateBackupDatabase(f.database.connection);
    },
  );
  test(
    'repeated restore replaces without duplicates and safety snapshot captures the latest current data',
    () async {
      await populate();
      final bytes = await encode(await snapshot());
      for (var i = 0; i < 2; i++) {
        await f.services.debtors.createCustomer(name: 'Current $i');
        final before = await snapshot(),
            preview = await repo.validate(bytes, 'backup.zip');
        await repo.restore(preview);
        expect(await f.count('customers'), 2);
        final safety =
            (await repo.directory
                    .list()
                    .where((e) => p.basename(e.path).startsWith('safety-'))
                    .toList())
                .cast<File>()
              ..sort(
                (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
              );
        expect(
          BackupCodec.decode(
            await safety.first.readAsBytes(),
          ).tables['customers']!.length,
          before['customers']!.length,
        );
      }
    },
  );
  for (final point in [
    'before_snapshot',
    'after_snapshot',
    'after_replace',
    'before_commit',
  ]) {
    test(
      'failure at $point rolls back all live data, guards and metadata; reopen stays intact',
      () async {
        await populate();
        final bytes = await encode(await snapshot());
        await f.services.debtors.createCustomer(name: 'Must survive');
        final before = await snapshot();
        repo = SqliteBackupRepository(
          f.database,
          f.clock,
          failureHook: (stage) async {
            if (stage == point) {
              throw const FileSystemException('Injected storage failure');
            }
          },
        );
        final preview = await repo.validate(bytes, 'backup.zip');
        await expectLater(
          repo.restore(preview),
          throwsA(isA<BackupException>()),
        );
        expect(await snapshot(), before);
        await f.reopen();
        expect(await snapshot(), before);
        await expectLater(
          f.database.connection.update('stock_movements', {'delta': 1}),
          throwsA(anything),
        );
        await validateBackupDatabase(f.database.connection);
      },
    );
  }
  test(
    'lost restore acknowledgment reconciles the committed operation',
    () async {
      await populate();
      final original = await snapshot(), bytes = await encode(original);
      repo = SqliteBackupRepository(
        f.database,
        f.clock,
        failureHook: (stage) async {
          if (stage == 'after_commit') throw StateError('Lost acknowledgement');
        },
      );
      final preview = await repo.validate(bytes, 'backup.zip');
      await repo.restore(preview);
      expect(operational(await snapshot()), original);
      await expectLater(repo.restore(preview), throwsA(isA<BackupException>()));
    },
  );
  test(
    'validated preview cannot be reused after cancellation or silently changed in staging',
    () async {
      final bytes = await encode(await snapshot());
      var preview = await repo.validate(bytes, 'backup.zip');
      await repo.discard(preview);
      await expectLater(repo.restore(preview), throwsA(isA<BackupException>()));
      preview = await repo.validate(bytes, 'backup.zip');
      final path = p.join(
        repo.directory.path,
        'import-${preview.token}.sqlite',
      );
      final stage = await f.database.factory.openDatabase(path);
      await stage.update(
        'units',
        {'name': 'Changed', 'name_key': 'changed'},
        where: 'id=?',
        whereArgs: [(await stage.query('units')).first['id']],
      );
      await stage.close();
      final before = await snapshot();
      await expectLater(repo.restore(preview), throwsA(isA<BackupException>()));
      expect(await snapshot(), before);
    },
  );
  test(
    'v4 portable import migrates phone keys and receipts in staging before replacement',
    () async {
      await populate();
      final old = await snapshot();
      old.remove('debt_operations');
      old['customers'] = old['customers']!
          .map((r) => {...r}..remove('phone_key'))
          .toList();
      final bytes = await encode(old, schema: 4);
      final preview = await repo.validate(bytes, 'older.zip');
      expect(preview.manifest.schema, 4);
      await repo.restore(preview);
      expect(await f.database.connection.getVersion(), schemaVersion);
      expect(
        (await f.services.debtors.searchCustomers(
          search: '0070123',
        )).items.single.customer.name,
        'احمد',
      );
      expect(await f.count('debt_operations'), 0);
      await validateBackupDatabase(f.database.connection);
    },
  );
  test(
    'v1 portable import installs later indexes, guards, counters and receipt tables',
    () async {
      await populate();
      final entries = (await snapshot())['ledger_entries']!;
      final last = entries.last;
      await f.services.debtors.deleteEntry(
        last['id'] as String,
        operationId: id(),
        reason: 'Retain deleted high sequence in old-schema audit',
      );
      final old = await snapshot();
      old.removeWhere((name, _) => !backupTablesFor(1).contains(name));
      old['customers'] = [
        for (final row in old['customers']!) {...row}..remove('phone_key'),
      ];
      final preview = await repo.validate(
        await encode(old, schema: 1),
        'v1.zip',
      );
      await repo.restore(preview);
      expect(await f.count('sequence_counters'), 2);
      expect(
        (await f.database.connection.query(
          'sequence_counters',
          where: 'name=?',
          whereArgs: ['ledger_entries'],
        )).single['value'],
        last['sequence'],
      );
      await validateBackupDatabase(f.database.connection);
    },
  );
  final corruptions = <String, void Function(BackupTables)>{
    'stock total': (t) => t['batches']![0]['quantity'] = 7,
    'stock running result': (t) =>
        t['stock_movements']![0]['resulting_quantity'] = 1,
    'historical debt deficit': (t) {
      final r = t['ledger_entries']!.last;
      r['business_date'] = '2020-01-01';
      r['kind'] = 'payment';
    },
    'overpayment': (t) {
      t['ledger_entries']!.last['amount_minor'] = 999999;
    },
    'missing foreign key': (t) => t['products']![0]['unit_id'] = id(),
    'duplicate ID': (t) => t['customers']!.add({...t['customers']!.first}),
    'partial date canonical mismatch': (t) {
      final r = t['date_specs']!.firstWhere(
        (r) => r['calendar'] == 'solarHijri',
      );
      r['canonical_start'] = '2024-02-01';
      r['canonical_end'] = '2024-03-01';
    },
    'invalid exact money': (t) =>
        t['daily_records']![0]['profit_minor'] = '1.5',
    'history counter below audit': (t) => t['sequence_counters']!.firstWhere(
      (r) => r['name'] == 'ledger_entries',
    )['value'] = 0,
    'archived outstanding customer': (t) =>
        t['customers']!.firstWhere((r) => r['name'] == 'احمد')['archived'] = 1,
    'malformed audit': (t) =>
        t['correction_audits']![0]['previous_value'] = '{}',
  };
  for (final change in corruptions.entries) {
    test(
      '${change.key} is rejected before replacement even with correct checksum',
      () async {
        await populate();
        final before = await snapshot();
        final altered = (jsonDecode(jsonEncode(before)) as Map<String, dynamic>)
            .map(
              (k, v) => MapEntry(
                k,
                (v as List)
                    .map((r) => Map<String, Object?>.from(r as Map))
                    .toList(),
              ),
            );
        change.value(altered);
        await expectLater(
          repo.validate(await encode(altered), 'bad.zip'),
          throwsA(isA<BackupException>()),
        );
        expect(await snapshot(), before);
        expect(
          await repo.directory
              .list()
              .where((f) => p.basename(f.path).startsWith('import-'))
              .toList(),
          isEmpty,
        );
      },
    );
  }
  test(
    'checksum, truncation, unsupported versions, unsafe paths and compression are rejected',
    () async {
      final bytes = await encode(await snapshot());
      final files = StoredZip.decode(bytes);
      final manifest =
          jsonDecode(utf8.decode(files['manifest.json']!))
              as Map<String, dynamic>;
      final badChecksum = StoredZip.encode({
        'manifest.json': files['manifest.json']!,
        'data.json': Uint8List.fromList(utf8.encode('{}')),
      });
      expect(
        () => BackupCodec.decode(badChecksum),
        throwsA(isA<BackupException>()),
      );
      for (final key in ['format_version', 'schema_version']) {
        final newer = {...manifest, key: 999};
        expect(
          () => BackupCodec.decode(
            StoredZip.encode({
              'manifest.json': Uint8List.fromList(
                utf8.encode(jsonEncode(newer)),
              ),
              'data.json': files['data.json']!,
            }),
          ),
          throwsA(
            isA<BackupException>().having(
              (e) => e.message,
              'message',
              contains('newer'),
            ),
          ),
        );
      }
      for (final cut in [0, 4, 30, bytes.length - 1]) {
        expect(
          () => BackupCodec.decode(Uint8List.sublistView(bytes, 0, cut)),
          throwsA(isA<BackupException>()),
        );
      }
      final unsafe = Uint8List.fromList(bytes);
      unsafe.setRange(30, 43, utf8.encode('../ifest.json'));
      expect(() => BackupCodec.decode(unsafe), throwsA(isA<BackupException>()));
      final compressed = Uint8List.fromList(bytes),
          header = ByteData.sublistView(compressed);
      final central = header.getUint32(compressed.length - 6, Endian.little);
      header.setUint16(central + 10, 8, Endian.little);
      expect(
        () => BackupCodec.decode(compressed),
        throwsA(isA<BackupException>()),
      );
      final oversized = Uint8List.fromList(bytes),
          h = ByteData.sublistView(oversized);
      h.setUint32(central + 24, maxBackupBytes + 1, Endian.little);
      expect(
        () => BackupCodec.decode(oversized),
        throwsA(isA<BackupException>()),
      );
    },
  );
  test(
    'private-copy cleanup retains recent safety files and active previews without deleting external files',
    () async {
      final bytes = await encode(await snapshot());
      final preview = await repo.validate(bytes, 'external.zip');
      final stage = File(
        p.join(repo.directory.path, 'import-${preview.token}.sqlite'),
      );
      final old = f.clock.nowUtc().subtract(const Duration(days: 10));
      await stage.setLastModified(old);
      final stale = File(p.join(repo.directory.path, 'import-${id()}.sqlite'));
      await stale.writeAsBytes([0]);
      await stale.setLastModified(old);
      final expired = File(
        p.join(
          repo.directory.path,
          '${id()}-pharmacy-backup-20260101-000000.zip',
        ),
      );
      await expired.writeAsBytes(bytes);
      await expired.setLastModified(old);
      final unrelated = File(p.join(repo.directory.path, 'external.zip'));
      await unrelated.writeAsBytes(bytes);
      await unrelated.setLastModified(old);
      final safety = <File>[];
      for (var i = 0; i < 3; i++) {
        final file = File(p.join(repo.directory.path, 'safety-${id()}.zip'));
        await file.writeAsBytes(bytes);
        await file.setLastModified(old.add(Duration(hours: i)));
        safety.add(file);
      }
      await repo.prepare();
      expect(await stale.exists(), isFalse);
      expect(await expired.exists(), isFalse);
      expect(await stage.exists(), isTrue);
      expect(await unrelated.readAsBytes(), bytes);
      expect(await safety.first.exists(), isFalse);
      expect(await safety[1].exists(), isTrue);
      expect(await safety[2].exists(), isTrue);
      await repo.restore(preview);
    },
  );
  test(
    'stream reader enforces actual size without trusting picker metadata and nested JSON is bounded',
    () async {
      var consumed = 0;
      Stream<List<int>> chunks() async* {
        for (var i = 0; i < 66; i++) {
          consumed++;
          yield Uint8List(1024 * 1024);
        }
      }

      await expectLater(
        readBoundedBackup(chunks()),
        throwsA(isA<BackupException>()),
      );
      expect(consumed, 65);
      expect(
        () => boundedJson('${'[' * 33}0${']' * 33}'),
        throwsA(isA<BackupException>()),
      );
    },
  );
  test(
    'independent Python ZIP/JSON reader and writer interoperate without device paths or rounding',
    () async {
      await populate();
      final bytes = await encode(await snapshot());
      final file = File(p.join(f.directory.path, 'portable.zip'));
      await file.writeAsBytes(bytes);
      final script = File(p.join(f.directory.path, 'verify.py'));
      await script.writeAsString('''import zipfile,json,hashlib,sys
source,target=sys.argv[1:]
with zipfile.ZipFile(source) as z:
 assert sorted(z.namelist()) == ['data.json','manifest.json']
 assert z.testzip() is None
 raw=z.read('data.json'); m=json.loads(z.read('manifest.json')); d=json.loads(raw)
 assert hashlib.sha256(raw).hexdigest() == m['payload_sha256']
 assert d['tables']['daily_records'][0]['sales_minor'] == '9000000000000000'
 assert isinstance(d['tables']['daily_records'][0]['profit_minor'],str)
 with zipfile.ZipFile(target,'w',compression=zipfile.ZIP_STORED) as out:
  out.writestr('manifest.json',z.read('manifest.json')); out.writestr('data.json',raw)
''');
      final rewritten = p.join(f.directory.path, 'python.zip');
      final result = await Process.run('python', [
        script.path,
        file.path,
        rewritten,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final native = BackupCodec.decode(await File(rewritten).readAsBytes());
      expect(
        native.manifest.checksum,
        sha256.convert(StoredZip.decode(bytes)['data.json']!).toString(),
      );
      final preview = await repo.validate(
        await File(rewritten).readAsBytes(),
        'python.zip',
      );
      await repo.restore(preview);
    },
  );
}
