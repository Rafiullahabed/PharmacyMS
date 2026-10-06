import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:pharmacyms/core/data/schema.dart';
import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/core/domain/money.dart';
import 'package:pharmacyms/core/domain/validation.dart';
import 'package:pharmacyms/features/debtors/domain/debt.dart';
import 'support/inventory_database.dart';

void main() {
  late InventoryDatabase f;
  DebtRepository repo() => f.services.debtors;
  String id() => const Uuid().v4();
  setUp(() async {
    f = InventoryDatabase();
    await f.open();
  });
  tearDown(() => f.close());
  Future<Customer> customer({
    String name = 'مریم',
    String? phone,
    String? note,
  }) => repo().createCustomer(name: name, phone: phone, note: note);
  Future<LedgerEntry> entry(
    Customer c,
    String value, {
    LedgerKind kind = LedgerKind.debt,
    int day = 5,
    String description = '',
    String? operation,
  }) => repo().addEntry(
    operationId: operation ?? id(),
    customerId: c.meta.id,
    date: BusinessDate(2026, 10, day),
    kind: kind,
    amount: Money.parse(value),
    description: description,
  );
  LedgerDraft draft(
    String value, {
    LedgerKind kind = LedgerKind.payment,
    int day = 5,
  }) => LedgerDraft(
    date: BusinessDate(2026, 10, day),
    kind: kind,
    amount: Money.parse(value),
  );

  test(
    'customer identity, optional phone, exact Persian content and duplicate-name discovery',
    () async {
      const note = '  یادداشت\nAmoxicillin برای خانواده  ';
      final a = await customer(name: '  مريم كريمي  ', note: note),
          b = await customer(name: 'مریم کریمی', phone: '۰۷۰۰ ۱۲۳۴۵۶');
      expect(a.name, 'مريم كريمي');
      expect(a.phone, isNull);
      expect(a.note, note);
      expect(
        (await repo().similarCustomers('مریم کریمی')).map((c) => c.meta.id),
        containsAll([a.meta.id, b.meta.id]),
      );
      expect(
        (await repo().similarCustomers(
          'مریم کریمی',
          excludingId: a.meta.id,
        )).single.meta.id,
        b.meta.id,
      );
      final updated = await repo().saveCustomer(
        operationId: id(),
        id: a.meta.id,
        name: 'Maryam مریم',
        phone: '00700',
        note: note,
      );
      expect(updated.meta.id, a.meta.id);
      expect(updated.meta.createdAt, a.meta.createdAt);
      expect(updated.phone, '00700');
      await f.reopen();
      expect((await repo().customer(a.meta.id)).note, note);
      await expectLater(
        customer(name: '  '),
        throwsA(isA<ValidationException>()),
      );
    },
  );
  test(
    'name/phone search and All Outstanding Settled filters preserve global active totals',
    () async {
      final owing = await customer(name: 'مريم كريمي', phone: '۰۷۰۰ (۱۲۳)-۴۵۶'),
          settled = await customer(name: 'Settled'),
          archived = await customer(name: 'Archived');
      await entry(owing, '600');
      await repo().archiveCustomer(archived.meta.id, archived: true);
      expect((await repo().searchCustomers()).total, 2);
      expect(
        (await repo().searchCustomers(
          filter: CustomerFilter.outstanding,
        )).items.single.customer.meta.id,
        owing.meta.id,
      );
      expect(
        (await repo().searchCustomers(
          filter: CustomerFilter.settled,
        )).items.single.customer.meta.id,
        settled.meta.id,
      );
      for (final text in ['مریم کریمی', '0700123456', '٠٧٠٠١٢٣٤٥٦']) {
        expect(
          (await repo().searchCustomers(
            search: text,
          )).items.single.customer.meta.id,
          owing.meta.id,
        );
      }
      expect((await repo().searchCustomers(search: '+')).items, isEmpty);
      expect(
        (await repo().searchCustomers(search: 'missing')).outstanding,
        BigInt.from(60000),
      );
      expect(
        (await repo().searchCustomers(
          archived: true,
        )).items.single.customer.meta.id,
        archived.meta.id,
      );
    },
  );
  test(
    '500 + 300 - 200 is 600 with stable backdated running balances and exact preview',
    () async {
      final c = await customer();
      final first = await entry(c, '۵۰۰', day: 1),
          second = await entry(c, '300', day: 3),
          payment = await entry(
            c,
            '٢٠٠',
            kind: LedgerKind.payment,
            day: 2,
            description: 'Amoxicillin برای خانواده\nپرداخت نقدی',
          );
      expect((await repo().balance(c.meta.id)).minor, 60000);
      final history = await repo().history(c.meta.id);
      expect(history.lines.map((l) => l.entry.meta.id), [
        second.meta.id,
        payment.meta.id,
        first.meta.id,
      ]);
      expect(history.lines.map((l) => l.balance.minor), [60000, 30000, 50000]);
      final preview = await repo().preview(c.meta.id, draft: draft('600'));
      expect(preview.before.minor, 60000);
      expect(preview.after.minor, 0);
      expect(preview.atEntry!.minor, 0);
      expect(
        await f.count('ledger_entries'),
        3,
      ); // Preview has no side effects.
      await f.reopen();
      expect(
        (await repo().history(c.meta.id)).lines[1].entry.description,
        payment.description,
      );
    },
  );
  test(
    'overpayments, historical deficits, future dates and nonpositive amounts leave data intact',
    () async {
      final c = await customer();
      await entry(c, '500', day: 3);
      for (final operation in [
        () => entry(c, '500.01', kind: LedgerKind.payment),
        () => entry(c, '1', kind: LedgerKind.payment, day: 2),
        () => entry(c, '1', day: 6),
        () => entry(c, '0'),
        () => entry(c, '-1'),
      ]) {
        await expectLater(operation(), throwsA(isA<ValidationException>()));
      }
      await expectLater(
        repo().preview(c.meta.id, draft: draft('1', day: 2)),
        throwsA(isA<ValidationException>()),
      );
      expect(await f.count('ledger_entries'), 1);
      expect(await f.count('correction_audits'), 0);
      expect(await f.count('debt_operations'), 2);
    },
  );
  test(
    'edits and deletion reject earlier negative balances even when final balance would be positive',
    () async {
      final c = await customer(), debt = await entry(c, '500', day: 1);
      await entry(c, '200', kind: LedgerKind.payment, day: 2);
      await entry(c, '1000', day: 5);
      await expectLater(
        repo().editEntry(
          operationId: id(),
          id: debt.meta.id,
          date: BusinessDate(2026, 10, 3),
          kind: LedgerKind.debt,
          amount: debt.amount,
          description: debt.description,
          reason: 'Wrong date',
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        repo().preview(c.meta.id, entryId: debt.meta.id, deleting: true),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        repo().deleteEntry(debt.meta.id, operationId: id(), reason: 'Mistake'),
        throwsA(isA<ValidationException>()),
      );
      expect((await repo().balance(c.meta.id)).minor, 130000);
      expect((await repo().entry(debt.meta.id))!.date, debt.date);
      expect(await f.count('correction_audits'), 0);
    },
  );
  test(
    'corrections preserve sequence and complete before/after audit including type and Unicode',
    () async {
      final c = await customer();
      await entry(c, '500', day: 1);
      final original = await entry(
        c,
        '300',
        day: 2,
        description: 'نسخه\nAmoxicillin',
      );
      final edited = await repo().editEntry(
        operationId: id(),
        id: original.meta.id,
        date: original.date,
        kind: LedgerKind.payment,
        amount: Money.parse('200.01'),
        description: 'اصلاح توضیح',
        reason: 'Corrected type',
      );
      expect(edited.sequence, original.sequence);
      expect(edited.meta.createdAt, original.meta.createdAt);
      expect((await repo().balance(c.meta.id)).minor, 29999);
      final audit = (await repo().corrections(c.meta.id)).single;
      expect(audit.previous['description'], original.description);
      expect(audit.previous['kind'], 'debt');
      expect(audit.next!['kind'], 'payment');
      expect(audit.reason, 'Corrected type');
      await repo().deleteEntry(
        original.meta.id,
        operationId: id(),
        reason: 'Duplicate',
      );
      await f.reopen();
      expect((await repo().balance(c.meta.id)).minor, 50000);
      expect((await repo().corrections(c.meta.id)).length, 2);
      expect(await repo().entry(original.meta.id), isNull);
      await expectLater(
        f.database.connection.delete('correction_audits'),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
  test(
    'customer and ledger operations reconcile duplicate taps and durable correction retries',
    () async {
      final op = id();
      final customers = await Future.wait([
        for (var i = 0; i < 2; i++)
          repo().saveCustomer(operationId: op, name: 'Same', phone: '007'),
      ]);
      expect(customers[0].meta.id, customers[1].meta.id);
      final c = customers.first, add = id();
      final entries = await Future.wait([
        entry(c, '500', operation: add),
        entry(c, '500', operation: add),
      ]);
      expect(entries[0].meta.id, entries[1].meta.id);
      final edit = id();
      Future<LedgerEntry> correct() => repo().editEntry(
        operationId: edit,
        id: add,
        date: BusinessDate(2026, 10, 5),
        kind: LedgerKind.debt,
        amount: Money.parse('300'),
        description: 'corrected',
        reason: 'Wrong amount',
      );
      await correct();
      await f.reopen();
      await correct();
      expect(await f.count('correction_audits'), 1);
      await expectLater(
        repo().saveCustomer(operationId: op, name: 'Different'),
        throwsA(isA<ValidationException>()),
      );
      final deletion = id();
      await repo().deleteEntry(add, operationId: deletion, reason: 'Duplicate');
      await f.reopen();
      await repo().deleteEntry(add, operationId: deletion, reason: 'Duplicate');
      expect(await f.count('correction_audits'), 2);
      expect(await f.count('ledger_entries'), 0);
      await correct();
      expect(
        await f.count('ledger_entries'),
        0,
      ); // Old edit retry never resurrects.
      await expectLater(
        entry(c, '500', operation: add),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        f.database.connection.delete('debt_operations'),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
  test(
    'failure while writing audit or receipt rolls back ledger and customer changes',
    () async {
      final c = await customer(), debt = await entry(c, '500');
      await f.database.connection.execute(
        "CREATE TRIGGER fail_audit BEFORE INSERT ON correction_audits BEGIN SELECT RAISE(ABORT,'injected storage failure'); END",
      );
      await expectLater(
        repo().editEntry(
          operationId: id(),
          id: debt.meta.id,
          date: debt.date,
          kind: debt.kind,
          amount: Money.parse('1'),
          description: 'changed',
          reason: 'Correction',
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect((await repo().balance(c.meta.id)).minor, 50000);
      expect(await f.count('correction_audits'), 0);
      await f.database.connection.execute('DROP TRIGGER fail_audit');
      await f.database.connection.execute(
        "CREATE TRIGGER fail_receipt BEFORE INSERT ON debt_operations BEGIN SELECT RAISE(ABORT,'injected storage failure'); END",
      );
      await expectLater(
        repo().saveCustomer(operationId: id(), id: c.meta.id, name: 'Changed'),
        throwsA(isA<DatabaseException>()),
      );
      expect((await repo().customer(c.meta.id)).name, c.name);
    },
  );
  test(
    'settlement allows archive/restore while archived ledger and history stay protected',
    () async {
      final c = await customer(), debt = await entry(c, '500');
      await expectLater(
        repo().archiveCustomer(c.meta.id, archived: true, operationId: id()),
        throwsA(isA<ValidationException>()),
      );
      final payment = await entry(c, '500', kind: LedgerKind.payment);
      final operation = id();
      await repo().archiveCustomer(
        c.meta.id,
        archived: true,
        operationId: operation,
      );
      await repo().archiveCustomer(
        c.meta.id,
        archived: true,
        operationId: operation,
      );
      expect((await repo().history(c.meta.id)).lines.length, 2);
      expect((await repo().searchCustomers()).items, isEmpty);
      await expectLater(entry(c, '1'), throwsA(isA<ValidationException>()));
      await expectLater(
        repo().deleteEntry(payment.meta.id, reason: 'Wrong'),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        repo().editEntry(
          id: debt.meta.id,
          date: debt.date,
          kind: debt.kind,
          amount: debt.amount,
          description: 'changed',
          reason: 'Correction',
        ),
        throwsA(isA<ValidationException>()),
      );
      await repo().archiveCustomer(
        c.meta.id,
        archived: false,
        operationId: id(),
      );
      expect((await repo().customer(c.meta.id)).meta.id, c.meta.id);
      expect(
        (await repo().searchCustomers(
          filter: CustomerFilter.settled,
        )).items.single.customer.meta.id,
        c.meta.id,
      );
    },
  );
  test(
    'paged history has stable same-day ordering and correct balances at page boundaries',
    () async {
      final c = await customer();
      final entries = <LedgerEntry>[];
      for (var i = 0; i < 65; i++) {
        entries.add(await entry(c, '0.01'));
      }
      final first = await repo().history(c.meta.id),
          second = await repo().history(c.meta.id, offset: 50);
      expect(first.total, 65);
      expect(first.lines.length, 50);
      expect(first.lines.first.balance.minor, 65);
      expect(first.lines.last.balance.minor, 16);
      expect(second.lines.first.balance.minor, 15);
      expect(second.lines.last.balance.minor, 1);
      expect(
        [...first.lines, ...second.lines].map((l) => l.entry.meta.id),
        entries.reversed.map((e) => e.meta.id),
      );
      final maxSequence = entries.last.sequence;
      await repo().deleteEntry(entries.last.meta.id, reason: 'Mistake');
      final next = await entry(c, '0.01');
      expect(next.sequence, greaterThan(maxSequence));
    },
  );
  test(
    'customer pagination and aggregate Home totals remain exact beyond single-customer money bounds',
    () async {
      for (var i = 0; i < 52; i++) {
        final c = await customer(
          name: 'Customer ${i.toString().padLeft(2, '0')}',
        );
        if (i < 2) await entry(c, Money.fromMinor(Money.maxMinor).decimal);
      }
      final first = await repo().searchCustomers(),
          second = await repo().searchCustomers(offset: 50);
      expect(first.total, 52);
      expect(second.items.length, 2);
      expect(first.outstanding, BigInt.from(Money.maxMinor) * BigInt.two);
      expect(
        (await f.services.home.read(f.clock.today())).outstanding,
        first.outstanding,
      );
      final c = first.items.first.customer;
      await expectLater(entry(c, '0.01'), throwsA(isA<ValidationException>()));
    },
  );
  test(
    'plain item suggestions and debt changes do not touch inventory or daily data',
    () async {
      final unit = (await f.services.settings.units()).first;
      final product = await f.services.inventory.createProduct(
        name: 'Amoxicillin کریمی',
        unitId: unit.meta.id,
      );
      await f.services.inventory.createBatch(
        productId: product.meta.id,
        receivedDate: f.clock.today(),
        openingQuantity: 12,
      );
      await f.services.dailyRecords.save(
        date: f.clock.today(),
        sales: Money.parse('50000'),
        profit: Money.parse('-1.01'),
      );
      final tables = [
        'products',
        'units',
        'batches',
        'date_specs',
        'stock_movements',
        'inventory_operations',
        'daily_records',
        'daily_operations',
      ];
      final before = {
        for (final table in tables)
          table: await f.database.connection.query(table),
      };
      expect(await repo().productNames('كريمي'), [product.name]);
      final c = await customer(),
          debt = await entry(
            c,
            '500',
            description: '${product.name} برای خانواده',
          );
      await entry(c, '300');
      final payment = await entry(c, '200', kind: LedgerKind.payment);
      await repo().editEntry(
        operationId: id(),
        id: debt.meta.id,
        date: debt.date,
        kind: debt.kind,
        amount: Money.parse('501'),
        description: debt.description,
        reason: 'Correction',
      );
      await repo().deleteEntry(
        payment.meta.id,
        reason: 'Correction',
        operationId: id(),
      );
      for (final table in tables) {
        expect(await f.database.connection.query(table), before[table]);
      }
    },
  );
  test(
    'v4 migration preserves old customer phone, ledger, audit and installs searchable keys',
    () async {
      final c = await customer(phone: '۰۷۰۰\t(۱۲۳)-۴۵۶'),
          debt = await entry(c, '500');
      await repo().editEntry(
        id: debt.meta.id,
        date: debt.date,
        kind: debt.kind,
        amount: Money.parse('600'),
        description: 'فارسی',
        reason: 'Correction',
      );
      final original = await f.database.connection.query('correction_audits');
      await f.database.connection.execute('DROP TABLE debt_operations');
      await f.database.connection.execute('DROP INDEX customer_phone_search');
      await f.database.connection.execute(
        'ALTER TABLE customers DROP COLUMN phone_key',
      );
      await f.database.connection.setVersion(4);
      await f.reopen();
      expect(await f.database.connection.getVersion(), schemaVersion);
      expect(
        (await repo().searchCustomers(
          search: '0700123456',
        )).items.single.customer.phone,
        c.phone,
      );
      expect((await repo().balance(c.meta.id)).minor, 60000);
      expect(await f.database.connection.query('correction_audits'), original);
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
