import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:uuid/uuid.dart';
import 'package:pharmacyms/app/application/app_services.dart';
import 'package:pharmacyms/core/data/app_database.dart';
import 'package:pharmacyms/core/data/schema.dart';
import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/core/domain/entity.dart';
import 'package:pharmacyms/core/domain/money.dart';
import 'package:pharmacyms/core/domain/validation.dart';
import 'package:pharmacyms/features/debtors/domain/debt.dart';
import 'support/fake_clock.dart';

void main() {
  sqfliteFfiInit();
  final clock = FakeClock();
  late Directory directory;
  late String path;
  late AppDatabase database;
  late AppServices services;
  String id() => const Uuid().v4();
  Future<int> count(String table) async => Sqflite.firstIntValue(
    await database.connection.rawQuery('SELECT count(*) FROM $table'),
  )!;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pharmacy_phase1_');
    path = p.join(directory.path, 'test.sqlite');
    database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
      clock: clock,
    );
    services = AppServices(database, clock);
  });
  tearDown(() async {
    await database.close();
    // Only the unique test-created directory under the OS temp root is removed.
    final resolved = p.normalize(directory.absolute.path);
    if (p.isWithin(p.normalize(Directory.systemTemp.absolute.path), resolved) &&
        p.basename(resolved).startsWith('pharmacy_phase1_')) {
      await directory.delete(recursive: true);
    }
  });
  Future<String> product() async {
    final unit = (await services.settings.units()).first;
    return (await services.inventory.createProduct(
      name: '  دوا Amoxicillin 500 mg  ',
      unitId: unit.meta.id,
    )).meta.id;
  }

  test(
    'new install has only suggested units; FK enforcement is enabled',
    () async {
      expect(
        (await services.settings.units()).map((u) => u.name),
        containsAll(['Strip', 'Bottle', 'Box', 'Piece', 'Pack', 'Tube']),
      );
      for (final table in [
        'products',
        'batches',
        'stock_movements',
        'daily_records',
        'customers',
        'ledger_entries',
        'correction_audits',
        'app_settings',
      ]) {
        expect(await count(table), 0);
      }
      expect(
        Sqflite.firstIntValue(
          await database.connection.rawQuery('PRAGMA foreign_keys'),
        ),
        1,
      );
      await expectLater(
        services.inventory.createProduct(name: 'x', unitId: id()),
        throwsA(isA<ValidationException>()),
      );
    },
  );
  test(
    'stock movements are atomic, explicit, immutable and idempotent',
    () async {
      final item = await product();
      final a = await services.inventory.createBatch(
        productId: item,
        receivedDate: clock.today(),
        openingQuantity: 8,
      );
      final b = await services.inventory.createBatch(
        productId: item,
        receivedDate: clock.today(),
        openingQuantity: 12,
      );
      final operation = id();
      await services.inventory.adjust(
        operationId: operation,
        batchId: b.meta.id,
        delta: -3,
      );
      await services.inventory.adjust(
        operationId: operation,
        batchId: b.meta.id,
        delta: -3,
      );
      final batches = await services.inventory.batches(item);
      expect(batches.singleWhere((x) => x.meta.id == a.meta.id).quantity, 8);
      expect(batches.singleWhere((x) => x.meta.id == b.meta.id).quantity, 9);
      await expectLater(
        services.inventory.adjust(
          operationId: id(),
          batchId: b.meta.id,
          delta: -10,
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        services.inventory.adjust(
          operationId: operation,
          batchId: b.meta.id,
          delta: 3,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(await count('stock_movements'), 3);
      await expectLater(
        database.connection.update(
          'stock_movements',
          {'delta': 9},
          where: 'id=?',
          whereArgs: [operation],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.connection.delete(
          'stock_movements',
          where: 'id=?',
          whereArgs: [operation],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.connection.update(
          'batches',
          {'quantity': 2},
          where: 'id=?',
          whereArgs: [a.meta.id],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await services.inventory.reverse(
        operationId: id(),
        movementId: operation,
      );
      expect(
        (await services.inventory.batches(
          item,
        )).singleWhere((x) => x.meta.id == b.meta.id).quantity,
        12,
      );
      await expectLater(
        services.inventory.reverse(operationId: id(), movementId: operation),
        throwsA(isA<DatabaseException>()),
      );
      expect(await count('daily_records'), 0);
      expect(await count('ledger_entries'), 0);
      expect(
        await database.connection.rawQuery(
          '''SELECT b.id FROM batches b WHERE b.quantity!=
      (SELECT coalesce(sum(delta),0) FROM stock_movements WHERE batch_id=b.id)''',
        ),
        isEmpty,
      );
    },
  );
  test('failed opening batch leaves no date specs or half writes', () async {
    await expectLater(
      services.inventory.createBatch(
        productId: id(),
        receivedDate: clock.today(),
        openingQuantity: 5,
        expiry: DateSpec(
          calendar: DateCalendar.solarHijri,
          year: 1405,
          month: 7,
        ),
      ),
      throwsA(isA<ValidationException>()),
    );
    expect(await count('batches'), 0);
    expect(await count('date_specs'), 0);
    expect(await count('stock_movements'), 0);
  });
  test(
    'unit names, history locks, foreign keys and archive restrictions',
    () async {
      final unit = await services.settings.saveUnit(name: '  Capsule  ');
      await expectLater(
        services.settings.saveUnit(name: 'CAPSULE'),
        throwsA(isA<DatabaseException>()),
      );
      final item = await services.inventory.createProduct(
        name: 'x',
        unitId: unit.meta.id,
      );
      final batch = await services.inventory.createBatch(
        productId: item.meta.id,
        receivedDate: clock.today(),
        openingQuantity: 1,
      );
      await services.settings.saveUnit(
        id: unit.meta.id,
        name: 'Capsules',
        inactive: true,
      );
      await expectLater(
        services.settings.deleteUnusedUnit(unit.meta.id),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        services.inventory.createProduct(name: 'y', unitId: unit.meta.id),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        database.connection.update(
          'products',
          {'unit_id': (await services.settings.units()).first.meta.id},
          where: 'id=?',
          whereArgs: [item.meta.id],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.connection.update(
          'products',
          {'archived': 1},
          where: 'id=?',
          whereArgs: [item.meta.id],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await services.inventory.adjust(
        operationId: id(),
        batchId: batch.meta.id,
        delta: -1,
      );
      await database.connection.update(
        'products',
        {'archived': 1},
        where: 'id=?',
        whereArgs: [item.meta.id],
      );
      await expectLater(
        database.connection.delete(
          'products',
          where: 'id=?',
          whereArgs: [item.meta.id],
        ),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
  test(
    'daily dates unique, signed profit exact, zero distinct from missing',
    () async {
      expect(await services.dailyRecords.onDate(clock.today()), isNull);
      final record = await services.dailyRecords.save(
        date: clock.today(),
        sales: Money.parse('0'),
        profit: Money.parse('-12.34'),
      );
      await expectLater(
        services.dailyRecords.save(
          date: clock.today(),
          sales: Money.parse('1'),
          profit: Money.parse('2'),
        ),
        throwsA(isA<ValidationException>()),
      );
      await services.dailyRecords.save(
        id: record.meta.id,
        date: clock.today(),
        sales: Money.parse('50000.01'),
        profit: Money.parse('99999.99'),
      );
      expect(
        (await services.dailyRecords.onDate(clock.today()))!.sales.minor,
        5000001,
      );
      await expectLater(
        services.dailyRecords.save(
          date: BusinessDate(2026, 10, 6),
          sales: Money.parse('0'),
          profit: Money.parse('0'),
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        database.connection.insert('daily_records', {
          ...EntityMeta.create(clock).toRow(),
          'business_date': '2026-02-30',
          'sales_minor': 1,
          'profit_minor': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.connection.update('daily_records', {'sales_minor': 1.5}),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.connection.update('daily_records', {'sales_minor': -1}),
        throwsA(isA<DatabaseException>()),
      );
      expect(await count('stock_movements'), 0);
      expect(await count('ledger_entries'), 0);
    },
  );
  test(
    'ledger validates historical balance, ordering and correction audit',
    () async {
      final customer = await services.debtors.createCustomer(
        name: 'مریم',
        phone: '0700123456',
      );
      final debt = await services.debtors.addEntry(
        operationId: id(),
        customerId: customer.meta.id,
        date: BusinessDate(2026, 10, 1),
        kind: LedgerKind.debt,
        amount: Money.parse('500'),
        description: 'Amoxicillin برای خانواده',
      );
      await services.debtors.addEntry(
        operationId: id(),
        customerId: customer.meta.id,
        date: BusinessDate(2026, 10, 3),
        kind: LedgerKind.debt,
        amount: Money.parse('300'),
      );
      final paymentId = id();
      for (var retry = 0; retry < 2; retry++) {
        await services.debtors.addEntry(
          operationId: paymentId,
          customerId: customer.meta.id,
          date: BusinessDate(2026, 10, 2),
          kind: LedgerKind.payment,
          amount: Money.parse('200'),
        );
      }
      expect((await services.debtors.balance(customer.meta.id)).minor, 60000);
      await expectLater(
        services.debtors.editEntry(
          id: debt.meta.id,
          date: BusinessDate(2026, 10, 4),
          kind: LedgerKind.debt,
          amount: Money.parse('500'),
          description: '',
          reason: 'Date correction',
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        services.debtors.deleteEntry(debt.meta.id, reason: 'Mistake'),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        services.debtors.addEntry(
          operationId: id(),
          customerId: customer.meta.id,
          date: clock.today(),
          kind: LedgerKind.payment,
          amount: Money.parse('600.01'),
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(await count('correction_audits'), 0);
      final edited = await services.debtors.editEntry(
        id: debt.meta.id,
        date: debt.date,
        kind: debt.kind,
        amount: Money.parse('550'),
        description: debt.description,
        reason: 'Correct amount',
      );
      expect(edited.sequence, debt.sequence);
      expect(
        (await services.debtors.corrections(
          customer.meta.id,
        )).single.previous['amount_minor'],
        50000,
      );
      await expectLater(
        services.debtors.archiveCustomer(customer.meta.id, archived: true),
        throwsA(isA<ValidationException>()),
      );
      await services.debtors.deleteEntry(paymentId, reason: 'Entered in error');
      expect((await services.debtors.corrections(customer.meta.id)).length, 2);
      await expectLater(
        database.connection.delete('correction_audits'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await count('daily_records'), 0);
      expect(await count('stock_movements'), 0);
    },
  );
  test(
    'disk reopen retains UUIDs, Unicode, original dates, money, settings and history',
    () async {
      final item = await product();
      final spec = DateSpec(
        calendar: DateCalendar.solarHijri,
        year: 1405,
        month: 7,
      );
      final batch = await services.inventory.createBatch(
        productId: item,
        receivedDate: clock.today(),
        openingQuantity: 5,
        expiry: spec,
      );
      final customer = await services.debtors.createCustomer(
        name: 'مریم کریمی',
        phone: '0700123456',
        note: 'Persian و English',
      );
      await services.debtors.addEntry(
        operationId: id(),
        customerId: customer.meta.id,
        date: clock.today(),
        kind: LedgerKind.debt,
        amount: Money.parse('0.01'),
      );
      final daily = await services.dailyRecords.save(
        date: clock.today(),
        sales: Money.parse('12345.67'),
        profit: Money.parse('-0.01'),
      );
      await services.settings.setPreference('default_calendar', 'solarHijri');
      await database.close();
      database = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
        clock: clock,
      );
      services = AppServices(database, clock);
      final reopened = (await services.inventory.batches(item)).single;
      expect(reopened.meta.id, batch.meta.id);
      expect(reopened.expiry!.toMap(), spec.toMap());
      expect(reopened.quantity, 5);
      expect(
        (await services.inventory.movements(batch.meta.id)).single.delta,
        5,
      );
      expect((await services.debtors.customers()).single.phone, '0700123456');
      expect((await services.debtors.customers()).single.name, 'مریم کریمی');
      expect(
        (await services.dailyRecords.onDate(clock.today()))!.meta.id,
        daily.meta.id,
      );
      expect(
        (await services.dailyRecords.onDate(clock.today()))!.profit.minor,
        -1,
      );
      expect(
        (await services.settings.preference('default_calendar'))!.value,
        'solarHijri',
      );
      expect((await services.home.read(clock.today())).outstanding, BigInt.one);
      expect(
        await database.connection.rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
      expect(
        (await database.connection.rawQuery(
          'PRAGMA integrity_check',
        )).single.values.single,
        'ok',
      );
      expect(await count('units'), 6);
    },
  );
  test(
    'source date constraints reject impossible components and inconsistent ranges',
    () async {
      final db = database.connection;
      final spec = DateSpec(
        calendar: DateCalendar.gregorian,
        year: 2026,
        month: 4,
        day: 30,
      );
      final row = {
        'id': id(),
        ...spec.toMap(),
        'canonical_start': spec.range.start.iso,
        'canonical_end': spec.range.end.iso,
      };
      await expectLater(
        db.insert('date_specs', {...row, 'day': 31}),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.insert('date_specs', {...row, 'canonical_start': '2026-04-29'}),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.insert('date_specs', {
          ...row,
          'calendar': 'solarHijri',
          'year': 1400,
          'month': 12,
          'day': 30,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.insert('date_specs', {...row, 'precision': 'month', 'day': null}),
        throwsA(isA<DatabaseException>()),
      );
      await db.insert('date_specs', row);
      await expectLater(
        db.update('date_specs', {'day': 29}),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
  test(
    'inactive unit does not block editing an existing product with unchanged unit',
    () async {
      final unit = (await services.settings.units()).first;
      final item = await services.inventory.createProduct(
        name: 'Original',
        unitId: unit.meta.id,
      );
      await services.settings.saveUnit(
        id: unit.meta.id,
        name: unit.name,
        inactive: true,
      );
      await database.connection.update(
        'products',
        {'name': 'Updated', 'name_key': 'updated', 'unit_id': unit.meta.id},
        where: 'id=?',
        whereArgs: [item.meta.id],
      );
      expect((await services.inventory.products()).single.name, 'Updated');
    },
  );
  test(
    'deleted ledger operation cannot replay and sequence never reuses deleted order',
    () async {
      final customer = await services.debtors.createCustomer(name: 'Test');
      final operation = id();
      final old = await services.debtors.addEntry(
        operationId: operation,
        customerId: customer.meta.id,
        date: clock.today(),
        kind: LedgerKind.debt,
        amount: Money.parse('10'),
      );
      await services.debtors.deleteEntry(operation, reason: 'Mistake');
      await expectLater(
        services.debtors.addEntry(
          operationId: operation,
          customerId: customer.meta.id,
          date: clock.today(),
          kind: LedgerKind.debt,
          amount: Money.parse('10'),
        ),
        throwsA(isA<ValidationException>()),
      );
      final next = await services.debtors.addEntry(
        operationId: id(),
        customerId: customer.meta.id,
        date: clock.today(),
        kind: LedgerKind.debt,
        amount: Money.parse('10'),
      );
      expect(next.sequence, greaterThan(old.sequence));
    },
  );
  test(
    'failed migration rolls back version and schema and preserves original records',
    () async {
      final badPath = p.join(directory.path, 'conflicting-v1.sqlite');
      final old = await databaseFactoryFfi.openDatabase(
        badPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) => migrate(db, 0, 1),
        ),
      );
      for (var i = 0; i < 2; i++) {
        await old.insert('units', {
          ...EntityMeta.create(clock).toRow(),
          'name': 'Duplicate',
          'name_key': 'duplicate',
          'inactive': 0,
        });
      }
      await old.close();
      await expectLater(
        AppDatabase.open(
          factory: databaseFactoryFfi,
          path: badPath,
          clock: clock,
        ),
        throwsA(isA<DatabaseException>()),
      );
      final unchanged = await databaseFactoryFfi.openDatabase(badPath);
      expect(await unchanged.getVersion(), 1);
      expect((await unchanged.query('units')).length, 2);
      expect(
        await unchanged.rawQuery(
          "SELECT name FROM sqlite_master WHERE name='sequence_counters'",
        ),
        isEmpty,
      );
      await unchanged.close();
    },
  );
  test(
    'v1 upgrade preserves data and installs v2 guards; newer versions fail closed',
    () async {
      await database.close();
      final oldPath = p.join(directory.path, 'v1.sqlite');
      final old = await databaseFactoryFfi.openDatabase(
        oldPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) => migrate(db, 0, 1),
        ),
      );
      final row = {
        ...EntityMeta.create(clock).toRow(),
        'name': 'Legacy unit',
        'name_key': 'legacy unit',
        'inactive': 0,
      };
      await old.insert('units', row);
      await old.close();
      database = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: oldPath,
        clock: clock,
      );
      expect(await database.connection.getVersion(), schemaVersion);
      expect(
        (await database.connection.query('units')).single['id'],
        row['id'],
      );
      await expectLater(
        database.connection.insert('units', {...row, 'id': id()}),
        throwsA(isA<DatabaseException>()),
      );
      await database.connection.setVersion(schemaVersion + 1);
      await database.close();
      await expectLater(
        AppDatabase.open(
          factory: databaseFactoryFfi,
          path: oldPath,
          clock: clock,
        ),
        throwsA(isA<StateError>()),
      );
      database = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
        clock: clock,
      );
    },
  );
}
