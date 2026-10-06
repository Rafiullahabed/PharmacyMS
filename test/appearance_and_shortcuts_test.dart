import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pharmacyms/app/application/app_controller.dart';
import 'package:pharmacyms/app/presentation/pharmacy_app.dart';
import 'package:pharmacyms/core/domain/validation.dart';
import 'package:pharmacyms/features/settings/application/appearance_controller.dart';
import 'package:pharmacyms/features/settings/data/sqlite_settings_repository.dart';
import 'package:pharmacyms/features/settings/presentation/appearance_settings.dart';
import 'package:pharmacyms/features/inventory/application/inventory_controller.dart';
import 'package:pharmacyms/features/inventory/data/sqlite_inventory_repository.dart';
import 'package:pharmacyms/features/inventory/domain/inventory.dart';
import 'package:pharmacyms/features/inventory/presentation/detail_screens.dart';
import 'package:pharmacyms/features/inventory/presentation/inventory_screen.dart';
import 'package:pharmacyms/features/daily_records/application/daily_records_controller.dart';
import 'package:pharmacyms/features/debtors/application/debt_controller.dart';
import 'support/visual_fixture.dart';
import 'support/visual_test_binding.dart';

class FailingSettings extends SqliteSettingsRepository {
  FailingSettings(super.db, super.clock);
  bool fail = false;
  @override
  Future<void> setPreference(String key, String value, {int version = 1}) {
    if (fail) throw StateError('Disk unavailable');
    return super.setPreference(key, value, version: version);
  }
}

class DelayedInventory extends SqliteInventoryRepository {
  DelayedInventory(super.db, super.clock);
  Completer<void>? gate;
  bool lose = false;
  final calls = <String>[];
  @override
  Future<StockMovement> adjust({
    required String operationId,
    required String batchId,
    required int delta,
    String? note,
  }) async {
    calls.add(operationId);
    await gate?.future;
    final result = await super.adjust(
      operationId: operationId,
      batchId: batchId,
      delta: delta,
      note: note,
    );
    if (lose) {
      lose = false;
      throw StateError('Lost acknowledgment');
    }
    return result;
  }
}

Future<void> frames(WidgetTester tester, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 70));
  }
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find
          .byWidgetPredicate(
            (w) =>
                w is Scrollable &&
                w.axis == Axis.vertical &&
                w.restorationId != 'editable',
          )
          .hitTestable()
          .last,
      maxScrolls: 50,
    );
  }
  await tester.ensureVisible(finder);
  await frames(tester, 3);
}

void main() {
  VisualTestBinding();
  late VisualFixture f;
  String id() => const Uuid().v4();
  setUp(() async {
    f = VisualFixture();
    await f.open();
  });
  tearDown(() => f.close());
  setUpAll(() async {
    await (FontLoader(
      'Vazirmatn',
    )..addFont(rootBundle.load('assets/fonts/Vazirmatn.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  test(
    'size defaults, failed save, reopen and backup replacement retain the real preference',
    () async {
      final repo = FailingSettings(f.database.connection, f.clock);
      final appearance = AppearanceController(() async => repo);
      await appearance.load();
      expect(appearance.size, DisplaySize.medium);
      await appearance.select(DisplaySize.small);
      repo.fail = true;
      await appearance.select(DisplaySize.large);
      expect(appearance.size, DisplaySize.small);
      expect(appearance.error, isNotNull);
      appearance.dispose();
      await f.reopen();
      final reopened = AppearanceController(() async => f.services.settings);
      await reopened.load();
      expect(reopened.size, DisplaySize.small);
      final backup = await f.services.backups.prepare();
      final bytes = await File(backup.path).readAsBytes();
      await reopened.select(DisplaySize.large);
      await f.services.backups.restore(
        await f.services.backups.validate(bytes, 'size.zip'),
      );
      await reopened.load();
      expect(reopened.size, DisplaySize.small);
      expect(const AppTextScaler(TextScaler.linear(2), .875).scale(16), 28);
      reopened.dispose();
    },
  );

  test(
    'unused deletion is atomic, retryable, permanent after reopen, and backup compatible',
    () async {
      final unit = (await f.services.settings.units()).first.meta.id;
      final p = await f.services.inventory.createProduct(
        name: 'Unused item',
        unitId: unit,
      );
      final operation = id();
      await f.database.connection.execute(
        "CREATE TRIGGER fail_delete_receipt BEFORE INSERT ON inventory_operations WHEN NEW.kind='delete_product' BEGIN SELECT RAISE(ABORT,'disk failure'); END",
      );
      await expectLater(
        f.services.inventory.deleteUnusedProduct(
          p.meta.id,
          operationId: operation,
        ),
        throwsA(anything),
      );
      expect(await f.count('products'), 1);
      await f.database.connection.execute('DROP TRIGGER fail_delete_receipt');
      await f.services.inventory.deleteUnusedProduct(
        p.meta.id,
        operationId: operation,
      );
      await f.reopen();
      await f.services.inventory.deleteUnusedProduct(
        p.meta.id,
        operationId: operation,
      );
      expect(await f.count('products'), 0);
      final backup = await f.services.backups.prepare();
      final preview = await f.services.backups.validate(
        await File(backup.path).readAsBytes(),
        'deleted.zip',
      );
      await f.services.backups.restore(preview);
      await f.services.inventory.deleteUnusedProduct(
        p.meta.id,
        operationId: operation,
      );
      expect(await f.count('products'), 0);
      expect(await f.count('daily_records'), 0);
      expect(await f.count('ledger_entries'), 0);
    },
  );

  test(
    'history blocks deletion even at zero; archive and stable unit remain available',
    () async {
      final unit = (await f.services.settings.units()).first.meta.id;
      final p = await f.services.inventory.createProduct(
        name: 'Used item',
        unitId: unit,
      );
      final b = await f.services.inventory.createBatch(
        productId: p.meta.id,
        receivedDate: f.clock.today(),
        openingQuantity: 1,
      );
      await expectLater(
        f.services.inventory.deleteUnusedProduct(p.meta.id, operationId: id()),
        throwsA(isA<ValidationException>()),
      );
      await f.services.inventory.adjust(
        operationId: id(),
        batchId: b.meta.id,
        delta: -1,
      );
      await expectLater(
        f.services.inventory.deleteUnusedProduct(p.meta.id, operationId: id()),
        throwsA(isA<ValidationException>()),
      );
      await f.services.inventory.archiveProduct(
        p.meta.id,
        archived: true,
        operationId: id(),
      );
      expect((await f.services.inventory.product(p.meta.id)).unitId, unit);
      expect(await f.count('stock_movements'), 2);
    },
  );

  late InventoryController inventory;
  late DailyRecordsController daily;
  late DebtController debt;
  late AppController app;
  final screenshotKey = GlobalKey();
  Future<void> open(
    WidgetTester tester, {
    InventoryRepository? repository,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    inventory = InventoryController(
      clock: f.clock,
      resolve: () async => (
        inventory: repository ?? f.services.inventory,
        settings: f.services.settings,
      ),
    );
    daily = DailyRecordsController(
      clock: f.clock,
      resolve: () async => f.services.dailyRecords,
    );
    debt = DebtController(
      clock: f.clock,
      resolve: () async => f.services.debtors,
    );
    app = AppController(clock: f.clock, load: f.services.home.read);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      inventory.dispose();
      daily.dispose();
      debt.dispose();
      app.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: screenshotKey,
        child: PharmacyApp(
          controller: app,
          inventory: inventory,
          daily: daily,
          debt: debt,
        ),
      ),
    );
    await frames(tester, 18);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull, reason: name);
    if (!const bool.fromEnvironment('APP_STYLE_SCREENSHOTS')) return;
    await tester.runAsync(() async {
      final image =
          await (screenshotKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/style-review').create(recursive: true);
      await File(
        'build/style-review/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> inventoryTab(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.inventory_2_outlined).last);
    await frames(tester);
  }

  testWidgets(
    'settings changes the whole app immediately and produces small medium large screen review',
    (tester) async {
      await tester.runAsync(f.seed);
      await open(tester);
      await capture(tester, 'home-medium');
      await tester.tap(find.byTooltip('Settings'));
      await frames(tester);
      for (final size in [
        DisplaySize.small,
        DisplaySize.large,
        DisplaySize.medium,
      ]) {
        final choice = find.widgetWithText(ChoiceChip, size.label);
        await reveal(tester, choice);
        await tester.tap(choice);
        await frames(tester);
        expect(tester.widget<ChoiceChip>(choice).selected, isTrue);
        expect(
          (await tester.runAsync(
            () => f.services.settings.preference(
              AppearanceController.preferenceKey,
            ),
          ))!.value,
          size.name,
        );
        final media = MediaQuery.of(tester.element(choice));
        expect(media.textScaler.scale(16), 16 * size.factor);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 1500));
        await frames(tester);
        await capture(tester, 'settings-${size.name}');
      }
      await tester.pageBack();
      await frames(tester);
      await inventoryTab(tester);
      await capture(tester, 'inventory-medium');
      await reveal(
        tester,
        find.byTooltip('Remove 1 Bottle from ${f.medicine.name}'),
      );
      await capture(tester, 'inventory-card-medium');
      final semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
      await tester.tap(find.byIcon(Icons.bar_chart_outlined).last);
      await frames(tester);
      await capture(tester, 'daily-medium');
      await tester.tap(find.byIcon(Icons.people_outline).last);
      await frames(tester);
      await capture(tester, 'debtors-medium');
    },
  );

  testWidgets(
    'one batch shortcuts change exactly one, reject duplicate taps, Undo and lost acknowledgment retry',
    (tester) async {
      final unit = (await tester.runAsync(
        () => f.services.settings.units(),
      ))!.first;
      final p = (await tester.runAsync(
        () => f.services.inventory.createProduct(
          name: 'Single bottle',
          unitId: unit.meta.id,
        ),
      ))!;
      final b = (await tester.runAsync(
        () => f.services.inventory.createBatch(
          productId: p.meta.id,
          receivedDate: f.clock.today(),
          openingQuantity: 2,
        ),
      ))!;
      final repo = DelayedInventory(f.database.connection, f.clock);
      await open(tester, repository: repo);
      await inventoryTab(tester);
      final minus = find.byTooltip('Remove 1 ${unit.name} from ${p.name}');
      await reveal(tester, minus);
      repo.gate = Completer<void>();
      await tester.tap(minus);
      await tester.tap(minus);
      await frames(tester);
      expect(repo.calls.length, 1);
      repo.gate!.complete();
      repo.gate = null;
      await frames(tester);
      expect((await tester.runAsync(() => repo.batch(b.meta.id)))!.quantity, 1);
      await tester.tap(find.text('Undo'));
      await frames(tester);
      expect((await tester.runAsync(() => repo.batch(b.meta.id)))!.quantity, 2);
      repo.lose = true;
      await reveal(tester, minus);
      await tester.tap(minus);
      await frames(tester);
      expect((await tester.runAsync(() => repo.batch(b.meta.id)))!.quantity, 1);
      await tester.tap(find.text('Retry'));
      await frames(tester);
      expect(repo.calls.last, repo.calls[repo.calls.length - 2]);
      expect((await tester.runAsync(() => repo.batch(b.meta.id)))!.quantity, 1);
      await reveal(tester, minus);
      await tester.tap(minus);
      await frames(tester);
      expect((await tester.runAsync(() => repo.batch(b.meta.id)))!.quantity, 0);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) =>
                    w is IconButton &&
                    w.tooltip == 'Remove 1 ${unit.name} from ${p.name}',
              ),
            )
            .onPressed,
        isNull,
      );
      final plus = find.byTooltip('Add 1 ${unit.name} to ${p.name}');
      await reveal(tester, plus);
      await tester.tap(plus);
      await frames(tester);
      expect((await tester.runAsync(() => repo.batch(b.meta.id)))!.quantity, 1);
      expect(await tester.runAsync(() => f.count('daily_records')), 0);
      expect(await tester.runAsync(() => f.count('ledger_entries')), 0);
    },
  );

  testWidgets(
    'multiple batches require a choice, cancellation does nothing and selected batch alone changes',
    (tester) async {
      await tester.runAsync(f.seed);
      await tester.runAsync(
        () => f.services.settings.setPreference(
          AppearanceController.preferenceKey,
          'large',
        ),
      );
      await open(tester, size: const Size(320, 640), scale: 2);
      await inventoryTab(tester);
      final minus = find.byTooltip('Remove 1 Bottle from ${f.medicine.name}');
      await reveal(tester, minus);
      await tester.tap(minus);
      await frames(tester);
      expect(
        (await tester.runAsync(
          () => f.services.inventory.batch(f.todayBatch.meta.id),
        ))!.quantity,
        8,
      );
      await capture(tester, 'batch-choice-200');
      await tester.tap(find.byTooltip('Cancel stock adjustment'));
      await frames(tester);
      await reveal(tester, minus);
      await tester.tap(minus);
      await frames(tester);
      final selection = find.byKey(
        ValueKey('quick-batch-${f.laterBatch.meta.id}'),
      );
      await reveal(tester, selection);
      await tester.tap(selection);
      await frames(tester);
      expect(
        (await tester.runAsync(
          () => f.services.inventory.batch(f.todayBatch.meta.id),
        ))!.quantity,
        8,
      );
      expect(
        (await tester.runAsync(
          () => f.services.inventory.batch(f.laterBatch.meta.id),
        ))!.quantity,
        4,
      );
      await tester.tap(find.text('Undo'));
      await frames(tester);
      expect(
        (await tester.runAsync(
          () => f.services.inventory.batch(f.laterBatch.meta.id),
        ))!.quantity,
        5,
      );
      expect(await tester.runAsync(() => f.count('daily_records')), 5);
      expect(await tester.runAsync(() => f.count('ledger_entries')), 3);
    },
  );

  testWidgets(
    'item detail keeps full stock forms and unused deletion requires confirmation',
    (tester) async {
      final unit = (await tester.runAsync(
        () => f.services.settings.units(),
      ))!.first;
      final p = (await tester.runAsync(
        () => f.services.inventory.createProduct(
          name: 'Unused item',
          unitId: unit.meta.id,
        ),
      ))!;
      await open(tester);
      await inventoryTab(tester);
      await reveal(tester, find.text(p.name));
      await tester.tap(find.text(p.name));
      await frames(tester);
      expect(find.byType(ProductDetailScreen), findsOneWidget);
      expect(find.text('Add stock'), findsOneWidget);
      final deletion = find.widgetWithText(TextButton, 'Delete item');
      await reveal(tester, deletion);
      await tester.tap(deletion);
      await frames(tester);
      await tester.tap(find.text('Cancel'));
      await frames(tester);
      expect(await tester.runAsync(() => f.count('products')), 1);
      await tester.tap(deletion);
      await frames(tester);
      await capture(tester, 'delete-confirmation');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Delete item'),
        ),
      );
      await frames(tester);
      expect(await tester.runAsync(() => f.count('products')), 0);
      expect(find.byType(InventoryScreen), findsOneWidget);
    },
  );
}
