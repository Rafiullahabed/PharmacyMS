import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacyms/app/application/app_controller.dart';
import 'package:pharmacyms/app/presentation/pharmacy_app.dart';
import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/core/domain/money.dart';
import 'package:pharmacyms/core/presentation/app_theme.dart';
import 'package:pharmacyms/core/presentation/components.dart';
import 'package:pharmacyms/core/presentation/form_fields.dart';
import 'package:pharmacyms/features/home/domain/home_summary.dart';
import 'support/fake_clock.dart';
import 'support/empty_inventory.dart';
import 'support/empty_daily.dart';
import 'support/empty_debt.dart';

HomeSummary emptySummary(BusinessDate date) => HomeSummary(
  today: date,
  products: 0,
  batches: 0,
  dailyRecords: 0,
  customers: 0,
  outstanding: BigInt.zero,
  units: [],
);

void main() {
  testWidgets('four tabs, honest empty states, Settings and back', (
    tester,
  ) async {
    final controller = AppController(
      clock: FakeClock(),
      load: (date) async => emptySummary(date),
    );
    addTearDown(controller.dispose);
    final inventory = emptyInventory();
    final daily = emptyDaily();
    final debt = emptyDebt();
    addTearDown(debt.dispose);
    addTearDown(daily.dispose);
    addTearDown(inventory.dispose);
    await tester.pumpWidget(
      PharmacyApp(
        controller: controller,
        inventory: inventory,
        daily: daily,
        debt: debt,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A clear view of your pharmacy'), findsOneWidget);
    expect(find.text('Add your first item'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.inventory_2_outlined).last);
    await tester.pumpAndSettle();
    expect(find.text('No items yet'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.bar_chart_outlined).last);
    await tester.pumpAndSettle();
    expect(find.text('No records in this period'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.people_outline).last);
    await tester.pumpAndSettle();
    expect(find.text('No customers yet'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Units'), findsOneWidget);
    expect(find.text('Backup & Restore'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Pharmacy Companion'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    '320px phone at 200 percent text keeps navigation and settings usable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = AppController(
        clock: FakeClock(),
        load: (date) async => emptySummary(date),
      );
      addTearDown(controller.dispose);
      final inventory = emptyInventory();
      final daily = emptyDaily();
      final debt = emptyDebt();
      addTearDown(debt.dispose);
      addTearDown(daily.dispose);
      addTearDown(inventory.dispose);
      await tester.pumpWidget(
        PharmacyApp(
          controller: controller,
          inventory: inventory,
          daily: daily,
          debt: debt,
        ),
      );
      await tester.pumpAndSettle();
      for (final icon in [
        Icons.inventory_2_outlined,
        Icons.bar_chart_outlined,
        Icons.people_outline,
        Icons.home_outlined,
      ]) {
        await tester.tap(find.byIcon(icon).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('storage error has working retry, no false empty success', (
    tester,
  ) async {
    var attempts = 0;
    final controller = AppController(
      clock: FakeClock(),
      load: (date) async {
        if (attempts++ == 0) throw StateError('test storage error');
        return emptySummary(date);
      },
    );
    addTearDown(controller.dispose);
    final inventory = emptyInventory();
    final daily = emptyDaily();
    final debt = emptyDebt();
    addTearDown(debt.dispose);
    addTearDown(daily.dispose);
    addTearDown(inventory.dispose);
    await tester.pumpWidget(
      PharmacyApp(
        controller: controller,
        inventory: inventory,
        daily: daily,
        debt: debt,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to open local data'), findsOneWidget);
    expect(find.text('No items yet'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('A clear view of your pharmacy'), findsOneWidget);
  });
  testWidgets(
    'reusable money field supports Persian digits and explicit loss sign',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final form = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: Form(
              key: form,
              child: MoneyField(
                controller: controller,
                label: 'Profit',
                allowNegative: true,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField), '۱۲٫۳۴');
      await tester.tap(find.text('Switch profit / loss sign'));
      await tester.pump();
      expect(Money.parse(controller.text).minor, -1234);
      expect(form.currentState!.validate(), isTrue);
      await tester.enterText(find.byType(TextFormField), '1.234');
      expect(form.currentState!.validate(), isFalse);
    },
  );
  testWidgets('Persian editable content is RTL while label stays LTR', (
    tester,
  ) async {
    final controller = TextEditingController(text: '۱۲ مریم Amoxicillin');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: AppTextField(controller: controller, label: 'Customer name'),
        ),
      ),
    );
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).textDirection,
      TextDirection.rtl,
    );
    expect(
      tester.widget<Text>(find.text('Customer name')).textDirection,
      TextDirection.ltr,
    );
    expect(contentDirection('123 Amoxicillin مریم'), TextDirection.ltr);
  });
  test(
    'controllable clock refreshes once when local business day changes',
    () async {
      final clock = FakeClock();
      var reads = 0;
      final controller = AppController(
        clock: clock,
        load: (date) async {
          reads++;
          return emptySummary(date);
        },
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.refreshIfDayChanged();
      expect(reads, 1);
      clock.date = BusinessDate(2026, 10, 6);
      await controller.refreshIfDayChanged();
      expect(reads, 2);
      expect(controller.summary!.today.iso, '2026-10-06');
    },
  );
  test('design foreground pairs meet normal text contrast', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
    }

    for (final color in [
      AppColors.text,
      AppColors.secondary,
      AppColors.primary,
      AppColors.success,
      AppColors.warning,
      AppColors.danger,
    ]) {
      expect(contrast(color, Colors.white), greaterThanOrEqualTo(4.5));
    }
  });
}
