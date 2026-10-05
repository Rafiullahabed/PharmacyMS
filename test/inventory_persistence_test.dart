import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;
import 'package:uuid/uuid.dart';
import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/core/domain/validation.dart';
import 'package:pharmacyms/core/data/schema.dart';
import 'package:pharmacyms/features/inventory/domain/inventory.dart';
import 'package:pharmacyms/features/inventory/application/inventory_controller.dart';
import 'support/inventory_database.dart';

void main() {
  late InventoryDatabase fixture;
  late String unitId;
  String id() => const Uuid().v4();
  InventoryRepository repo() => fixture.services.inventory;
  DateSpec full(int day, {int month = 10}) => DateSpec(
    calendar: DateCalendar.gregorian,
    year: 2026,
    month: month,
    day: day,
  );
  Future<Product> product({
    int minimum = 0,
    int warning = 30,
    String name = 'Amoxicillin 500 mg',
  }) => repo().createProduct(
    name: name,
    unitId: unitId,
    minimumStock: minimum,
    warningDays: warning,
  );
  Future<Batch> batch(
    Product p,
    int quantity, {
    DateSpec? expiry,
    DateSpec? production,
    String? label,
  }) => repo().saveBatch(
    operationId: id(),
    productId: p.meta.id,
    draft: BatchDraft(
      receivedDate: fixture.clock.today(),
      quantity: quantity,
      expiry: expiry,
      production: production,
      label: label,
    ),
  );
  Future<void> reconcile() async {
    expect(
      await fixture.database.connection.rawQuery(
        '''SELECT b.id FROM batches b WHERE b.quantity !=
      (SELECT coalesce(sum(delta),0) FROM stock_movements WHERE batch_id=b.id)''',
      ),
      isEmpty,
    );
    final movements = await fixture.database.connection.query(
      'stock_movements',
      orderBy: 'sequence',
    );
    final totals = <String, int>{};
    for (final m in movements) {
      final batch = m['batch_id'] as String;
      totals[batch] = (totals[batch] ?? 0) + (m['delta'] as int);
      expect(m['resulting_quantity'], totals[batch]);
      expect(totals[batch], greaterThanOrEqualTo(0));
    }
    for (final table in [
      'daily_records',
      'customers',
      'ledger_entries',
      'correction_audits',
    ]) {
      expect(
        await fixture.count(table),
        0,
        reason: 'Inventory must not write $table',
      );
    }
  }

  setUp(() async {
    fixture = InventoryDatabase();
    await fixture.open();
    unitId = (await fixture.services.settings.units()).first.meta.id;
  });
  tearDown(() => fixture.close());

  test(
    'initial stock rollback removes product, dates, history and receipt',
    () async {
      final operation = id();
      await expectLater(
        repo().saveProduct(
          operationId: operation,
          draft: ProductDraft(name: 'New item', unitId: unitId),
          initialStock: BatchDraft(
            receivedDate: fixture.clock.today(),
            quantity: 4,
            production: full(6),
            expiry: full(5),
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
      for (final table in [
        'products',
        'batches',
        'date_specs',
        'stock_movements',
        'inventory_operations',
      ]) {
        expect(await fixture.count(table), 0);
      }
      // A failure after opening movement insertion also rolls back the entire save.
      await fixture.database.connection.execute(
        "CREATE TRIGGER simulate_full_disk BEFORE INSERT ON inventory_operations BEGIN SELECT RAISE(ABORT,'simulated storage failure'); END",
      );
      await expectLater(
        repo().saveProduct(
          operationId: operation,
          draft: ProductDraft(name: 'New item', unitId: unitId),
          initialStock: BatchDraft(
            receivedDate: fixture.clock.today(),
            quantity: 4,
            expiry: full(5),
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );
      for (final table in [
        'products',
        'batches',
        'date_specs',
        'stock_movements',
        'inventory_operations',
      ]) {
        expect(await fixture.count(table), 0);
      }
      await fixture.database.connection.execute(
        'DROP TRIGGER simulate_full_disk',
      );
      final p = await repo().saveProduct(
        operationId: operation,
        draft: ProductDraft(name: 'New item', unitId: unitId),
        initialStock: BatchDraft(
          receivedDate: fixture.clock.today(),
          quantity: 4,
          expiry: full(5),
        ),
      );
      expect((await repo().batches(p.meta.id)).single.quantity, 4);
      await reconcile();
    },
  );

  test(
    'concurrent create retries and disk reopen keep one product and opening',
    () async {
      final operation = id();
      final draft = ProductDraft(name: '  دوا 500 mg  ', unitId: unitId);
      final source = DateSpec(
        calendar: DateCalendar.solarHijri,
        year: 1405,
        month: 7,
      );
      final opening = BatchDraft(
        receivedDate: fixture.clock.today(),
        quantity: 8,
        expiry: source,
      );
      final results = await Future.wait(
        List.generate(
          3,
          (_) => repo().saveProduct(
            operationId: operation,
            draft: draft,
            initialStock: opening,
          ),
        ),
      );
      expect(results.map((p) => p.meta.id).toSet(), hasLength(1));
      expect(results.first.name, 'دوا 500 mg');
      final initial = (await repo().batches(results.first.meta.id)).single;
      expect(initial.label, startsWith('Batch '));
      await fixture.reopen();
      final retried = await repo().saveProduct(
        operationId: operation,
        draft: draft,
        initialStock: opening,
      );
      expect(retried.meta.id, results.first.meta.id);
      final restored = (await repo().batches(retried.meta.id)).single;
      expect(restored.meta.id, initial.meta.id);
      expect(restored.expiry!.toMap(), source.toMap());
      expect(restored.quantity, 8);
      expect(await fixture.count('stock_movements'), 1);
      await expectLater(
        repo().saveProduct(
          operationId: operation,
          draft: ProductDraft(name: 'Changed payload', unitId: unitId),
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        fixture.database.connection.delete('inventory_operations'),
        throwsA(isA<DatabaseException>()),
      );
      await reconcile();
    },
  );

  test(
    'explicit two-batch removal, duplicate taps, insufficiency and Undo persist',
    () async {
      final p = await product();
      final a = await batch(p, 8, expiry: full(7), label: 'Delivery A');
      final b = await batch(p, 12, expiry: full(29), label: 'Delivery B');
      final operation = id();
      await Future.wait(
        List.generate(
          3,
          (_) => repo().adjust(
            operationId: operation,
            batchId: b.meta.id,
            delta: -3,
            note: 'Manual removal',
          ),
        ),
      );
      expect((await repo().batch(a.meta.id)).quantity, 8);
      expect((await repo().batch(b.meta.id)).quantity, 9);
      await expectLater(
        repo().adjust(operationId: id(), batchId: b.meta.id, delta: -10),
        throwsA(isA<ValidationException>()),
      );
      expect(await fixture.count('stock_movements'), 3);
      final undo = id();
      await Future.wait(
        List.generate(
          2,
          (_) => repo().reverse(operationId: undo, movementId: operation),
        ),
      );
      await fixture.reopen();
      await repo().reverse(operationId: undo, movementId: operation);
      expect((await repo().batch(b.meta.id)).quantity, 12);
      final history = await repo().productMovements(p.meta.id);
      expect(history, hasLength(4));
      expect(history.first.kind, MovementKind.reversal);
      expect(history.first.reversalOf, operation);
      expect(history.first.delta, 3);
      expect(history.first.resultingQuantity, 12);
      await expectLater(
        repo().reverse(operationId: id(), movementId: operation),
        throwsA(isA<DatabaseException>()),
      );
      await reconcile();
    },
  );

  test('Undo cannot make stock negative after another removal', () async {
    final p = await product();
    final b = await batch(p, 1);
    final added = await repo().adjust(
      operationId: id(),
      batchId: b.meta.id,
      delta: 3,
    );
    await repo().adjust(operationId: id(), batchId: b.meta.id, delta: -4);
    await expectLater(
      repo().reverse(operationId: id(), movementId: added.meta.id),
      throwsA(isA<ValidationException>()),
    );
    expect((await repo().batch(b.meta.id)).quantity, 0);
    expect(await fixture.count('stock_movements'), 3);
    await reconcile();
  });

  test(
    'same-date deliveries stay distinct; date correction preserves quantity and source',
    () async {
      final p = await product();
      final a = await batch(p, 4, expiry: full(20));
      final draft = BatchDraft(
        receivedDate: fixture.clock.today(),
        quantity: 6,
        expiry: full(20),
      );
      final operation = id();
      final b = await repo().saveBatch(
        operationId: operation,
        productId: p.meta.id,
        draft: draft,
      );
      await repo().saveBatch(
        operationId: operation,
        productId: p.meta.id,
        draft: draft,
      );
      expect(a.meta.id, isNot(b.meta.id));
      expect(await repo().batches(p.meta.id), hasLength(2));
      final production = DateSpec(
        calendar: DateCalendar.gregorian,
        year: 2026,
        month: 10,
      );
      final expiry = DateSpec(
        calendar: DateCalendar.solarHijri,
        year: 1405,
        month: 7,
      );
      final edited = await repo().saveBatch(
        operationId: id(),
        productId: p.meta.id,
        batchId: b.meta.id,
        draft: BatchDraft(
          receivedDate: BusinessDate(2026, 10, 2),
          label: 'Corrected label',
          production: production,
          expiry: expiry,
        ),
      );
      expect(edited.quantity, 6);
      expect(edited.meta.id, b.meta.id);
      expect(edited.production!.toMap(), production.toMap());
      expect(edited.expiry!.toMap(), expiry.toMap());
      await expectLater(
        repo().saveBatch(
          operationId: id(),
          productId: p.meta.id,
          batchId: b.meta.id,
          draft: BatchDraft(receivedDate: fixture.clock.today(), quantity: 10),
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        repo().saveBatch(
          operationId: id(),
          productId: p.meta.id,
          batchId: b.meta.id,
          draft: BatchDraft(
            receivedDate: fixture.clock.today(),
            production: full(30),
            expiry: expiry,
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
      final noExpiry = await repo().saveBatch(
        operationId: id(),
        productId: p.meta.id,
        batchId: b.meta.id,
        draft: BatchDraft(
          receivedDate: edited.receivedDate,
          label: edited.label,
        ),
      );
      expect(noExpiry.expiry, isNull);
      expect(noExpiry.quantity, 6);
      expect(await fixture.count('stock_movements'), 2);
      await fixture.reopen();
      expect((await repo().batch(b.meta.id)).expiry, isNull);
      await reconcile();
    },
  );

  test(
    'unit lifecycle preserves identity, history, inactive operation and locking',
    () async {
      final settings = fixture.services.settings;
      final unit = await settings.saveUnit(
        name: ' Capsule ',
        operationId: id(),
      );
      final p = await repo().createProduct(
        name: 'Capsules',
        unitId: unit.meta.id,
      );
      final b = await batch(p, 2);
      await settings.saveUnit(
        id: unit.meta.id,
        name: 'Capsules',
        inactive: true,
      );
      expect((await settings.unitUsage())[unit.meta.id], 1);
      await expectLater(
        settings.deleteUnusedUnit(unit.meta.id),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        repo().createProduct(name: 'Another', unitId: unit.meta.id),
        throwsA(isA<ValidationException>()),
      );
      await repo().adjust(operationId: id(), batchId: b.meta.id, delta: 1);
      await repo().saveProduct(
        operationId: id(),
        productId: p.meta.id,
        draft: ProductDraft(name: 'Renamed medicine', unitId: unit.meta.id),
      );
      expect(
        (await repo().inventory(
          today: fixture.clock.today(),
        )).items.single.unit,
        'Capsules',
      );
      await repo().adjust(operationId: id(), batchId: b.meta.id, delta: -3);
      await expectLater(
        repo().saveProduct(
          operationId: id(),
          productId: p.meta.id,
          draft: ProductDraft(name: p.name, unitId: unitId),
        ),
        throwsA(isA<ValidationException>()),
      );
      final duplicate = await settings.saveUnit(name: 'CAPSULES');
      await expectLater(
        settings.saveUnit(id: unit.meta.id, name: 'Capsules'),
        throwsA(isA<DatabaseException>()),
      );
      final deletion = id();
      await settings.deleteUnusedUnit(duplicate.meta.id, operationId: deletion);
      await settings.deleteUnusedUnit(duplicate.meta.id, operationId: deletion);
      await settings.saveUnit(id: unit.meta.id, name: 'Capsules');
      await fixture.reopen();
      final restored = (await fixture.services.settings.units()).singleWhere(
        (u) => u.meta.id == unit.meta.id,
      );
      expect(restored.inactive, false);
      expect((await repo().product(p.meta.id)).unitId, unit.meta.id);
      await reconcile();
    },
  );

  test(
    'no-history unit may change; duplicate names warn but remain valid',
    () async {
      final p = await product(name: '  كريم ي  ');
      final other = (await fixture.services.settings.units()).last;
      final edited = await repo().saveProduct(
        operationId: id(),
        productId: p.meta.id,
        draft: ProductDraft(name: p.name, unitId: other.meta.id),
      );
      expect(edited.unitId, other.meta.id);
      expect(await repo().similarProducts('کریم ی'), hasLength(1));
      await product(name: 'کریم ی');
      expect(
        (await repo().inventory(
          today: fixture.clock.today(),
          search: 'کریم',
        )).items,
        hasLength(2),
      );
      expect((await repo().product(p.meta.id)).name, 'كريم ي');
      expect(await repo().hasStockHistory(p.meta.id), false);
    },
  );

  test(
    'archive guards include expired physical stock, preserve history and allow restoration',
    () async {
      final p = await product(minimum: 5);
      final b = await batch(p, 3, expiry: full(1));
      await expectLater(
        repo().archiveProduct(p.meta.id, archived: true, operationId: id()),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        repo().archiveBatch(b.meta.id, archived: true, operationId: id()),
        throwsA(isA<ValidationException>()),
      );
      await repo().adjust(operationId: id(), batchId: b.meta.id, delta: -3);
      await repo().archiveBatch(b.meta.id, archived: true, operationId: id());
      await repo().archiveProduct(p.meta.id, archived: true, operationId: id());
      expect(
        (await repo().inventory(today: fixture.clock.today())).items,
        isEmpty,
      );
      expect(
        (await repo().inventory(
          today: fixture.clock.today(),
          archived: true,
        )).items.single.product.meta.id,
        p.meta.id,
      );
      expect((await repo().overview(fixture.clock.today())).lowStock, 0);
      await expectLater(
        repo().archiveBatch(b.meta.id, archived: false, operationId: id()),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        repo().adjust(operationId: id(), batchId: b.meta.id, delta: 1),
        throwsA(isA<DatabaseException>()),
      );
      await repo().archiveProduct(
        p.meta.id,
        archived: false,
        operationId: id(),
      );
      expect((await repo().batch(b.meta.id)).archived, true);
      await repo().archiveBatch(b.meta.id, archived: false, operationId: id());
      await repo().adjust(operationId: id(), batchId: b.meta.id, delta: 2);
      expect(await repo().productMovements(p.meta.id), hasLength(3));
      await reconcile();
    },
  );

  test(
    'alert boundaries distinguish physical/usable, zero, month end and product thresholds',
    () async {
      final p = await product(minimum: 6, warning: 0);
      final expiresToday = await batch(p, 2, expiry: full(5));
      await batch(p, 3, expiry: full(4));
      await batch(p, 3); // No-expiry stock is usable.
      final empty = await batch(p, 1, expiry: full(5));
      await repo().adjust(operationId: id(), batchId: empty.meta.id, delta: -1);
      final q = await product(minimum: 2, warning: 45, name: 'Second');
      final atThreshold = await batch(q, 2, expiry: full(19, month: 11));
      await batch(q, 1, expiry: full(20, month: 11));
      final zero = await product();
      final item = (await repo().inventory(
        today: fixture.clock.today(),
        filter: InventoryFilter.lowStock,
      )).items.single;
      expect(item.product.meta.id, p.meta.id);
      expect(item.physical, 8);
      expect(item.usable, 5);
      expect(item.expiredBatches, 1);
      expect(item.expiringBatches, 1);
      final soon = await repo().alerts(
        today: fixture.clock.today(),
        filter: InventoryFilter.expiringSoon,
      );
      expect(
        soon.map((a) => a.batch.meta.id),
        unorderedEquals([expiresToday.meta.id, atThreshold.meta.id]),
      );
      expect(
        (await repo().inventory(
          today: fixture.clock.today(),
          filter: InventoryFilter.outOfStock,
        )).items.single.product.meta.id,
        zero.meta.id,
      );
      final equal = await product(minimum: 4, name: 'Equal threshold');
      await batch(equal, 4);
      expect(
        (await repo().inventory(
          today: fixture.clock.today(),
          filter: InventoryFilter.lowStock,
        )).total,
        1,
      );
      fixture.clock.date = BusinessDate(2026, 10, 6);
      expect(
        (await repo().inventory(today: fixture.clock.today(), search: p.name))
            .items
            .singleWhere((item) => item.product.meta.id == p.meta.id)
            .usable,
        3,
      );
      expect(
        await repo().alerts(
          today: fixture.clock.today(),
          filter: InventoryFilter.expired,
        ),
        hasLength(2),
      );
      final month = DateSpec(
        calendar: DateCalendar.solarHijri,
        year: 1405,
        month: 7,
      );
      final m = await product(name: 'Month only');
      await batch(m, 1, expiry: month);
      expect(
        (await repo().inventory(
          today: month.range.end,
          search: m.name,
        )).items.single.usable,
        1,
      );
      final next = DateTime.utc(
        month.range.end.year,
        month.range.end.month,
        month.range.end.day + 1,
      );
      expect(
        (await repo().inventory(
          today: BusinessDate.fromLocal(next),
          search: m.name,
        )).items.single.usable,
        0,
      );
    },
  );

  test(
    'v2 to current migration preserves live quantities, source dates and movements',
    () async {
      final p = await product();
      final b = await batch(p, 7, expiry: full(15));
      final originalHistory = await fixture.database.connection.query(
        'stock_movements',
      );
      // Remove the v3/v4 additions to reconstruct a v2 installation.
      await fixture.database.connection.execute('DROP TABLE daily_operations');
      await fixture.database.connection.execute('DROP TABLE debt_operations');
      await fixture.database.connection.execute(
        'DROP INDEX customer_phone_search',
      );
      await fixture.database.connection.execute(
        'ALTER TABLE customers DROP COLUMN phone_key',
      );
      await fixture.database.connection.execute(
        'DROP TABLE inventory_operations',
      );
      await fixture.database.connection.execute('DROP INDEX batch_received');
      await fixture.database.connection.setVersion(2);
      await fixture.reopen();
      expect(await fixture.database.connection.getVersion(), schemaVersion);
      expect((await repo().batch(b.meta.id)).quantity, 7);
      expect((await repo().batch(b.meta.id)).expiry!.toMap(), full(15).toMap());
      expect(
        await fixture.database.connection.query('stock_movements'),
        originalHistory,
      );
      await repo().saveProduct(
        operationId: id(),
        productId: p.meta.id,
        draft: ProductDraft(name: 'Edited after migration', unitId: unitId),
      );
      expect(await fixture.count('inventory_operations'), 1);
      expect(
        await fixture.database.connection.rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
      expect(
        (await fixture.database.connection.rawQuery(
          'PRAGMA integrity_check',
        )).single.values.single,
        'ok',
      );
      await reconcile();
    },
  );

  test('inventory day signal refreshes only when local day changes', () async {
    final controller = InventoryController(
      resolve: () async =>
          (inventory: repo(), settings: fixture.services.settings),
      clock: fixture.clock,
    );
    addTearDown(controller.dispose);
    var changes = 0;
    controller.addListener(() => changes++);
    controller.refreshDay();
    expect(changes, 0);
    fixture.clock.date = BusinessDate(2026, 10, 6);
    controller.refreshDay();
    controller.refreshDay();
    expect(changes, 1);
  });
}
