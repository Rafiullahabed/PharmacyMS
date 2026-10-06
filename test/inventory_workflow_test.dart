import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/core/domain/validation.dart';
import 'package:pharmacyms/core/presentation/app_theme.dart';
import 'package:pharmacyms/core/presentation/form_fields.dart';
import 'package:pharmacyms/core/presentation/components.dart';
import 'package:pharmacyms/features/inventory/application/inventory_controller.dart';
import 'package:pharmacyms/features/inventory/data/sqlite_inventory_repository.dart';
import 'package:pharmacyms/features/inventory/domain/inventory.dart';
import 'package:pharmacyms/features/inventory/presentation/batch_form.dart';
import 'package:pharmacyms/features/inventory/presentation/date_spec_field.dart';
import 'package:pharmacyms/features/inventory/presentation/detail_screens.dart';
import 'package:pharmacyms/features/inventory/presentation/product_form.dart';
import 'package:pharmacyms/features/inventory/presentation/inventory_screen.dart';
import 'package:pharmacyms/features/inventory/presentation/stock_adjustment.dart';
import 'package:pharmacyms/features/settings/presentation/units_screen.dart';
import 'support/inventory_database.dart';

/// Only failure timing is simulated. Every successful operation uses real SQLite.
class ControlledInventory extends SqliteInventoryRepository {
  ControlledInventory(super.db, super.clock);
  Completer<void>? gate;
  bool loseAcknowledgment = false;
  bool loseProductAcknowledgment = false;
  int adjustmentCalls = 0;
  final attemptedIds = <String>[];
  @override
  Future<Product> saveProduct({
    required String operationId,
    String? productId,
    required ProductDraft draft,
    BatchDraft? initialStock,
  }) async {
    final result = await super.saveProduct(
      operationId: operationId,
      productId: productId,
      draft: draft,
      initialStock: initialStock,
    );
    if (loseProductAcknowledgment) {
      loseProductAcknowledgment = false;
      throw StateError('Simulated lost product-save acknowledgment');
    }
    return result;
  }

  @override
  Future<StockMovement> adjust({
    required String operationId,
    required String batchId,
    required int delta,
    String? note,
  }) async {
    adjustmentCalls++;
    attemptedIds.add(operationId);
    await gate?.future;
    final result = await super.adjust(
      operationId: operationId,
      batchId: batchId,
      delta: delta,
      note: note,
    );
    if (loseAcknowledgment) {
      loseAcknowledgment = false;
      throw StateError('Simulated lost acknowledgment after SQLite commit');
    }
    return result;
  }
}

Future<void> ioFrames(WidgetTester tester, {int count = 6}) async {
  for (var i = 0; i < count; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150 && !ready(); i++) {
    await ioFrames(tester, count: 1);
  }
  expect(
    ready(),
    true,
    reason: 'UI did not finish the expected local operation',
  );
  await ioFrames(tester, count: 6);
}

Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is AppTextField && w.label == label),
  matching: find.byType(TextFormField),
);
Future<void> enter(WidgetTester tester, String label, String value) async {
  final target = field(label);
  await tester.ensureVisible(target);
  await tester.enterText(target, value);
  await tester.pump();
}

Finder rawField(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (w) =>
        (w is AppTextField && w.label == label) ||
        (w is SearchField && w.label == label),
  ),
  matching: find.byType(TextField),
);
Future<void> select(WidgetTester tester, Finder dropdown, String option) async {
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  late InventoryDatabase fixture;
  late ControlledInventory repository;
  late InventoryController controller;
  late String unitId;
  setUp(() async {
    fixture = InventoryDatabase();
    await fixture.open();
    repository = ControlledInventory(
      fixture.database.connection,
      fixture.clock,
    );
    controller = InventoryController(
      resolve: () async =>
          (inventory: repository, settings: fixture.services.settings),
      clock: fixture.clock,
    );
    unitId = (await fixture.services.settings.units()).first.meta.id;
  });
  tearDown(() async {
    controller.dispose();
    await fixture.close();
  });

  Future<void> launcher(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => page),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await ioFrames(tester);
  }

  testWidgets(
    'manual batch selection, insufficient input, duplicate taps, commit and Undo',
    (tester) async {
      late Product product;
      late Batch a, b;
      await tester.runAsync(() async {
        product = await repository.createProduct(
          name: 'Amoxicillin',
          unitId: unitId,
        );
        a = await repository.createBatch(
          productId: product.meta.id,
          receivedDate: fixture.clock.today(),
          openingQuantity: 8,
          label: 'Delivery A',
          expiry: DateSpec(
            calendar: DateCalendar.gregorian,
            year: 2026,
            month: 10,
            day: 7,
          ),
        );
        b = await repository.createBatch(
          productId: product.meta.id,
          receivedDate: fixture.clock.today(),
          openingQuantity: 12,
          label: 'Delivery B',
          expiry: DateSpec(
            calendar: DateCalendar.gregorian,
            year: 2026,
            month: 12,
            day: 30,
          ),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => adjustStock(
                  context,
                  controller,
                  product.meta.id,
                  remove: true,
                ),
                child: const Text('Open removal'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open removal'));
      await tester.tap(
        find.text('Open removal'),
      ); // Opening itself is guarded too.
      await until(
        tester,
        () => find.byType(StockAdjustment).evaluate().isNotEmpty,
      );
      expect(find.byType(StockAdjustment), findsOneWidget);
      final dropdown = find.byType(DropdownButtonFormField<String>);
      expect(
        tester.widget<DropdownButtonFormField<String>>(dropdown).initialValue,
        isNull,
      );
      final save = find.widgetWithText(FilledButton, 'Remove stock');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(find.text('2026/10/07 · Gregorian · Full date'), findsOneWidget);
      await tester.tap(find.text('Delivery B · 12 Bottle').last);
      await tester.pumpAndSettle();
      await enter(tester, 'Quantity to remove', '13');
      expect(
        find.text('Only 12 Bottle are available in this batch.'),
        findsWidgets,
      );
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await enter(tester, 'Quantity to remove', '۳');
      expect(find.text('Current 12 → After removing 9 Bottle'), findsOneWidget);
      repository.gate = Completer<void>();
      await tester.tap(save);
      await tester.tap(save);
      await tester.pump();
      expect(repository.adjustmentCalls, 1);
      expect(find.text('Saving…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Saving…'))
            .onPressed,
        isNull,
      );
      repository.gate!.complete();
      await until(tester, () => find.text('Undo').evaluate().isNotEmpty);
      await tester.runAsync(() async {
        expect((await repository.batch(a.meta.id)).quantity, 8);
        expect((await repository.batch(b.meta.id)).quantity, 9);
      });
      await tester.tap(find.text('Undo'));
      await until(
        tester,
        () => find.text('Stock change undone').evaluate().isNotEmpty,
      );
      await tester.runAsync(() async {
        expect((await repository.batch(b.meta.id)).quantity, 12);
        expect(await fixture.count('stock_movements'), 4);
        expect(await fixture.count('daily_records'), 0);
        expect(await fixture.count('ledger_entries'), 0);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'lost commit acknowledgment keeps input and retries the same removal exactly once',
    (tester) async {
      late Product product;
      late Batch batch;
      await tester.runAsync(() async {
        product = await repository.createProduct(
          name: 'Bottle',
          unitId: unitId,
        );
        batch = await repository.createBatch(
          productId: product.meta.id,
          receivedDate: fixture.clock.today(),
          openingQuantity: 3,
          label: 'Only batch',
        );
      });
      repository.loseAcknowledgment = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => adjustStock(
                  context,
                  controller,
                  product.meta.id,
                  remove: true,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await until(
        tester,
        () => field('Quantity to remove').evaluate().isNotEmpty,
      );
      expect(find.text('Only batch'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await enter(tester, 'Quantity to remove', '3');
      await tester.tap(find.widgetWithText(FilledButton, 'Remove stock'));
      await until(
        tester,
        () => find
            .textContaining('Unable to save to this device')
            .evaluate()
            .isNotEmpty,
      );
      expect(
        tester
            .widget<TextFormField>(field('Quantity to remove'))
            .controller!
            .text,
        '3',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Remove stock'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Remove stock'));
      await until(tester, () => find.text('Undo').evaluate().isNotEmpty);
      expect(repository.attemptedIds.toSet(), hasLength(1));
      await tester.runAsync(() async {
        expect((await repository.batch(batch.meta.id)).quantity, 0);
        expect(await fixture.count('stock_movements'), 2);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'product form validates, warns about duplicates and saves initial stock atomically',
    (tester) async {
      await tester.runAsync(
        () => repository.createProduct(name: 'کریم', unitId: unitId),
      );
      await launcher(tester, ProductForm(controller: controller));
      await until(
        tester,
        () =>
            find.byType(DropdownButtonFormField<String>).evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a counting unit.'), findsOneWidget);
      await enter(tester, 'Item name', 'کریم');
      await select(
        tester,
        find.byType(DropdownButtonFormField<String>),
        'Bottle',
      );
      await tester.ensureVisible(find.text('Add initial stock'));
      await tester.tap(find.text('Add initial stock'));
      await tester.pumpAndSettle();
      await enter(tester, 'Initial quantity', '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => fixture.count('products')), 1);
      await enter(tester, 'Initial quantity', '5');
      final expiry = find.byWidgetPredicate(
        (w) => w is DateSpecField && w.label == 'Expiry',
      );
      await select(
        tester,
        find.descendant(
          of: expiry,
          matching: find.byType(DropdownButtonFormField<DateInputMode>),
        ),
        'No expiry date',
      );
      await tester.tap(find.text('Save'));
      await until(
        tester,
        () => find.text('Possible duplicate item').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Continue'));
      await until(tester, () => find.byType(ProductForm).evaluate().isEmpty);
      await tester.runAsync(() async {
        expect(await fixture.count('products'), 2);
        expect(await fixture.count('batches'), 1);
        expect(await fixture.count('stock_movements'), 1);
        final saved = (await fixture.database.connection.query(
          'batches',
        )).single;
        expect(saved['quantity'], 5);
        expect(saved['expiry_mode'], 'none');
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unknown product save reconciles before showing any new duplicate warning',
    (tester) async {
      repository.loseProductAcknowledgment = true;
      await launcher(tester, ProductForm(controller: controller));
      await until(
        tester,
        () =>
            find.byType(DropdownButtonFormField<String>).evaluate().isNotEmpty,
      );
      await enter(tester, 'Item name', 'Retry product');
      await select(
        tester,
        find.byType(DropdownButtonFormField<String>),
        'Bottle',
      );
      await tester.tap(find.text('Save'));
      await until(
        tester,
        () => find
            .textContaining('Unable to save to this device')
            .evaluate()
            .isNotEmpty,
      );
      expect(await tester.runAsync(() => fixture.count('products')), 1);
      await tester.tap(find.text('Save'));
      await until(tester, () => find.byType(ProductForm).evaluate().isEmpty);
      expect(find.text('Possible duplicate item'), findsNothing);
      expect(await tester.runAsync(() => fixture.count('products')), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dirty form cancel retains input, discard leaves without a write',
    (tester) async {
      await launcher(tester, UnitForm(controller: controller));
      await enter(tester, 'Unit name', 'کپسول');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(field('Unit name')).controller!.text,
        'کپسول',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(UnitForm), findsNothing);
      expect(await tester.runAsync(() => fixture.count('units')), 6);
    },
  );

  testWidgets(
    'unit add/rename persists and used-unit menu excludes destructive deletion',
    (tester) async {
      await launcher(tester, UnitsScreen(controller: controller));
      await until(
        tester,
        () => find.byTooltip('Manage Bottle').evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Add unit'));
      await tester.pumpAndSettle();
      await enter(tester, 'Unit name', 'Capsule');
      await tester.tap(find.text('Save'));
      await until(
        tester,
        () => find.byTooltip('Manage Capsule').evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Manage Capsule'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await enter(tester, 'Unit name', 'کپسول');
      await tester.tap(find.text('Save'));
      await until(
        tester,
        () => find.byTooltip('Manage کپسول').evaluate().isNotEmpty,
      );
      await tester.runAsync(() async {
        final unit = (await fixture.services.settings.units()).singleWhere(
          (u) => u.name == 'کپسول',
        );
        await repository.createProduct(name: 'Medicine', unitId: unit.meta.id);
      });
      controller.changed();
      await ioFrames(tester);
      await tester.ensureVisible(find.byTooltip('Manage کپسول'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Manage کپسول'));
      await tester.pumpAndSettle();
      expect(find.text('Delete unused unit'), findsNothing);
      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Deactivate'));
      await ioFrames(tester);
      await tester.runAsync(() async {
        expect(
          (await fixture.services.settings.units())
              .singleWhere((u) => u.name == 'کپسول')
              .inactive,
          true,
        );
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'calendar display switching retains source; partial change requires explicit reentry',
    (tester) async {
      final key = GlobalKey<DateSpecFieldState>();
      final source = DateSpec(
        calendar: DateCalendar.solarHijri,
        year: 1405,
        month: 1,
        day: 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: DateSpecField(
                key: key,
                label: 'Expiry',
                today: fixture.clock.today(),
                initial: source,
                expiry: true,
                onChanged: () {},
              ),
            ),
          ),
        ),
      );
      await select(
        tester,
        find.byType(DropdownButtonFormField<DateCalendar>),
        'Gregorian',
      );
      expect(key.currentState!.value()!.toMap(), source.toMap());
      expect(
        tester.widget<TextField>(rawField('Expiry year')).controller!.text,
        '2026',
      );
      await select(
        tester,
        find.byType(DropdownButtonFormField<DateInputMode>),
        'Month & year',
      );
      expect(key.currentState!.value()!.day, isNull);
      await tester.tap(find.byType(DropdownButtonFormField<DateCalendar>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Solar Hijri').last);
      await tester.pumpAndSettle();
      expect(find.text('Re-enter the month?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(key.currentState!.value()!.calendar, DateCalendar.gregorian);
      await tester.tap(find.byType(DropdownButtonFormField<DateCalendar>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Solar Hijri').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Re-enter month'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(rawField('Expiry year')).controller!.text,
        '',
      );
      await tester.enterText(rawField('Expiry year'), '۱۴۰۵');
      await tester.enterText(rawField('Expiry month'), '۷');
      await tester.pump();
      expect(
        key.currentState!.value()!.toMap(),
        DateSpec(
          calendar: DateCalendar.solarHijri,
          year: 1405,
          month: 7,
        ).toMap(),
      );
      await select(
        tester,
        find.byType(DropdownButtonFormField<DateInputMode>),
        'Full date',
      );
      await tester.enterText(rawField('Expiry day'), '31');
      expect(
        () => key.currentState!.value(),
        throwsA(isA<ValidationException>()),
      );
      await select(
        tester,
        find.byType(DropdownButtonFormField<DateInputMode>),
        'No expiry date',
      );
      expect(key.currentState!.value(), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sheet swipe guards dirty input and remains usable above a small-screen keyboard',
    (tester) async {
      late Product product;
      await tester.runAsync(() async {
        product = await repository.createProduct(name: 'دوا', unitId: unitId);
        await repository.createBatch(
          productId: product.meta.id,
          receivedDate: fixture.clock.today(),
          openingQuantity: 3,
        );
      });
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => adjustStock(
                  context,
                  controller,
                  product.meta.id,
                  remove: false,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await until(
        tester,
        () => find.byType(StockAdjustment).evaluate().isNotEmpty,
      );
      await enter(tester, 'Quantity to add', '2');
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.getBottomLeft(find.widgetWithText(FilledButton, 'Add stock')).dy,
        lessThanOrEqualTo(318),
      );
      tester.view.resetViewInsets();
      await tester.pump();
      await tester.drag(
        find.byKey(const ValueKey('adjustment-dismiss-handle')),
        const Offset(0, 90),
      );
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(field('Quantity to add')).controller!.text,
        '2',
      );
      await tester.tap(find.byTooltip('Close adjustment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(StockAdjustment), findsNothing);
      expect(await tester.runAsync(() => fixture.count('stock_movements')), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Add stock offers a new independent batch and saves it without merging',
    (tester) async {
      late Product product;
      await tester.runAsync(() async {
        product = await repository.createProduct(
          name: 'New deliveries',
          unitId: unitId,
        );
        await repository.createBatch(
          productId: product.meta.id,
          receivedDate: fixture.clock.today(),
          openingQuantity: 5,
          label: 'Earlier delivery',
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => adjustStock(
                  context,
                  controller,
                  product.meta.id,
                  remove: false,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await until(tester, () => find.text('New batch').evaluate().isNotEmpty);
      await tester.tap(find.text('New batch'));
      await tester.pumpAndSettle();
      expect(find.byType(BatchForm), findsOneWidget);
      await enter(tester, 'Initial quantity', '7');
      final expiry = find.byWidgetPredicate(
        (w) => w is DateSpecField && w.label == 'Expiry',
      );
      await select(
        tester,
        find.descendant(
          of: expiry,
          matching: find.byType(DropdownButtonFormField<DateInputMode>),
        ),
        'No expiry date',
      );
      await tester.tap(find.text('Save'));
      await until(tester, () => find.byType(BatchForm).evaluate().isEmpty);
      await tester.runAsync(() async {
        final batches = await repository.batches(product.meta.id);
        expect(batches, hasLength(2));
        expect(batches.map((b) => b.quantity), unorderedEquals([5, 7]));
        expect(await fixture.count('stock_movements'), 2);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'inventory Persian search, empty result, expiry filter and affected batch route',
    (tester) async {
      await tester.runAsync(() async {
        final product = await repository.createProduct(
          name: 'كريم ي',
          unitId: unitId,
        );
        await repository.createBatch(
          productId: product.meta.id,
          receivedDate: fixture.clock.today(),
          openingQuantity: 2,
          label: 'Expired delivery',
          expiry: DateSpec(
            calendar: DateCalendar.gregorian,
            year: 2026,
            month: 10,
            day: 4,
          ),
        );
        await repository.createBatch(
          productId: product.meta.id,
          receivedDate: fixture.clock.today(),
          openingQuantity: 3,
          label: 'Fresh delivery',
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(body: InventoryScreen(controller: controller)),
        ),
      );
      await until(tester, () => find.text('كريم ي').evaluate().isNotEmpty);
      expect(find.text('3 Bottle usable'), findsOneWidget);
      expect(find.text('5 Bottle physical stock'), findsOneWidget);
      await tester.enterText(rawField('Search items'), 'nothing');
      await until(
        tester,
        () => find.text('No matching items').evaluate().isNotEmpty,
      );
      await tester.enterText(rawField('Search items'), 'کریم ی');
      await until(tester, () => find.text('كريم ي').evaluate().isNotEmpty);
      await tester.ensureVisible(find.widgetWithText(FilterChip, 'Expired'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Expired'));
      await until(
        tester,
        () => find.text('Expired delivery').evaluate().isNotEmpty,
      );
      expect(find.text('Fresh delivery'), findsNothing);
      await tester.tap(find.text('Expired delivery'));
      await until(
        tester,
        () =>
            find.text('Batch details').evaluate().isNotEmpty &&
            find
                .text('Expiry: 2026/10/04 · Gregorian · Full date')
                .evaluate()
                .isNotEmpty,
      );
      expect(find.text('Expired stock'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'batch correction review and large-text small-screen forms preserve stock',
    (tester) async {
      late Product product;
      late Batch batch;
      await tester.runAsync(() async {
        product = await repository.createProduct(
          name: 'Persian دوا',
          unitId: unitId,
        );
        batch = await repository.createBatch(
          productId: product.meta.id,
          receivedDate: fixture.clock.today(),
          openingQuantity: 2,
          expiry: DateSpec(
            calendar: DateCalendar.gregorian,
            year: 2026,
            month: 10,
            day: 5,
          ),
        );
      });
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await launcher(
        tester,
        BatchForm(
          controller: controller,
          product: product,
          unit: 'Bottle',
          batch: batch,
        ),
      );
      expect(field('Initial quantity'), findsNothing);
      final expiry = find.byWidgetPredicate(
        (w) => w is DateSpecField && w.label == 'Expiry',
      );
      await select(
        tester,
        find.descendant(
          of: expiry,
          matching: find.byType(DropdownButtonFormField<DateInputMode>),
        ),
        'No expiry date',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Review date correction'), findsOneWidget);
      expect(find.textContaining('Quantity stays 2 Bottle.'), findsOneWidget);
      await tester.tap(find.text('Save correction'));
      await until(tester, () => find.byType(BatchForm).evaluate().isEmpty);
      await tester.runAsync(() async {
        expect((await repository.batch(batch.meta.id)).expiry, isNull);
        expect((await repository.batch(batch.meta.id)).quantity, 2);
        expect(await fixture.count('stock_movements'), 1);
      });
      await launcher(
        tester,
        BatchDetailScreen(controller: controller, batchId: batch.meta.id),
      );
      await until(
        tester,
        () => find.text('No expiry date').evaluate().isNotEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
