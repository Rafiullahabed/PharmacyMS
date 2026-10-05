import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pharmacyms/app/application/app_controller.dart';
import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/core/domain/expiry.dart';
import 'package:pharmacyms/core/domain/entity.dart';
import 'package:pharmacyms/features/home/domain/home_summary.dart';
import 'package:pharmacyms/features/inventory/application/inventory_controller.dart';
import 'package:pharmacyms/features/inventory/domain/inventory.dart';
import 'support/inventory_database.dart';
import 'support/fake_clock.dart';

void main() {
  late InventoryDatabase fixture;
  late String unit;
  InventoryRepository repo() => fixture.services.inventory;
  String id() => const Uuid().v4();
  DateSpec full(BusinessDate date) => DateSpec(
    calendar: DateCalendar.gregorian,
    year: date.year,
    month: date.month,
    day: date.day,
  );
  BusinessDate shift(BusinessDate day, int days) =>
      BusinessDate.fromLocal(DateTime.utc(day.year, day.month, day.day + days));
  Future<Product> product(String name, {int minimum = 0, int warning = 30}) =>
      repo().createProduct(
        name: name,
        unitId: unit,
        minimumStock: minimum,
        warningDays: warning,
      );
  Future<Batch> batch(Product product, int quantity, DateSpec? expiry) =>
      repo().createBatch(
        productId: product.meta.id,
        receivedDate: fixture.clock.today(),
        openingQuantity: quantity,
        expiry: expiry,
      );
  setUp(() async {
    fixture = InventoryDatabase();
    await fixture.open();
    unit = (await fixture.services.settings.units()).first.meta.id;
  });
  tearDown(() => fixture.close());

  test(
    'SQL pages, Home counts and domain quantities agree across thresholds and rollover',
    () async {
      final today = fixture.clock.today();
      final products = [
        await product('Minimum disabled', minimum: 0, warning: 0),
        await product('Equal minimum', minimum: 10, warning: 45),
        await product('Below minimum', minimum: 11, warning: 46),
        await product('Empty item', minimum: 0),
        await product('Empty low item', minimum: 1),
      ];
      for (final p in products.take(3)) {
        await batch(p, 2, full(shift(today, -1)));
        await batch(p, 3, full(today));
        await batch(p, 2, full(shift(today, 45)));
        await batch(p, 1, full(shift(today, 46)));
        await batch(p, 4, null);
        final empty = await batch(p, 2, full(today));
        await repo().adjust(
          operationId: id(),
          batchId: empty.meta.id,
          delta: -2,
        );
      }
      for (final day in [
        today,
        shift(today, 1),
        shift(today, 45),
        shift(today, 46),
        shift(today, 47),
      ]) {
        final expected = <InventoryItem>[];
        for (final p in products) {
          expected.add(
            InventoryItem.fromBatches(
              p,
              'Bottle',
              await repo().batches(p.meta.id),
              day,
            ),
          );
        }
        for (final filter in InventoryFilter.values) {
          final page = await repo().inventory(today: day, filter: filter);
          expect(
            page.items.map((item) => item.product.meta.id),
            unorderedEquals(
              expected
                  .where((item) => item.matches(filter))
                  .map((item) => item.product.meta.id),
            ),
            reason: '${day.iso} ${filter.name}',
          );
          expect(page.total, page.items.length);
          for (final item in page.items) {
            final domain = expected.singleWhere(
              (e) => e.product.meta.id == item.product.meta.id,
            );
            expect(
              [
                item.physical,
                item.usable,
                item.expiredQuantity,
                item.expiredBatches,
                item.expiringBatches,
                item.expiresTodayBatches,
              ],
              [
                domain.physical,
                domain.usable,
                domain.expiredQuantity,
                domain.expiredBatches,
                domain.expiringBatches,
                domain.expiresTodayBatches,
              ],
            );
          }
          if (filter.isExpiry) {
            final alerts = await repo().alertPage(today: day, filter: filter);
            expect(alerts.totalProducts, page.total);
            expect(alerts.totalBatches, alerts.items.length);
            for (final alert in alerts.items) {
              final status = BatchInventoryStatus(
                alert.batch,
                day,
                warningDays: alert.product.warningDays,
              );
              expect(switch (filter) {
                InventoryFilter.expired => status.expired,
                InventoryFilter.expiresToday => status.expiresToday,
                _ => status.expiringSoon,
              }, true);
            }
          }
        }
        final home = await repo().dashboard(day);
        expect(home.today, day);
        expect(home.overview.products, products.length);
        expect(
          home.overview.lowStock,
          expected.where((e) => e.lowStock).length,
        );
        expect(
          home.overview.outOfStock,
          expected.where((e) => e.outOfStock).length,
        );
        expect(
          home.overview.expiredBatches,
          expected.fold<int>(0, (sum, e) => sum + e.expiredBatches),
        );
        expect(
          home.overview.expiringBatches,
          expected.fold<int>(0, (sum, e) => sum + e.expiringBatches),
        );
        expect(
          home.overview.expiresTodayBatches,
          expected.fold<int>(0, (sum, e) => sum + e.expiresTodayBatches),
        );
      }
      final first = await repo().inventory(today: today);
      expect(
        first.items
            .singleWhere((i) => i.product.name == 'Equal minimum')
            .lowStock,
        false,
      );
      expect(
        first.items
            .singleWhere((i) => i.product.name == 'Below minimum')
            .lowStock,
        true,
      );
      final zeroWarning = first.items.singleWhere(
        (i) => i.product.name == 'Minimum disabled',
      );
      expect(
        zeroWarning.expiringBatches,
        1,
      ); // Includes today even with warning 0.
      expect(zeroWarning.physical, 12);
      expect(zeroWarning.usable, 10);
    },
  );

  for (final spec in [
    DateSpec(calendar: DateCalendar.gregorian, year: 2024, month: 2),
    DateSpec(calendar: DateCalendar.gregorian, year: 2100, month: 2),
    DateSpec(calendar: DateCalendar.solarHijri, year: 1399, month: 12),
    DateSpec(calendar: DateCalendar.solarHijri, year: 1400, month: 12),
    DateSpec(calendar: DateCalendar.solarHijri, year: 1405, month: 6),
  ]) {
    test(
      'month-only ${spec.label} uses original leap/calendar month end',
      () async {
        final p = await product('Calendar boundary', warning: 0);
        final b = await batch(p, 7, spec);
        for (final delta in [-1, 0, 1]) {
          final day = shift(spec.effectiveExpiry, delta);
          final overview = await repo().overview(day);
          expect(overview.expiresTodayBatches, delta == 0 ? 1 : 0);
          expect(overview.expiredBatches, delta == 1 ? 1 : 0);
          expect(overview.expiringBatches, delta == 0 ? 1 : 0);
          final item = (await repo().inventory(today: day)).items.single;
          expect(item.physical, 7);
          expect(item.usable, delta == 1 ? 0 : 7);
        }
        await fixture.reopen();
        expect((await repo().batch(b.meta.id)).expiry!.toMap(), spec.toMap());
      },
    );
  }

  test(
    'empty/no-expiry and archived records never create active expiry warnings',
    () async {
      final p = await product('Active');
      final empty = await batch(p, 2, full(fixture.clock.today()));
      await repo().adjust(operationId: id(), batchId: empty.meta.id, delta: -2);
      await batch(p, 4, null);
      final archived = await batch(
        p,
        1,
        full(shift(fixture.clock.today(), -1)),
      );
      await repo().adjust(
        operationId: id(),
        batchId: archived.meta.id,
        delta: -1,
      );
      await repo().archiveBatch(
        archived.meta.id,
        archived: true,
        operationId: id(),
      );
      final removedProduct = await product('Archived low stock', minimum: 50);
      await repo().archiveProduct(
        removedProduct.meta.id,
        archived: true,
        operationId: id(),
      );
      final home = await repo().dashboard(fixture.clock.today());
      expect(home.overview.hasAlerts, false);
      expect(home.overview.products, 1);
      expect(home.overview.batches, 2);
      expect(home.expiryAttention, isEmpty);
      expect(home.stockAttention, isEmpty);
      expect(
        (await repo().inventory(
          today: fixture.clock.today(),
        )).items.single.usable,
        4,
      );
      final emptyStatus = BatchInventoryStatus(
        await repo().batch(empty.meta.id),
        fixture.clock.today(),
        warningDays: 30,
      );
      expect(emptyStatus.dateState, ExpiryState.expiresToday);
      expect(emptyStatus.expiresToday, false);
      // Domain eligibility also protects restored/imported archived snapshots.
      final historical = Batch(
        meta: EntityMeta.create(fixture.clock),
        productId: p.meta.id,
        label: 'History',
        receivedDate: fixture.clock.today(),
        quantity: 3,
        expiry: full(fixture.clock.today()),
        archived: true,
      );
      final historicalStatus = BatchInventoryStatus(
        historical,
        fixture.clock.today(),
        warningDays: 30,
      );
      expect(historicalStatus.physical, 0);
      expect(historicalStatus.expiringSoon, false);
    },
  );

  test(
    'out-of-stock-only Home is not all clear and attention selection retains stock issues',
    () async {
      final empty = await product('Zero minimum empty');
      var home = await repo().dashboard(fixture.clock.today());
      expect(home.overview.lowStock, 0);
      expect(home.overview.outOfStock, 1);
      expect(home.overview.hasAlerts, true);
      expect(home.stockAttention.single.product.meta.id, empty.meta.id);
      final p = await product('Many expiry issues');
      for (var i = 0; i < 6; i++) {
        await batch(p, 1, full(shift(fixture.clock.today(), -i - 1)));
      }
      final dueToday = await batch(p, 1, full(fixture.clock.today()));
      home = await repo().dashboard(fixture.clock.today());
      expect(home.expiryAttention, hasLength(3)); // Two expired, plus today.
      expect(
        home.expiryAttention.map((a) => a.batch.meta.id),
        contains(dueToday.meta.id),
      );
      expect(home.stockAttention.single.product.meta.id, empty.meta.id);
      final all = await repo().inventory(
        today: fixture.clock.today(),
        filter: InventoryFilter.needsAttention,
      );
      expect(all.total, 2);
    },
  );

  test(
    'paged expiry counts are batch counts; search keeps original Unicode and deterministic IDs',
    () async {
      final p = await product('كريم ي');
      for (var i = 0; i < 5; i++) {
        await batch(p, 1, full(fixture.clock.today()));
      }
      final other = await product('Other');
      await batch(other, 1, full(fixture.clock.today()));
      final seen = <String>[];
      for (var offset = 0; offset < 5; offset += 2) {
        final page = await repo().alertPage(
          today: fixture.clock.today(),
          filter: InventoryFilter.expiresToday,
          search: 'کریم ی',
          offset: offset,
          limit: 2,
        );
        expect(page.totalBatches, 5);
        expect(page.totalProducts, 1);
        seen.addAll(page.items.map((a) => a.batch.meta.id));
        expect(page.items.first.product.name, 'كريم ي');
      }
      expect(seen.toSet(), hasLength(5));
      expect(seen, orderedEquals([...seen]..sort()));
      expect(
        (await repo().alertPage(
          today: fixture.clock.today(),
          filter: InventoryFilter.expiresToday,
        )).totalBatches,
        6,
      );
    },
  );

  test(
    'stock, date, threshold and unit edits immediately affect snapshot values and survive reopen',
    () async {
      final p = await product('Settings changes', minimum: 4, warning: 44);
      final b = await batch(p, 4, full(shift(fixture.clock.today(), 45)));
      expect(
        (await repo().dashboard(fixture.clock.today())).overview.hasAlerts,
        false,
      );
      await repo().saveProduct(
        operationId: id(),
        productId: p.meta.id,
        draft: ProductDraft(
          name: p.name,
          unitId: unit,
          minimumStock: 5,
          warningDays: 45,
        ),
      );
      var home = await repo().dashboard(fixture.clock.today());
      expect(home.overview.lowStock, 1);
      expect(home.overview.expiringBatches, 1);
      await fixture.services.settings.saveUnit(id: unit, name: 'شیشه');
      home = await repo().dashboard(fixture.clock.today());
      expect(home.expiryAttention.single.unit, 'شیشه');
      await repo().saveBatch(
        operationId: id(),
        productId: p.meta.id,
        batchId: b.meta.id,
        draft: BatchDraft(
          receivedDate: b.receivedDate,
          expiry: full(shift(fixture.clock.today(), -1)),
        ),
      );
      home = await repo().dashboard(fixture.clock.today());
      expect(home.overview.expiredBatches, 1);
      expect(home.overview.outOfStock, 1);
      expect(home.stockAttention.single.physical, 4);
      expect(home.stockAttention.single.usable, 0);
      await repo().adjust(operationId: id(), batchId: b.meta.id, delta: -4);
      await fixture.reopen();
      home = await repo().dashboard(fixture.clock.today());
      expect(home.overview.expiredBatches, 0);
      expect(home.overview.lowStock, 1);
      expect(home.overview.outOfStock, 1);
      expect(home.stockAttention.single.physical, 0);
    },
  );

  test(
    'Home refresh coalesces commits during an outstanding read and rollover',
    () async {
      final clock = FakeClock();
      final gate = Completer<HomeSummary>();
      final days = <BusinessDate>[];
      HomeSummary summary(BusinessDate day, int products) => HomeSummary(
        today: day,
        products: products,
        batches: 0,
        dailyRecords: 0,
        customers: 0,
        outstanding: BigInt.zero,
        units: [],
      );
      final controller = AppController(
        clock: clock,
        load: (day) async {
          days.add(day);
          return days.length == 1 ? gate.future : summary(day, 2);
        },
      );
      addTearDown(controller.dispose);
      final running = controller.refresh();
      await controller.refresh();
      clock.date = shift(clock.today(), 1);
      await controller.refresh();
      gate.complete(summary(days.first, 0));
      await running;
      expect(days, hasLength(2));
      expect(controller.summary!.products, 2);
      expect(controller.summary!.today, clock.today());
      expect(controller.failed, false);
    },
  );

  testWidgets(
    'local-day polling invalidates once, including backwards timezone changes',
    (tester) async {
      final controller = InventoryController(
        clock: fixture.clock,
        resolve: () async =>
            (inventory: repo(), settings: fixture.services.settings),
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.startDayWatch();
      await tester.pump(const Duration(seconds: 31));
      expect(notifications, 0);
      fixture.clock.date = shift(fixture.clock.today(), 1);
      await tester.pump(const Duration(seconds: 31));
      expect(notifications, 1);
      await tester.pump(const Duration(seconds: 31));
      expect(notifications, 1);
      fixture.clock.date = shift(fixture.clock.today(), -1);
      await tester.pump(const Duration(seconds: 31));
      expect(notifications, 2);
      controller.dispose();
      await tester.pump(const Duration(seconds: 31));
      expect(notifications, 2);
    },
  );
}
