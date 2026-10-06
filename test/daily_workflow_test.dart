import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacyms/app/application/app_controller.dart';
import 'package:pharmacyms/app/presentation/pharmacy_app.dart';
import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/core/domain/money.dart';
import 'package:pharmacyms/core/presentation/form_fields.dart';
import 'package:pharmacyms/features/daily_records/application/daily_records_controller.dart';
import 'package:pharmacyms/features/daily_records/data/sqlite_daily_records_repository.dart';
import 'package:pharmacyms/features/daily_records/domain/daily_record.dart';
import 'package:pharmacyms/features/daily_records/domain/daily_report.dart';
import 'package:pharmacyms/features/daily_records/presentation/daily_record_form.dart';
import 'package:pharmacyms/features/daily_records/presentation/daily_record_detail.dart';
import 'package:pharmacyms/features/daily_records/presentation/trend_panel.dart';
import 'package:pharmacyms/features/inventory/application/inventory_controller.dart';
import 'support/inventory_database.dart';
import 'package:pharmacyms/features/debtors/application/debt_controller.dart';

class _Repository extends SqliteDailyRecordsRepository {
  _Repository(super.db, super.clock);
  bool loseSave = false,
      loseDelete = false,
      failReport = false,
      failDate = false;
  @override
  Future<DailyRecord?> onDate(BusinessDate date) async {
    if (failDate) throw StateError('Injected date read failure');
    return super.onDate(date);
  }

  Completer<void>? delay;
  int saves = 0;
  @override
  Future<DailyRecord> save({
    String? operationId,
    String? id,
    required BusinessDate date,
    required Money sales,
    required Money profit,
    String? note,
  }) async {
    saves++;
    await delay?.future;
    final value = await super.save(
      operationId: operationId,
      id: id,
      date: date,
      sales: sales,
      profit: profit,
      note: note,
    );
    if (loseSave) {
      loseSave = false;
      throw StateError('Injected acknowledgment loss');
    }
    return value;
  }

  @override
  Future<void> delete(String id, {String? operationId}) async {
    await super.delete(id, operationId: operationId);
    if (loseDelete) {
      loseDelete = false;
      throw StateError('Injected acknowledgment loss');
    }
  }

  @override
  Future<DailyReport> report(ReportRange range) async {
    if (failReport) throw StateError('Injected read failure');
    return super.report(range);
  }
}

Future<void> frames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 160 && !ready(); i++) {
    await frames(tester, count: 1);
  }
  expect(ready(), isTrue, reason: 'Persisted UI state did not appear');
  await frames(tester);
}

Future<void> tap(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      300,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 60,
    );
  }
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await frames(tester);
}

Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is AppTextField && w.label == label),
  matching: find.byType(TextFormField),
);
Future<void> enter(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(field(label));
  await tester.enterText(field(label), text);
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Vazirmatn',
    )..addFont(rootBundle.load('assets/fonts/Vazirmatn.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  late InventoryDatabase f;
  late _Repository repo;
  late DailyRecordsController daily;
  late InventoryController inventory;
  late AppController app;
  final shot = GlobalKey();
  setUp(() async {
    f = InventoryDatabase();
    await f.open();
    repo = _Repository(f.database.connection, f.clock);
    daily = DailyRecordsController(clock: f.clock, resolve: () async => repo);
    inventory = InventoryController(
      clock: f.clock,
      resolve: () async =>
          (inventory: f.services.inventory, settings: f.services.settings),
    );
    app = AppController(clock: f.clock, load: f.services.home.read);
  });
  tearDown(() async {
    daily.dispose();
    inventory.dispose();
    app.dispose();
    await f.close();
  });
  Future<void> open(WidgetTester tester) async {
    final debt = DebtController(
      clock: f.clock,
      resolve: () async => f.services.debtors,
    );
    addTearDown(debt.dispose);
    addTearDown(() async {
      inventory.stopDayWatch();
      await tester.pumpWidget(const SizedBox.shrink());
      await frames(tester);
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: PharmacyApp(
          controller: app,
          inventory: inventory,
          daily: daily,
          debt: debt,
        ),
      ),
    );
    await until(
      tester,
      () =>
          find.text('Record today').evaluate().isNotEmpty ||
          find.text("Edit today's record").evaluate().isNotEmpty,
    );
  }

  Future<void> recordsTab(WidgetTester tester) async {
    await tap(tester, find.byIcon(Icons.bar_chart_outlined).last);
    await until(
      tester,
      () =>
          find.text('Recorded totals').evaluate().isNotEmpty ||
          find.text('Unable to open local data').evaluate().isNotEmpty,
    );
  }

  Future<void> seed(
    WidgetTester tester,
    String date, {
    String sales = '0',
    String profit = '0',
  }) async {
    await tester.runAsync(
      () => f.services.dailyRecords.save(
        date: BusinessDate.parse(date),
        sales: Money.parse(sales),
        profit: Money.parse(profit),
      ),
    );
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('PHASE4_SCREENSHOTS')) return;
    await frames(tester);
    await tester.runAsync(() async {
      final boundary =
          shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('build/phase4-review');
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'Home record today accepts Persian decimals and loss sign; edit replaces figures and confirmed deletion refreshes Home',
    (tester) async {
      await open(tester);
      await tap(tester, find.text('Record today'));
      await until(
        tester,
        () => find.byType(DailyRecordForm).evaluate().isNotEmpty,
      );
      expect(
        tester.widget<TextFormField>(field('Sales (AFN)')).controller!.text,
        isEmpty,
      );
      await enter(tester, 'Sales (AFN)', '۵۰٬۰۰۰٫۰۱');
      await enter(tester, 'Profit (AFN)', '۱۲٫۳۴');
      await tap(tester, find.text('Switch profit / loss sign'));
      await enter(tester, 'Note (optional)', 'یادداشت Amoxicillin');
      await tap(tester, find.text('Save record'));
      await until(
        tester,
        () =>
            find.text("Edit today's record").evaluate().isNotEmpty &&
            find.byType(DailyRecordForm).evaluate().isEmpty,
      );
      expect(find.text('AFN 50,000.01'), findsOneWidget);
      expect(find.text('AFN -12.34'), findsOneWidget);
      await tap(tester, find.text("Edit today's record"));
      await until(
        tester,
        () => find.byType(DailyRecordForm).evaluate().isNotEmpty,
      );
      expect(
        tester.widget<TextFormField>(field('Note (optional)')).controller!.text,
        'یادداشت Amoxicillin',
      );
      await enter(tester, 'Sales (AFN)', '0');
      await enter(tester, 'Profit (AFN)', '1.01');
      await tap(tester, find.text('Save changes'));
      await until(
        tester,
        () => find.byType(DailyRecordForm).evaluate().isEmpty,
      );
      expect(find.text('AFN 0.00'), findsOneWidget);
      expect(find.text('AFN 1.01'), findsOneWidget);
      await recordsTab(tester);
      await tap(tester, find.text('Today'));
      await until(
        tester,
        () => find.text('1 of 1 days recorded').evaluate().isNotEmpty,
      );
      await tap(tester, find.widgetWithText(ListTile, '05 Oct 2026'));
      await until(
        tester,
        () =>
            find.byType(DailyRecordDetail).evaluate().isNotEmpty &&
            find.text('Edit record').evaluate().isNotEmpty,
      );
      await tap(tester, find.byTooltip('Record actions'));
      await tap(tester, find.text('Delete record'));
      expect(find.textContaining('Sales: AFN 0.00'), findsOneWidget);
      await tap(tester, find.text('Cancel'));
      expect(await tester.runAsync(() => f.count('daily_records')), 1);
      await tap(tester, find.byTooltip('Record actions'));
      await tap(tester, find.text('Delete record'));
      await tap(tester, find.widgetWithText(TextButton, 'Delete record'));
      await until(
        tester,
        () => find.text('0 of 1 days recorded').evaluate().isNotEmpty,
      );
      await tap(tester, find.byIcon(Icons.home_outlined));
      await until(
        tester,
        () => find.text('Record today').evaluate().isNotEmpty,
      );
      expect(find.text('Not recorded'), findsOneWidget);
      expect(await tester.runAsync(() => f.count('daily_records')), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'validation keeps input; prior-date conflict offers saved record without summing; dirty cancel preserves input',
    (tester) async {
      await seed(tester, '2026-10-04', sales: '12', profit: '-1');
      await open(tester);
      await recordsTab(tester);
      await tap(tester, find.text('Add record'));
      await tap(tester, find.text('Save record'));
      expect(
        find.textContaining('Enter an amount with up to two decimal places.'),
        findsWidgets,
      );
      await enter(tester, 'Business date', '2026-10-06');
      await enter(tester, 'Sales (AFN)', '-1');
      await enter(tester, 'Profit (AFN)', '1.234');
      await tap(tester, find.text('Save record'));
      expect(
        find.text('Future business dates are not allowed.'),
        findsOneWidget,
      );
      expect(find.text('Enter a nonnegative amount.'), findsOneWidget);
      await enter(tester, 'Business date', '۲۰۲۶-۱۰-۰۴');
      await enter(tester, 'Sales (AFN)', '99');
      await enter(tester, 'Profit (AFN)', '0');
      await tap(tester, find.text('Save record'));
      await until(
        tester,
        () => find.text('Open existing record').evaluate().isNotEmpty,
      );
      expect(await tester.runAsync(() => f.count('daily_records')), 1);
      await tester.pageBack();
      await frames(tester);
      await tap(tester, find.text('Cancel'));
      expect(
        tester.widget<TextFormField>(field('Sales (AFN)')).controller!.text,
        '99',
      );
      await tap(tester, find.text('Open existing record'));
      await tap(tester, find.text('Open record'));
      expect(
        tester.widget<TextFormField>(field('Sales (AFN)')).controller!.text,
        '12.00',
      );
      await enter(tester, 'Sales (AFN)', '13');
      await tap(tester, find.text('Save changes'));
      await until(
        tester,
        () =>
            find.text('Daily record').evaluate().isNotEmpty &&
            find.byType(DailyRecordForm).evaluate().isEmpty,
      );
      expect(await tester.runAsync(() => f.count('daily_records')), 1);
      expect(
        (await tester.runAsync(
          () => repo.onDate(BusinessDate(2026, 10, 4)),
        ))!.sales.minor,
        1300,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'duplicate taps and lost save/delete acknowledgment reconcile a durable operation',
    (tester) async {
      repo.delay = Completer<void>();
      repo.loseSave = true;
      await open(tester);
      await tap(tester, find.text('Record today'));
      await until(
        tester,
        () => find.byType(DailyRecordForm).evaluate().isNotEmpty,
      );
      await enter(tester, 'Sales (AFN)', '10.01');
      await enter(tester, 'Profit (AFN)', '0');
      await tester.tap(find.text('Save record'));
      await tester.tap(find.text('Save record'));
      await frames(tester);
      expect(find.text('Saving…'), findsOneWidget);
      expect(repo.saves, 1);
      repo.delay!.complete();
      await until(
        tester,
        () => find.text('Retry same save').evaluate().isNotEmpty,
      );
      expect(await tester.runAsync(() => f.count('daily_records')), 1);
      expect(
        tester.widget<TextFormField>(field('Sales (AFN)')).controller!.text,
        '10.01',
      );
      await tap(tester, find.text('Retry same save'));
      await until(
        tester,
        () =>
            find.text("Edit today's record").evaluate().isNotEmpty &&
            find.byType(DailyRecordForm).evaluate().isEmpty,
      );
      expect(await tester.runAsync(() => f.count('daily_operations')), 1);
      await recordsTab(tester);
      await tap(tester, find.text('Today'));
      await frames(tester);
      await tap(tester, find.widgetWithText(ListTile, '05 Oct 2026'));
      await until(tester, () => find.text('Edit record').evaluate().isNotEmpty);
      repo.loseDelete = true;
      await tap(tester, find.byTooltip('Record actions'));
      await tap(tester, find.text('Delete record'));
      await tap(tester, find.widgetWithText(TextButton, 'Delete record'));
      await until(
        tester,
        () => find.text('Retry deletion').evaluate().isNotEmpty,
      );
      expect(await tester.runAsync(() => f.count('daily_records')), 0);
      await tap(tester, find.text('Retry deletion'));
      await until(
        tester,
        () => find.text('0 of 1 days recorded').evaluate().isNotEmpty,
      );
      expect(await tester.runAsync(() => f.count('daily_operations')), 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'custom inclusive filters show missing days, exact selected loss, monthly coverage and comparison baselines',
    (tester) async {
      await seed(tester, '2026-09-30', sales: '10.10', profit: '-2.01');
      await seed(tester, '2026-10-02');
      await seed(tester, '2026-10-04', sales: '999');
      await open(tester);
      await recordsTab(tester);
      await tap(tester, find.text('Custom range'));
      await enter(tester, 'Start date', '2026-10-03');
      await enter(tester, 'End date', '2026-09-30');
      await tap(tester, find.text('Apply range'));
      expect(
        find.text('Start date must be on or before end date.'),
        findsOneWidget,
      );
      await enter(tester, 'Start date', '2026-09-30');
      await enter(tester, 'End date', '2026-10-03');
      await tap(tester, find.text('Apply range'));
      await until(
        tester,
        () => find.text('2 of 4 days recorded').evaluate().isNotEmpty,
      );
      expect(find.text('AFN 10.10'), findsOneWidget);
      expect(find.text('AFN -2.01'), findsOneWidget);
      await tap(tester, find.text('Profit (manual)'));
      await tap(tester, find.text('Previous value'));
      await tap(tester, find.text('Previous value'));
      await tap(tester, find.text('Previous value'));
      expect(find.text('Recorded profit: AFN -2.01'), findsOneWidget);
      expect(find.text('Loss · Below zero'), findsOneWidget);
      await tap(tester, find.text('Next value'));
      expect(find.text('Recorded profit: Not recorded'), findsOneWidget);
      await tap(tester, find.text('Next value'));
      expect(
        find.descendant(
          of: find.byType(TrendPanel),
          matching: find.text('Recorded profit: AFN 0.00'),
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('Monthly totals'));
      await tap(tester, find.text('Monthly data · accessible list'));
      expect(find.text('1 of 3 days recorded'), findsWidgets);
      expect(find.text('1 of 1 days recorded'), findsOneWidget);
      await tap(tester, find.text('Compare previous period'));
      expect(find.text('Sales change: Not available'), findsOneWidget);
      await tap(tester, find.text('Today'));
      await until(
        tester,
        () => find.text('No records in this period').evaluate().isNotEmpty,
      );
      expect(find.byType(TrendPanel), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'local day rollover updates financial Home and active Today filter; resume refreshes saved figures',
    (tester) async {
      await seed(tester, '2026-10-05', sales: '1', profit: '-1');
      await open(tester);
      await recordsTab(tester);
      await tap(tester, find.text('Today'));
      await until(
        tester,
        () => find.text('1 of 1 days recorded').evaluate().isNotEmpty,
      );
      f.clock.date = BusinessDate(2026, 10, 6);
      await tester.pump(const Duration(seconds: 31));
      await until(
        tester,
        () => find.text('0 of 1 days recorded').evaluate().isNotEmpty,
      );
      await tap(tester, find.byIcon(Icons.home_outlined));
      expect(find.text('Record today'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await seed(tester, '2026-10-06', sales: '2.22', profit: '-0.01');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await until(tester, () => find.text('AFN 2.22').evaluate().isNotEmpty);
      expect(find.text("Edit today's record"), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('report read failure exposes working Retry without fake totals', (
    tester,
  ) async {
    repo.failReport = true;
    await open(tester);
    repo.failDate = true;
    await tap(tester, find.text('Record today'));
    await until(
      tester,
      () => find.text('Unable to open local data').evaluate().isNotEmpty,
    );
    expect(find.byType(BackButton), findsOneWidget);
    repo.failDate = false;
    await tap(tester, find.text('Retry'));
    await until(
      tester,
      () => find.byType(DailyRecordForm).evaluate().isNotEmpty,
    );
    await tester.pageBack();
    await frames(tester);
    await recordsTab(tester);
    expect(find.text('Unable to open local data'), findsOneWidget);
    expect(find.text('Recorded totals'), findsNothing);
    repo.failReport = false;
    await tap(tester, find.text('Retry'));
    await until(
      tester,
      () => find.text('No records in this period').evaluate().isNotEmpty,
    );
    expect(find.text('0 of 7 days recorded'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '320px and 200 percent text keeps form with keyboard, charts and exact accessible data usable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final semantics = tester.ensureSemantics();
      try {
        await seed(tester, '2026-10-04', sales: '1.01', profit: '-0.01');
        await seed(tester, '2026-10-05', sales: '2', profit: '0.01');
        await open(tester);
        await recordsTab(tester);
        await tap(tester, find.text('Add record'));
        tester.view.viewInsets = const FakeViewPadding(bottom: 180);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump();
        await enter(tester, 'Business date', '2026-10-03');
        await enter(tester, 'Sales (AFN)', '0');
        await enter(tester, 'Profit (AFN)', '0');
        expect(
          tester.getRect(find.text('Save record')).bottom,
          lessThan(568 - 180),
        );
        await screenshot(tester, 'narrow-form');
        tester.view.resetViewInsets();
        await tester.pump();
        await tap(tester, find.text('Save record'));
        await until(
          tester,
          () => find.byType(DailyRecordDetail).evaluate().isNotEmpty,
        );
        await tester.pageBack();
        await frames(tester);
        await tap(tester, find.text('Profit (manual)'));
        final plot = find.byKey(const ValueKey('daily-trend-plot'));
        await tester.ensureVisible(plot);
        await frames(tester);
        await screenshot(tester, 'narrow-chart');
        final plotRect = tester.getRect(plot);
        await tester.tapAt(Offset(plotRect.right - 16, plotRect.top + 24));
        await frames(tester);
        expect(find.text('Selected: 05 Oct 2026'), findsOneWidget);
        await tester.ensureVisible(find.byType(TrendPanel));
        await tester.pump();
        await tap(tester, find.text('Previous value'));
        expect(find.text('Recorded profit: AFN -0.01'), findsOneWidget);
        await tester.ensureVisible(find.text('Selected: 04 Oct 2026'));
        await frames(tester);
        await screenshot(tester, 'narrow-chart-values');
        tester.platformDispatcher.textScaleFactorTestValue = 1;
        await tester.pump();
        await tester.drag(find.byType(Scrollable).last, const Offset(0, 3000));
        await frames(tester);
        await tester.ensureVisible(plot);
        await frames(tester);
        await screenshot(tester, 'phone-chart');
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await tester.pump();
        expect(find.bySemanticsLabel('Previous value'), findsOneWidget);
        await tap(tester, find.text('Monthly totals'));
        await tap(tester, find.text('Monthly data · accessible list'));
        expect(find.textContaining('Sales: AFN 3.01'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
