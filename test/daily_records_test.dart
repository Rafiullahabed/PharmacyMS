import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import 'package:pharmacyms/core/data/schema.dart';
import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/core/domain/entity.dart';
import 'package:pharmacyms/core/domain/money.dart';
import 'package:pharmacyms/core/domain/validation.dart';
import 'package:pharmacyms/features/daily_records/domain/daily_record.dart';
import 'package:pharmacyms/features/daily_records/domain/daily_report.dart';
import 'package:pharmacyms/features/debtors/domain/debt.dart';
import 'support/inventory_database.dart';

void main() {
  late InventoryDatabase f;
  String uuid() => const Uuid().v4();
  setUp(() async {
    f = InventoryDatabase();
    await f.open();
  });
  tearDown(() => f.close());
  Future<DailyRecord> save(
    String date, {
    String sales = '0',
    String profit = '0',
    String? operation,
    String? id,
    String? note,
  }) => f.services.dailyRecords.save(
    operationId: operation,
    id: id,
    date: BusinessDate.parse(date),
    sales: Money.parse(sales),
    profit: Money.parse(profit),
    note: note,
  );

  test(
    'preset and custom ranges use inclusive civil days across leap/month/year boundaries',
    () {
      final leap = BusinessDate(2024, 3, 1);
      final last7 = ReportPeriod.last7Days.range(leap);
      expect(last7.start.iso, '2024-02-24');
      expect(last7.days, 7);
      expect(last7.previous!.start.iso, '2024-02-17');
      expect(last7.previous!.end.iso, '2024-02-23');
      expect(ReportPeriod.today.range(leap).days, 1);
      expect(ReportPeriod.thisMonth.range(BusinessDate(2024, 2, 29)).days, 29);
      expect(ReportPeriod.thisMonth.range(BusinessDate(2100, 2, 28)).days, 28);
      expect(
        ReportPeriod.last7Days.range(BusinessDate(2026, 1, 2)).start.iso,
        '2025-12-27',
      );
      expect(
        ReportRange(BusinessDate(1, 1, 1), BusinessDate(1, 1, 1)).previous,
        isNull,
      );
      expect(
        () => ReportRange(leap, BusinessDate(2024, 2, 29)),
        throwsA(isA<ValidationException>()),
      );
    },
  );
  test(
    'unique dates, exact normalized decimals, zero and loss persist after reopening',
    () async {
      final first = await save(
        '2026-10-05',
        sales: '۵۰٬۰۰۰٫۰۱',
        profit: '−١٢٫٣٤',
        note: 'یادداشت mixed',
      );
      expect(first.sales.minor, 5000001);
      expect(first.profit.minor, -1234);
      await expectLater(
        save('2026-10-05', sales: '1'),
        throwsA(isA<ValidationException>()),
      );
      await save('2026-10-04', profit: '999'); // Profit may exceed sales.
      await save('2026-10-03');
      await f.reopen();
      final read = (await f.services.dailyRecords.byId(first.meta.id))!;
      expect(read.note, 'یادداشت mixed');
      expect(read.sales, first.sales);
      expect(read.profit, first.profit);
      expect(
        (await f.services.dailyRecords.onDate(
          BusinessDate(2026, 10, 3),
        ))!.sales.minor,
        0,
      );
      expect(
        await f.services.dailyRecords.onDate(BusinessDate(2026, 10, 2)),
        isNull,
      );
      expect(await f.count('daily_records'), 3);
    },
  );
  test(
    'future dates and negative sales reject; invalid precision never rounds',
    () async {
      await expectLater(
        save('2026-10-06'),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        save('2026-10-05', sales: '-0.01'),
        throwsA(isA<ValidationException>()),
      );
      expect(() => Money.parse('۱۲٫۳۴۵'), throwsA(isA<ValidationException>()));
      expect(await f.count('daily_records'), 0);
    },
  );
  test(
    'edits replace amounts and move date; conflict keeps both originals intact',
    () async {
      final a = await save('2026-10-05', sales: '1.01', profit: '0.10'),
          b = await save('2026-10-04', sales: '2');
      final edited = await save(
        '2026-10-03',
        id: a.meta.id,
        sales: '0',
        profit: '-1.01',
        note: 'correction',
      );
      expect(edited.meta.id, a.meta.id);
      expect(edited.meta.createdAt, a.meta.createdAt);
      expect(await f.services.dailyRecords.onDate(a.date), isNull);
      await expectLater(
        save('2026-10-04', id: a.meta.id),
        throwsA(isA<ValidationException>()),
      );
      expect(
        (await f.services.dailyRecords.byId(a.meta.id))!.profit.minor,
        -101,
      );
      expect((await f.services.dailyRecords.byId(b.meta.id))!.sales.minor, 200);
      expect(await f.count('daily_records'), 2);
    },
  );
  test(
    'concurrent identical operation saves once; mismatched receipt rejects',
    () async {
      final operation = uuid();
      final results = await Future.wait([
        save('2026-10-05', operation: operation, sales: '3.14'),
        save('2026-10-05', operation: operation, sales: '3.14'),
      ]);
      expect(results[0].meta.id, results[1].meta.id);
      expect(await f.count('daily_records'), 1);
      expect(await f.count('daily_operations'), 1);
      await f.reopen();
      expect(
        (await save('2026-10-05', operation: operation, sales: '3.14')).meta.id,
        results[0].meta.id,
      );
      await expectLater(
        save('2026-10-05', operation: operation, sales: '9'),
        throwsA(isA<ValidationException>()),
      );
      final outcomes = await Future.wait([
        for (var i = 0; i < 2; i++)
          save(
            '2026-10-04',
            operation: uuid(),
          ).then((_) => true, onError: (_) => false),
      ]);
      expect(outcomes.where((ok) => ok).length, 1);
    },
  );
  test(
    'deletion refreshes coverage; durable retries cannot resurrect or overwrite later edits',
    () async {
      final operation = uuid(), deletedOperation = uuid();
      final a = await save('2026-10-05', operation: operation, sales: '1');
      await save('2026-10-05', id: a.meta.id, sales: '2');
      await save('2026-10-05', operation: operation, sales: '1');
      expect((await f.services.dailyRecords.byId(a.meta.id))!.sales.minor, 200);
      await f.services.dailyRecords.delete(
        a.meta.id,
        operationId: deletedOperation,
      );
      await f.reopen();
      await f.services.dailyRecords.delete(
        a.meta.id,
        operationId: deletedOperation,
      );
      await save('2026-10-05', operation: operation, sales: '1');
      expect(await f.count('daily_records'), 0);
      final report = await f.services.dailyRecords.report(
        ReportPeriod.today.range(f.clock.today()),
      );
      expect(report.totals.recorded, 0);
      expect(report.dayAt(0).value(false), isNull);
      expect(report.change(false), 'Not available');
    },
  );
  test('a receipt failure rolls back the entire record write', () async {
    await f.database.connection.execute(
      "CREATE TRIGGER fail_daily_receipt BEFORE INSERT ON daily_operations BEGIN SELECT RAISE(ABORT,'injected full storage'); END",
    );
    await expectLater(save('2026-10-05', operation: uuid()), throwsException);
    expect(await f.count('daily_records'), 0);
    expect(await f.count('daily_operations'), 0);
    await f.database.connection.execute('DROP TRIGGER fail_daily_receipt');
    await save('2026-10-05', operation: uuid());
    expect(await f.count('daily_records'), 1);
  });
  test(
    'inclusive reports, missing days, zero values and monthly coverage reconcile after edits',
    () async {
      await save(
        '2024-02-27',
        sales: '900',
      ); // Outside current period, inside previous.
      final a = await save('2024-02-28', sales: '0.10', profit: '-0.01');
      await save('2024-02-29');
      await save('2024-03-02', sales: '0.20', profit: '0.01');
      await save(
        '2024-03-03',
        sales: '999',
      ); // Outside both current boundaries.
      final range = ReportRange(
        BusinessDate(2024, 2, 28),
        BusinessDate(2024, 3, 2),
      );
      final report = await f.services.dailyRecords.report(range);
      expect(report.totals.sales, BigInt.from(30));
      expect(report.totals.profit, BigInt.zero);
      expect(report.totals.coverage, '3 of 4 days recorded');
      expect(report.records.map((r) => r.date.iso), [
        '2024-03-02',
        '2024-02-29',
        '2024-02-28',
      ]);
      expect(report.dayAt(1).value(false), BigInt.zero);
      expect(report.dayAt(2).value(false), isNull);
      expect(report.months.map((m) => m.totals.coverage), [
        '2 of 2 days recorded',
        '1 of 2 days recorded',
      ]);
      expect(report.months.first.totals.profit, BigInt.from(-1));
      await save('2024-02-28', id: a.meta.id, sales: '0.11', profit: '-1');
      final changed = await f.services.dailyRecords.report(range);
      expect(changed.totals.sales, BigInt.from(31));
      expect(changed.totals.profit, BigInt.from(-99));
      await f.services.dailyRecords.delete(a.meta.id);
      expect(
        (await f.services.dailyRecords.report(range)).totals.coverage,
        '2 of 4 days recorded',
      );
    },
  );
  test(
    'missing month has null values; large exact totals do not overflow SQLite or Money',
    () async {
      final rows = [
        for (var i = 0; i < 1100; i++)
          DailyRecord(
            meta: EntityMeta.create(f.clock),
            date: shiftDay(BusinessDate(2020, 1, 1), i),
            sales: Money.fromMinor(Money.maxMinor),
            profit: Money.fromMinor(-Money.maxMinor),
          ),
      ];
      final batch = f.database.connection.batch();
      for (final r in rows) {
        batch.insert('daily_records', {
          ...r.meta.toRow(),
          'business_date': r.date.iso,
          'sales_minor': r.sales.minor,
          'profit_minor': r.profit.minor,
        });
      }
      await batch.commit(noResult: true);
      final report = await f.services.dailyRecords.report(
        ReportRange(BusinessDate(2020, 1, 1), BusinessDate(2024, 3, 1)),
      );
      expect(
        report.totals.sales,
        BigInt.from(Money.maxMinor) * BigInt.from(1100),
      );
      expect(
        formatMinorUnits(report.totals.profit),
        'AFN -99,000,000,000,000,000.00',
      );
      expect(report.months.last.value(false), isNull);
      expect(report.months.last.totals.coverage, '0 of 1 days recorded');
    },
  );
  test(
    'comparison avoids zero/no-data baselines and discloses incomplete coverage',
    () async {
      final range = ReportRange(
        BusinessDate(2026, 10, 4),
        BusinessDate(2026, 10, 5),
      );
      await save('2026-10-02');
      await save('2026-10-05', sales: '10', profit: '-2');
      var report = await f.services.dailyRecords.report(range);
      expect(report.change(false), 'Not available');
      expect(report.change(true), 'Not available');
      await save('2026-10-03', sales: '4', profit: '-4');
      report = await f.services.dailyRecords.report(range);
      expect(report.change(false), '+150.00%');
      expect(report.change(true), '+50.00%');
      expect(report.previousTotals.coverage, '2 of 2 days recorded');
      expect(report.totals.coverage, '1 of 2 days recorded');
    },
  );
  test(
    'financial creation/edit/deletion leaves inventory and debt byte-for-byte unchanged',
    () async {
      final unit = (await f.services.settings.units()).first;
      final product = await f.services.inventory.createProduct(
        name: 'Inventory',
        unitId: unit.meta.id,
      );
      await f.services.inventory.createBatch(
        productId: product.meta.id,
        receivedDate: f.clock.today(),
        openingQuantity: 8,
      );
      final customer = await f.services.debtors.createCustomer(name: 'مریم');
      await f.services.debtors.addEntry(
        operationId: uuid(),
        customerId: customer.meta.id,
        kind: LedgerKind.debt,
        date: f.clock.today(),
        amount: Money.parse('500'),
      );
      final tables = [
        'products',
        'batches',
        'stock_movements',
        'customers',
        'ledger_entries',
        'correction_audits',
      ];
      final before = {
        for (final table in tables)
          table: await f.database.connection.query(table),
      };
      final a = await save('2026-10-05', sales: '50000', profit: '1000');
      await save('2026-10-05', id: a.meta.id, sales: '49999.99', profit: '-1');
      await f.services.dailyRecords.delete(a.meta.id);
      for (final table in tables) {
        expect(await f.database.connection.query(table), before[table]);
      }
    },
  );
  test(
    'v3 upgrade preserves daily rows and installs immutable durable receipts',
    () async {
      final a = await save('2026-10-05', sales: '12.34', profit: '-1');
      await f.database.connection.execute('DROP TABLE daily_operations');
      await f.database.connection.execute('DROP TABLE debt_operations');
      await f.database.connection.execute('DROP INDEX customer_phone_search');
      await f.database.connection.execute(
        'ALTER TABLE customers DROP COLUMN phone_key',
      );
      await f.database.connection.setVersion(3);
      await f.reopen();
      expect(await f.database.connection.getVersion(), schemaVersion);
      expect(
        (await f.services.dailyRecords.byId(a.meta.id))!.sales.minor,
        1234,
      );
      await save('2026-10-05', operation: uuid(), id: a.meta.id, sales: '1');
      await expectLater(
        f.database.connection.delete('daily_operations'),
        throwsException,
      );
      expect(
        await f.database.connection.rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
      expect(
        (await f.database.connection.rawQuery(
          'PRAGMA integrity_check',
        )).single.values.single,
        'ok',
      );
    },
  );
}
