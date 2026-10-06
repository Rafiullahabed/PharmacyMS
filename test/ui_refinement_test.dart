import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacyms/app/application/app_controller.dart';
import 'package:pharmacyms/app/presentation/pharmacy_app.dart';
import 'package:pharmacyms/core/domain/money.dart';
import 'package:pharmacyms/core/presentation/app_theme.dart';
import 'package:pharmacyms/core/presentation/components.dart';
import 'package:pharmacyms/core/presentation/form_fields.dart';
import 'package:pharmacyms/core/presentation/workflow.dart';
import 'package:pharmacyms/features/backup/application/backup_controller.dart';
import 'package:pharmacyms/features/backup/application/backup_files.dart';
import 'package:pharmacyms/features/backup/data/sqlite_backup_repository.dart';
import 'package:pharmacyms/features/backup/domain/backup.dart';
import 'package:pharmacyms/features/backup/presentation/backup_screen.dart';
import 'package:pharmacyms/features/daily_records/application/daily_records_controller.dart';
import 'package:pharmacyms/features/daily_records/presentation/daily_record_detail.dart';
import 'package:pharmacyms/features/daily_records/presentation/daily_record_form.dart';
import 'package:pharmacyms/features/daily_records/presentation/daily_records_screen.dart';
import 'package:pharmacyms/features/daily_records/presentation/trend_panel.dart';
import 'package:pharmacyms/features/daily_records/domain/daily_report.dart';
import 'package:pharmacyms/features/inventory/presentation/date_spec_field.dart';
import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/features/debtors/application/debt_controller.dart';
import 'package:pharmacyms/features/debtors/domain/debt.dart';
import 'package:pharmacyms/features/debtors/presentation/customer_detail.dart';
import 'package:pharmacyms/features/debtors/presentation/customer_form.dart';
import 'package:pharmacyms/features/debtors/presentation/debtors_screen.dart';
import 'package:pharmacyms/features/debtors/presentation/ledger_detail.dart';
import 'package:pharmacyms/features/debtors/presentation/ledger_form.dart';
import 'package:pharmacyms/features/inventory/application/inventory_controller.dart';
import 'package:pharmacyms/features/inventory/domain/inventory.dart';
import 'package:pharmacyms/features/inventory/presentation/batch_form.dart';
import 'package:pharmacyms/features/inventory/presentation/detail_screens.dart';
import 'package:pharmacyms/features/inventory/presentation/history_screen.dart';
import 'package:pharmacyms/features/inventory/presentation/inventory_screen.dart';
import 'package:pharmacyms/features/inventory/presentation/product_form.dart';
import 'package:pharmacyms/features/inventory/presentation/stock_adjustment.dart';
import 'package:pharmacyms/features/settings/presentation/settings_screen.dart';
import 'package:pharmacyms/features/settings/presentation/units_screen.dart';
import 'support/visual_fixture.dart';
import 'support/visual_test_binding.dart';

class ReviewFiles implements BackupFiles {
  SelectedBackup? selection;
  @override
  Future<SelectedBackup?> pick() async => selection;
  @override
  Future<ExportOutcome> save(PreparedBackup backup) async =>
      ExportOutcome.cancelled;
  @override
  Future<ExportOutcome> share(PreparedBackup backup, Rect origin) async =>
      ExportOutcome.cancelled;
}

Future<void> frames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
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
      maxScrolls: 60,
    );
  }
  await tester.ensureVisible(target);
  await frames(tester, 4);
}

Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is AppTextField && w.label == label),
  matching: find.byType(TextFormField),
);

void main() {
  VisualTestBinding();
  setUpAll(() async {
    await (FontLoader(
      'Vazirmatn',
    )..addFont(rootBundle.load('assets/fonts/Vazirmatn.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  late VisualFixture f;
  late InventoryController inventory;
  late DailyRecordsController daily;
  late DebtController debt;
  late AppController app;
  late BackupController backup;
  late ReviewFiles files;
  final shot = GlobalKey();
  setUp(() async {
    f = VisualFixture();
    await f.open();
    await f.seed();
    inventory = InventoryController(
      clock: f.clock,
      resolve: () async =>
          (inventory: f.services.inventory, settings: f.services.settings),
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
    files = ReviewFiles();
    backup = BackupController(
      resolve: () async => SqliteBackupRepository(f.database, f.clock),
      files: files,
      onRestored: () async {},
    );
  });
  tearDown(() async {
    inventory.dispose();
    daily.dispose();
    debt.dispose();
    app.dispose();
    backup.dispose();
    await f.close();
  });

  Future<void> capture(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull, reason: name);
    if (!const bool.fromEnvironment('PHASE7_SCREENSHOTS')) return;
    await tester.runAsync(() async {
      final image =
          await (shot.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/phase7-review').create(recursive: true);
      await File(
        'build/phase7-review/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> open(
    WidgetTester tester,
    Widget page, {
    double scale = 1,
    double keyboard = 0,
  }) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: MaterialApp(
          theme: appTheme(),
          debugShowCheckedModeBanner: false,
          navigatorKey: navigator,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: child!,
          ),
          home: const Scaffold(),
        ),
      ),
    );
    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => page));
    await frames(tester, 15);
  }

  void viewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      inventory.stopDayWatch();
      await tester.pumpWidget(const SizedBox.shrink());
      await frames(tester);
    });
  }

  for (final mode in [(390.0, 844.0, 1.0), (320.0, 640.0, 2.0)]) {
    testWidgets('screen gallery ${mode.$1.toInt()}px at ${mode.$3 * 100}% text', (
      tester,
    ) async {
      viewport(tester, Size(mode.$1, mode.$2));
      final suffix = '${mode.$1.toInt()}-${mode.$3.toInt()}x';
      final record = await tester.runAsync(
        () => f.services.dailyRecords.onDate(f.clock.today().addDays(-1)),
      );
      final unit = (await tester.runAsync(
        () => f.services.settings.units(),
      ))!.first.name;
      final screens = <String, Widget>{
        'home': NavigationShell(
          controller: app,
          inventory: inventory,
          daily: daily,
          debt: debt,
          backups: backup,
        ),
        'inventory': Builder(
          builder: (context) => Scaffold(
            appBar: pageAppBar(context, title: 'Inventory'),
            body: InventoryScreen(controller: inventory),
          ),
        ),
        'expiry-results': Scaffold(
          body: InventoryScreen(
            controller: inventory,
            initialFilter: InventoryFilter.expiringSoon,
          ),
        ),
        'product': ProductDetailScreen(
          controller: inventory,
          productId: f.medicine.meta.id,
        ),
        'batch': BatchDetailScreen(
          controller: inventory,
          batchId: f.laterBatch.meta.id,
        ),
        'stock-history': HistoryScreen(
          controller: inventory,
          productId: f.medicine.meta.id,
          unit: unit,
        ),
        'product-form': ProductForm(controller: inventory, product: f.persian),
        'batch-form': BatchForm(
          controller: inventory,
          product: f.medicine,
          unit: unit,
          batch: f.laterBatch,
        ),
        'daily': Builder(
          builder: (context) => Scaffold(
            appBar: pageAppBar(context, title: 'Daily Records'),
            body: DailyRecordsScreen(controller: daily),
          ),
        ),
        'daily-detail': DailyRecordDetail(
          controller: daily,
          id: record!.meta.id,
        ),
        'daily-form': DailyRecordForm(controller: daily, record: record),
        'debtors': Builder(
          builder: (context) => Scaffold(
            appBar: pageAppBar(context, title: 'Debtors'),
            body: DebtorsScreen(controller: debt),
          ),
        ),
        'customer': CustomerDetail(controller: debt, id: f.customer.meta.id),
        'customer-form': CustomerForm(controller: debt, customer: f.customer),
        'ledger': LedgerDetail(controller: debt, id: f.payment.meta.id),
        'payment-form': LedgerForm(
          controller: debt,
          customer: f.customer,
          balance: Money.parse('600'),
          kind: LedgerKind.payment,
        ),
        'correction-form': LedgerForm(
          controller: debt,
          customer: f.customer,
          balance: Money.parse('600'),
          kind: LedgerKind.payment,
          entry: f.payment,
        ),
        'corrections': CorrectionHistory(
          controller: debt,
          customerId: f.customer.meta.id,
        ),
        'settings': SettingsScreen(controller: inventory, backups: backup),
        'units': UnitsScreen(controller: inventory),
        'unit-form': UnitForm(controller: inventory),
        'backup': BackupScreen(controller: backup),
      };
      for (final screen in screens.entries) {
        await open(tester, screen.value, scale: mode.$3);
        if (mode.$3 == 1) {
          final semantics = tester.ensureSemantics();
          try {
            await tester.pump();
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
              reason: screen.key,
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
              reason: screen.key,
            );
          } finally {
            semantics.dispose();
          }
        }
        await capture(tester, '${screen.key}-$suffix');
        // Exercise content outside the first viewport, including long histories and date controls.
        final scrolls = find
            .byWidgetPredicate(
              (w) =>
                  w is Scrollable &&
                  w.axis == Axis.vertical &&
                  w.restorationId != 'editable',
            )
            .hitTestable();
        if (scrolls.evaluate().isNotEmpty) {
          for (var i = 0; i < 3; i++) {
            await tester.drag(scrolls.last, const Offset(0, -420));
            await frames(tester, 2);
            expect(
              tester.takeException(),
              isNull,
              reason: '${screen.key} after scrolling',
            );
          }
          await capture(tester, '${screen.key}-scrolled-$suffix');
        }
      }
    });
  }

  testWidgets('large-text shell scrolls filters and results together', (
    tester,
  ) async {
    viewport(tester, const Size(320, 640));
    await open(
      tester,
      NavigationShell(
        controller: app,
        inventory: inventory,
        daily: daily,
        debt: debt,
      ),
      scale: 2,
    );
    await tester.tap(find.byIcon(Icons.inventory_2_outlined).last);
    await frames(tester);
    final chip = find.widgetWithText(FilterChip, 'Low stock');
    await tester.ensureVisible(chip);
    await frames(tester);
    final chipBounds = tester.getRect(chip);
    expect(chipBounds.height, greaterThanOrEqualTo(48));
    expect(chipBounds.bottom, lessThanOrEqualTo(640));
    await tester.tap(chip);
    await frames(tester);
    expect(tester.widget<FilterChip>(chip).selected, isTrue);
    await capture(tester, 'inventory-shell-filters-2x');
    final shortcut = find.byTooltip('Remove 1 Bottle from ${f.medicine.name}');
    await reveal(tester, shortcut);
    expect(shortcut.hitTestable(), findsOneWidget);
    await capture(tester, 'inventory-shell-results-2x');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'forms keep Save reachable with 200% text and short keyboard viewport',
    (tester) async {
      viewport(tester, const Size(568, 320));
      await open(
        tester,
        CustomerForm(controller: debt),
        scale: 2,
        keyboard: 120,
      );
      await reveal(tester, field('Customer name'));
      await tester.enterText(field('Customer name'), 'مریم · Maryam');
      await frames(tester);
      await reveal(tester, find.text('Save customer'));
      await frames(tester);
      await capture(tester, 'customer-landscape-keyboard-2x');
      expect(
        tester.getRect(find.text('Save customer')).top,
        greaterThanOrEqualTo(0),
      );
      expect(
        tester.getRect(find.text('Save customer')).bottom,
        lessThanOrEqualTo(200),
      );
    },
  );

  testWidgets(
    'mixed-language search preserves selection and input direction immediately',
    (tester) async {
      viewport(tester, const Size(320, 640));
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await open(
        tester,
        Scaffold(
          body: SearchField(
            controller: controller,
            label: 'Search items',
            clearLabel: 'Clear search',
            onChanged: (_) {},
          ),
        ),
        scale: 2,
      );
      await tester.enterText(find.byType(TextField), 'کریم · Skin cream');
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      );
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).textDirection,
        TextDirection.rtl,
      );
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 4),
      );
      expect(controller.text, 'کریم · Skin cream');
      await capture(tester, 'persian-selection-2x');
    },
  );

  testWidgets('full mixed-language descriptions use each paragraph direction', (
    tester,
  ) async {
    viewport(tester, const Size(320, 640));
    await open(
      tester,
      const Scaffold(
        body: PageContent(
          children: [
            ContentText('پرداخت نقدی\nReceipt checked with customer.'),
          ],
        ),
      ),
      scale: 2,
    );
    expect(
      tester.widget<Text>(find.text('پرداخت نقدی')).textDirection,
      TextDirection.rtl,
    );
    expect(
      tester
          .widget<Text>(find.text('Receipt checked with customer.'))
          .textDirection,
      TextDirection.ltr,
    );
    await capture(tester, 'mixed-paragraphs-2x');
  });

  testWidgets(
    'multiline cursor direction follows its paragraph without rewriting text',
    (tester) async {
      viewport(tester, const Size(320, 640));
      const original = 'پرداخت نقدی\nReceipt checked with customer.';
      final text = TextEditingController(text: original);
      addTearDown(text.dispose);
      await open(
        tester,
        Scaffold(
          body: PageContent(
            children: [
              AppTextField(controller: text, label: 'Description', maxLines: 5),
            ],
          ),
        ),
        scale: 2,
      );
      text.selection = TextSelection.collapsed(offset: original.length);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).textDirection,
        TextDirection.ltr,
      );
      text.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).textDirection,
        TextDirection.rtl,
      );
      expect(text.text, original);
      expect(
        text.selection,
        const TextSelection(baseOffset: 0, extentOffset: 6),
      );
      await capture(tester, 'multiline-cursor-2x');
    },
  );

  testWidgets(
    'reduced motion and loading/error controls have labels and 48px targets',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Column(
                children: [
                  const LoadingState(),
                  const ErrorNotice('Unable to save. Your input is kept.'),
                  TextButton(onPressed: () {}, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.bySemanticsLabel('Loading local data…'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    },
  );

  testWidgets(
    'manual batch selection, explicit preview, commit and Undo remain independent',
    (tester) async {
      viewport(tester, const Size(320, 640));
      await open(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => adjustStock(
                context,
                inventory,
                f.medicine.meta.id,
                remove: true,
              ),
              child: const Text('Adjust'),
            ),
          ),
        ),
        scale: 2,
      );
      await tester.tap(find.text('Adjust'));
      await frames(tester);
      expect(find.byType(StockAdjustment), findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .initialValue,
        isNull,
      );
      await capture(tester, 'stock-manual-batch-choice-2x');
      final dropdown = find.byType(DropdownButtonFormField<String>);
      await reveal(tester, dropdown);
      await tester.tap(dropdown);
      await frames(tester);
      final delivery = find.textContaining('October delivery');
      await reveal(tester, delivery);
      await tester.tap(delivery);
      await frames(tester);
      await reveal(tester, field('Quantity to remove'));
      await tester.enterText(field('Quantity to remove'), '2');
      await frames(tester);
      final preview = find.textContaining('Current 8');
      await reveal(tester, preview);
      await frames(tester);
      await capture(tester, 'stock-before-after-2x');
      final commit = find.widgetWithText(FilledButton, 'Remove stock');
      await reveal(tester, commit);
      await tester.tap(commit);
      await frames(tester, 16);
      expect(find.byType(StockAdjustment), findsNothing);
      expect(
        (await tester.runAsync(
          () => f.services.inventory.batch(f.todayBatch.meta.id),
        ))!.quantity,
        6,
      );
      await tester.tap(find.text('Undo'));
      await frames(tester, 16);
      expect(
        (await tester.runAsync(
          () => f.services.inventory.batch(f.todayBatch.meta.id),
        ))!.quantity,
        8,
      );
      expect(
        (await tester.runAsync(
          () => f.services.debtors.balance(f.customer.meta.id),
        ))!.decimal,
        '600.00',
      );
      expect(await tester.runAsync(() => f.count('daily_records')), 5);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'chart axes, selected loss and monthly data remain readable at 200%',
    (tester) async {
      viewport(tester, const Size(320, 640));
      final report = await tester.runAsync(
        () => f.services.dailyRecords.report(
          ReportPeriod.last7Days.range(f.clock.today()),
        ),
      );
      await open(
        tester,
        Scaffold(
          body: PageContent(children: [TrendPanel(report: report!)]),
        ),
        scale: 2,
      );
      await reveal(tester, find.text('Profit (manual)'));
      await tester.tap(find.text('Profit (manual)'));
      await frames(tester);
      final plot = find.byKey(const ValueKey('daily-trend-plot'));
      await reveal(tester, plot);
      await frames(tester);
      await capture(tester, 'chart-profit-2x');
      await reveal(tester, find.text('Previous value'));
      await tester.tap(find.text('Previous value'));
      await frames(tester);
      await reveal(tester, find.textContaining('Recorded profit: AFN -350.75'));
      await frames(tester);
      await capture(tester, 'chart-exact-loss-2x');
      await reveal(tester, find.text('Monthly totals'));
      await tester.tap(find.text('Monthly totals'));
      await frames(tester);
      await reveal(tester, find.text('Monthly data · accessible list'));
      await tester.tap(find.text('Monthly data · accessible list'));
      await frames(tester);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -420));
      await frames(tester);
      await capture(tester, 'monthly-accessible-data-2x');
    },
  );

  testWidgets(
    'month-only picker never invents a day or changes the source calendar',
    (tester) async {
      viewport(tester, const Size(320, 640));
      final key = GlobalKey<DateSpecFieldState>();
      await open(
        tester,
        Scaffold(
          body: PageContent(
            children: [
              DateSpecField(
                key: key,
                label: 'Expiry',
                today: f.clock.today(),
                expiry: true,
                initial: f.laterBatch.expiry,
                onChanged: () {},
              ),
            ],
          ),
        ),
        scale: 2,
      );
      await reveal(tester, find.text('Choose expiry month'));
      await tester.tap(find.text('Choose expiry month'));
      await frames(tester);
      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
      await capture(tester, 'solar-hijri-month-picker-2x');
      await tester.tap(find.text('Use month'));
      await frames(tester);
      expect(key.currentState!.value()!.day, isNull);
      expect(key.currentState!.value()!.calendar, DateCalendar.solarHijri);
      expect(key.currentState!.value()!.toMap(), f.laterBatch.expiry!.toMap());
    },
  );

  testWidgets(
    'restore preview and destructive confirmation stay scrollable with large text',
    (tester) async {
      viewport(tester, const Size(320, 640));
      await tester.runAsync(() async {
        final prepared = await SqliteBackupRepository(
          f.database,
          f.clock,
        ).prepare();
        files.selection = SelectedBackup(
          'review-backup.zip',
          await File(prepared.path).readAsBytes(),
        );
        await backup.select();
      });
      await open(tester, BackupScreen(controller: backup), scale: 2);
      await reveal(tester, find.text('Restore preview'));
      await frames(tester);
      await capture(tester, 'restore-preview-2x');
      await reveal(tester, find.text('Replace with this backup'));
      await tester.tap(find.text('Replace with this backup'));
      await frames(tester);
      await capture(tester, 'restore-confirmation-2x');
      await tester.tap(find.text('Cancel'));
      await frames(tester);
      expect(backup.preview, isNotNull);
      expect(await tester.runAsync(() => f.count('products')), 4);
    },
  );

  testWidgets(
    'tab search and filters survive navigation, details and Home read failure',
    (tester) async {
      viewport(tester, const Size(390, 844));
      var fail = false;
      final model = AppController(
        clock: f.clock,
        load: (date) {
          if (fail) throw StateError('Review-only read failure');
          return f.services.home.read(date);
        },
      );
      await open(
        tester,
        NavigationShell(
          controller: model,
          inventory: inventory,
          daily: daily,
          debt: debt,
        ),
      );
      await tester.tap(find.byIcon(Icons.inventory_2_outlined).last);
      await frames(tester);
      await tester.enterText(find.byType(TextField), 'Amoxicillin');
      await frames(tester);
      await tester.tap(find.byIcon(Icons.people_outline));
      await frames(tester);
      await tester.tap(find.byIcon(Icons.inventory_2_outlined).last);
      await frames(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Amoxicillin',
      );
      fail = true;
      await model.refresh();
      await frames(tester);
      expect(find.byType(InventoryScreen), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Amoxicillin',
      );
      await tester.tap(find.byIcon(Icons.home_outlined));
      await frames(tester);
      expect(find.text('Unable to open local data'), findsOneWidget);
      await capture(tester, 'home-recovery');
      fail = false;
      await tester.tap(find.text('Retry'));
      await frames(tester);
      await tester.tap(find.byIcon(Icons.inventory_2_outlined).last);
      await frames(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Amoxicillin',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
    },
  );

  test('text palette meets WCAG AA contrast on its actual surfaces', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
    }

    for (final color in [
      AppColors.text,
      AppColors.secondary,
      AppColors.primary,
      AppColors.success,
      AppColors.warning,
      AppColors.danger,
    ]) {
      expect(contrast(color, AppColors.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(color, AppColors.canvas), greaterThanOrEqualTo(4.5));
      expect(
        contrast(
          color,
          Color.alphaBlend(color.withValues(alpha: .08), AppColors.canvas),
        ),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(
      contrast(Colors.white, AppColors.primary),
      greaterThanOrEqualTo(4.5),
    );
  });

  test(
    'development fixture exports through production format without production seeding',
    () async {
      final prepared = await SqliteBackupRepository(
        f.database,
        f.clock,
      ).prepare();
      if (const bool.fromEnvironment('PHASE7_SCREENSHOTS')) {
        await Directory('build/phase7-review').create(recursive: true);
        await File(
          prepared.path,
        ).copy('build/phase7-review/visual-fixture.zip');
      }
      expect(
        (await f.services.debtors.balance(f.customer.meta.id)).decimal,
        '600.00',
      );
    },
  );
}
