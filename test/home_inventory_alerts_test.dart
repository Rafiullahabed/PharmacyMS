import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pharmacyms/app/application/app_controller.dart';
import 'package:pharmacyms/app/presentation/pharmacy_app.dart';
import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/core/domain/money.dart';
import 'package:pharmacyms/core/presentation/components.dart';
import 'package:pharmacyms/core/presentation/form_fields.dart';
import 'package:pharmacyms/features/debtors/domain/debt.dart';
import 'package:pharmacyms/features/inventory/application/inventory_controller.dart';
import 'package:pharmacyms/features/inventory/data/sqlite_inventory_repository.dart';
import 'package:pharmacyms/features/inventory/domain/inventory.dart';
import 'package:pharmacyms/features/inventory/presentation/detail_screens.dart';
import 'package:pharmacyms/features/inventory/presentation/inventory_screen.dart';
import 'package:pharmacyms/features/inventory/presentation/product_form.dart';
import 'support/inventory_database.dart';
import 'package:pharmacyms/features/debtors/application/debt_controller.dart';
import 'package:pharmacyms/features/daily_records/application/daily_records_controller.dart';

class _HomeRepository extends SqliteInventoryRepository {
  _HomeRepository(super.db, super.clock);
  bool failDashboard = false;
  @override
  Future<InventoryDashboard> dashboard(BusinessDate today) {
    if (failDashboard) throw StateError('Injected read failure');
    return super.dashboard(today);
  }
}

Future<void> _frames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 160 && !done(); i++) {
    await _frames(tester, count: 1);
  }
  expect(
    done(),
    true,
    reason: 'The expected persisted UI state did not appear',
  );
  await _frames(tester);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await _frames(tester);
}

Finder _field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is AppTextField && w.label == label),
  matching: find.byType(TextFormField),
);

void main() {
  late InventoryDatabase fixture;
  late _HomeRepository repository;
  late InventoryController inventory;
  late AppController app;
  late String unitId;
  String id() => const Uuid().v4();
  DateSpec expiry(int offset) {
    final today = fixture.clock.today();
    final date = DateTime.utc(today.year, today.month, today.day + offset);
    return DateSpec(
      calendar: DateCalendar.gregorian,
      year: date.year,
      month: date.month,
      day: date.day,
    );
  }

  Future<Product> product(String name, {int minimum = 0, int warning = 30}) =>
      repository.createProduct(
        name: name,
        unitId: unitId,
        minimumStock: minimum,
        warningDays: warning,
      );
  Future<Batch> batch(Product p, String label, int quantity, int? offset) =>
      repository.createBatch(
        productId: p.meta.id,
        receivedDate: fixture.clock.today(),
        openingQuantity: quantity,
        label: label,
        expiry: offset == null ? null : expiry(offset),
      );
  Future<void> open(WidgetTester tester) async {
    addTearDown(() async {
      inventory.stopDayWatch();
      await tester.pumpWidget(const SizedBox.shrink());
      await _frames(tester);
    });
    final daily = DailyRecordsController(
      clock: fixture.clock,
      resolve: () async => fixture.services.dailyRecords,
    );
    addTearDown(daily.dispose);
    final debt = DebtController(
      clock: fixture.clock,
      resolve: () async => fixture.services.debtors,
    );
    addTearDown(debt.dispose);
    await tester.pumpWidget(
      PharmacyApp(
        controller: app,
        inventory: inventory,
        daily: daily,
        debt: debt,
      ),
    );
    await _until(
      tester,
      () =>
          find.textContaining('active products ·').evaluate().isNotEmpty ||
          find
              .textContaining('Unable to read local inventory')
              .evaluate()
              .isNotEmpty,
    );
  }

  setUp(() async {
    fixture = InventoryDatabase();
    await fixture.open();
    repository = _HomeRepository(fixture.database.connection, fixture.clock);
    inventory = InventoryController(
      clock: fixture.clock,
      resolve: () async =>
          (inventory: repository, settings: fixture.services.settings),
    );
    app = AppController(clock: fixture.clock, load: fixture.services.home.read);
    unitId = (await fixture.services.settings.units()).first.meta.id;
  });
  tearDown(() async {
    inventory.dispose();
    app.dispose();
    await fixture.close();
  });

  testWidgets('each Home count opens its exact filter with a route back', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final p = await product('Medicine', minimum: 10);
      await batch(p, 'Old delivery', 2, -1);
      await batch(p, 'Today delivery', 3, 0);
      await batch(p, 'Soon delivery', 4, 10);
      await product('Zero minimum empty');
      final healthy = await product('Healthy');
      await batch(healthy, 'No expiry', 8, null);
    });
    await open(tester);
    for (final entry in [
      ('Low stock: 1 product', InventoryFilter.lowStock),
      ('Out of stock: 1 product', InventoryFilter.outOfStock),
      ('Expired: 1 batch', InventoryFilter.expired),
      ('Expires today: 1 batch', InventoryFilter.expiresToday),
      ('Expiring soon: 2 batches', InventoryFilter.expiringSoon),
    ]) {
      await _tap(tester, find.text(entry.$1));
      await _until(
        tester,
        () =>
            find.byType(InventoryScreen).evaluate().isNotEmpty &&
            find
                .widgetWithText(FilterChip, entry.$2.label)
                .evaluate()
                .isNotEmpty,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, entry.$2.label))
            .selected,
        true,
      );
      if (entry.$2.isExpiry) {
        await _until(
          tester,
          () => find
              .textContaining('affected batches across')
              .evaluate()
              .isNotEmpty,
        );
      }
      await tester.pageBack();
      await _frames(tester);
      expect(find.text('Pharmacy Companion'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Needs attention includes zero-minimum empty item and opens the named batch or item',
    (tester) async {
      late Product empty;
      late Batch todayBatch;
      await tester.runAsync(() async {
        empty = await product('Empty item');
        final p = await product('Medicine');
        for (var i = 0; i < 4; i++) {
          await batch(p, 'Expired $i', 1, -i - 1);
        }
        todayBatch = await batch(p, 'Today delivery', 3, 0);
      });
      await open(tester);
      expect(find.text('No current inventory alerts'), findsNothing);
      final todayRow = find.widgetWithText(
        ListTile,
        'Expires today · 3 Bottle\nToday delivery · ${todayBatch.meta.id.substring(0, 8)}\n${todayBatch.expiry!.label}',
      );
      await _tap(tester, todayRow);
      expect(
        tester
            .widget<BatchDetailScreen>(find.byType(BatchDetailScreen))
            .batchId,
        todayBatch.meta.id,
      );
      await tester.pageBack();
      await _frames(tester);
      await _tap(tester, find.widgetWithText(ListTile, 'Empty item'));
      expect(
        tester
            .widget<ProductDetailScreen>(find.byType(ProductDetailScreen))
            .productId,
        empty.meta.id,
      );
      await tester.pageBack();
      await _frames(tester);
      await _tap(tester, find.text('View all items needing attention'));
      expect(
        tester
            .widget<FilterChip>(
              find.widgetWithText(FilterChip, 'Needs attention'),
            )
            .selected,
        true,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing product thresholds refreshes Home; date, quantity and unit commits refresh visible alerts',
    (tester) async {
      late Product p;
      late Batch b;
      await tester.runAsync(() async {
        p = await product('Threshold settings', minimum: 10, warning: 44);
        b = await batch(p, 'Delivery', 10, 45);
      });
      await open(tester);
      expect(find.text('No current inventory alerts'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.inventory_2_outlined).last);
      await _frames(tester);
      await _tap(tester, find.text('Threshold settings'));
      await _tap(tester, find.text('Edit item'));
      await _until(tester, () => _field('Minimum stock').evaluate().isNotEmpty);
      await tester.ensureVisible(_field('Minimum stock'));
      await tester.enterText(_field('Minimum stock'), '11');
      await tester.ensureVisible(_field('Expiry warning days'));
      await tester.enterText(_field('Expiry warning days'), '45');
      await _tap(tester, find.text('Save'));
      await _until(tester, () => find.byType(ProductForm).evaluate().isEmpty);
      await tester.pageBack();
      await _frames(tester);
      await tester.tap(find.byIcon(Icons.home_outlined));
      await _until(
        tester,
        () =>
            find.text('Low stock: 1 product').evaluate().isNotEmpty &&
            find.text('Expiring soon: 1 batch').evaluate().isNotEmpty,
      );
      await tester.runAsync(() async {
        await repository.saveBatch(
          operationId: id(),
          productId: p.meta.id,
          batchId: b.meta.id,
          draft: BatchDraft(
            receivedDate: b.receivedDate,
            label: b.label,
            expiry: expiry(-1),
          ),
        );
      });
      inventory.changed(); // Same post-commit signal used by the batch form.
      await _until(
        tester,
        () =>
            find.text('Expired: 1 batch').evaluate().isNotEmpty &&
            find.text('Out of stock: 1 product').evaluate().isNotEmpty,
      );
      await tester.runAsync(() async {
        await fixture.services.settings.saveUnit(id: unitId, name: 'شیشه');
      });
      inventory.changed();
      await _until(
        tester,
        () => find
            .textContaining('Expired stock · 10 شیشه')
            .evaluate()
            .isNotEmpty,
      );
      await tester.runAsync(() async {
        await repository.adjust(
          operationId: id(),
          batchId: b.meta.id,
          delta: -10,
        );
      });
      inventory.changed();
      await _until(
        tester,
        () => find.text('Expired: 0 batches').evaluate().isNotEmpty,
      );
      expect(find.text('Low stock: 1 product'), findsOneWidget);
      expect(find.text('Out of stock: 1 product'), findsOneWidget);
      expect(find.text('No current inventory alerts'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'day rollover refreshes an open filter and Home; resume refreshes after a date correction',
    (tester) async {
      late Product p;
      late Batch b;
      await tester.runAsync(() async {
        p = await product('Today medicine', minimum: 1, warning: 0);
        b = await batch(p, 'Today delivery', 3, 0);
      });
      await open(tester);
      await _tap(tester, find.text('Expires today: 1 batch'));
      await _until(
        tester,
        () => find.text('Today delivery').evaluate().isNotEmpty,
      );
      fixture.clock.date = BusinessDate(2026, 10, 6);
      await tester.pump(const Duration(seconds: 31));
      await _until(
        tester,
        () => find.text('No matching items').evaluate().isNotEmpty,
      );
      await tester.pageBack();
      await _until(
        tester,
        () => find.text('Expired: 1 batch').evaluate().isNotEmpty,
      );
      expect(find.text('Expires today: 0 batches'), findsOneWidget);
      expect(find.text('Out of stock: 1 product'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.runAsync(() async {
        await repository.saveBatch(
          operationId: id(),
          productId: p.meta.id,
          batchId: b.meta.id,
          draft: BatchDraft(receivedDate: b.receivedDate, expiry: expiry(1)),
        );
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _until(
        tester,
        () =>
            find.text('Expired: 0 batches').evaluate().isNotEmpty &&
            find.text('Out of stock: 0 products').evaluate().isNotEmpty,
      );
      expect(find.text('No current inventory alerts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home states no records until actual persisted financial/debt amounts exist',
    (tester) async {
      await open(tester);
      expect(find.text('Not recorded'), findsOneWidget);
      expect(find.text('No customer debt recorded.'), findsOneWidget);
      expect(find.byType(MoneyText), findsNothing);
      expect(find.text('Record today'), findsOneWidget);
      await tester.runAsync(() async {
        await fixture.services.dailyRecords.save(
          date: fixture.clock.today(),
          sales: Money.parse('125.50'),
          profit: Money.parse('-0.01'),
        );
        final customer = await fixture.services.debtors.createCustomer(
          name: 'مریم',
        );
        await fixture.services.debtors.addEntry(
          operationId: id(),
          customerId: customer.meta.id,
          date: fixture.clock.today(),
          kind: LedgerKind.debt,
          amount: Money.parse('450'),
        );
      });
      await tester.runAsync(app.refresh);
      await _frames(tester);
      expect(
        tester
            .widgetList<MoneyText>(find.byType(MoneyText))
            .map((w) => w.total ?? BigInt.from(w.money!.minor)),
        unorderedEquals([
          BigInt.from(12550),
          BigInt.from(-1),
          BigInt.from(45000),
        ]),
      );
      expect(find.text('Not recorded'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home read failure has Retry without false all-clear or fabricated counts',
    (tester) async {
      await tester.runAsync(() => product('Empty with zero minimum'));
      repository.failDashboard = true;
      await open(tester);
      expect(find.text('No current inventory alerts'), findsNothing);
      expect(find.text('Out of stock: 0 products'), findsNothing);
      repository.failDashboard = false;
      await _tap(tester, find.widgetWithText(FilledButton, 'Retry'));
      await _until(
        tester,
        () => find.text('Out of stock: 1 product').evaluate().isNotEmpty,
      );
      expect(find.text('No current inventory alerts'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'alert semantics expose label, count and action; 320px/200% Home keeps all actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.runAsync(() async {
          final p = await product(
            'کریم برای مراقبت پوست و نام بسیار طولانی English 500 mg',
            minimum: 5,
          );
          await batch(p, 'Long batch label برای آزمایش', 2, 0);
        });
        await open(tester);
        await tester.ensureVisible(find.text('Expires today: 1 batch'));
        await tester.pump();
        final node = tester.getSemantics(
          find.bySemanticsLabel('Expires today: 1 batch'),
        );
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
        expect(node.getSemanticsData().hint, 'Open filtered inventory');
        await _tap(tester, find.text('Expires today: 1 batch'));
        await _until(
          tester,
          () => find.text('Expires today').evaluate().length > 1,
        );
        expect(find.byIcon(Icons.today_outlined), findsWidgets);
        await tester.pageBack();
        await _frames(tester);
        await tester.ensureVisible(
          find.text('View all items needing attention'),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
