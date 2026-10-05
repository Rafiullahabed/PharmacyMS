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
import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/core/domain/money.dart';
import 'package:pharmacyms/core/presentation/form_fields.dart';
import 'package:pharmacyms/features/daily_records/application/daily_records_controller.dart';
import 'package:pharmacyms/features/debtors/application/debt_controller.dart';
import 'package:pharmacyms/features/debtors/data/sqlite_debt_repository.dart';
import 'package:pharmacyms/features/debtors/domain/debt.dart';
import 'package:pharmacyms/features/debtors/presentation/customer_form.dart';
import 'package:pharmacyms/features/debtors/presentation/ledger_form.dart';
import 'package:pharmacyms/features/inventory/application/inventory_controller.dart';
import 'support/inventory_database.dart';

class _Repository extends SqliteDebtRepository {
  _Repository(super.db, super.clock);
  bool loseAdd = false,
      loseDelete = false,
      loseCustomer = false,
      failSearch = false,
      failPreview = false,
      loseEdit = false;
  Completer<void>? delay;
  int adds = 0;
  @override
  Future<Customer> saveCustomer({
    required String operationId,
    String? id,
    required String name,
    String? phone,
    String? note,
  }) async {
    final value = await super.saveCustomer(
      operationId: operationId,
      id: id,
      name: name,
      phone: phone,
      note: note,
    );
    if (loseCustomer) {
      loseCustomer = false;
      throw StateError('Lost acknowledgment');
    }
    return value;
  }

  @override
  Future<LedgerEntry> addEntry({
    required String operationId,
    required String customerId,
    required BusinessDate date,
    required LedgerKind kind,
    required Money amount,
    String description = '',
  }) async {
    adds++;
    await delay?.future;
    final value = await super.addEntry(
      operationId: operationId,
      customerId: customerId,
      date: date,
      kind: kind,
      amount: amount,
      description: description,
    );
    if (loseAdd) {
      loseAdd = false;
      throw StateError('Lost acknowledgment');
    }
    return value;
  }

  @override
  Future<LedgerEntry> editEntry({
    String? operationId,
    required String id,
    required BusinessDate date,
    required LedgerKind kind,
    required Money amount,
    required String description,
    required String reason,
  }) async {
    final value = await super.editEntry(
      operationId: operationId,
      id: id,
      date: date,
      kind: kind,
      amount: amount,
      description: description,
      reason: reason,
    );
    if (loseEdit) {
      loseEdit = false;
      throw StateError('Lost acknowledgment');
    }
    return value;
  }

  @override
  Future<void> deleteEntry(
    String id, {
    required String reason,
    String? operationId,
  }) async {
    await super.deleteEntry(id, reason: reason, operationId: operationId);
    if (loseDelete) {
      loseDelete = false;
      throw StateError('Lost acknowledgment');
    }
  }

  @override
  Future<CustomerPage> searchCustomers({
    String search = '',
    CustomerFilter filter = CustomerFilter.all,
    bool archived = false,
    int limit = 50,
    int offset = 0,
  }) async {
    if (failSearch) throw StateError('Read failed');
    return super.searchCustomers(
      search: search,
      filter: filter,
      archived: archived,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<LedgerPreview> preview(
    String customerId, {
    String? entryId,
    LedgerDraft? draft,
    bool deleting = false,
  }) async {
    if (failPreview) throw StateError('Read failed');
    return super.preview(
      customerId,
      entryId: entryId,
      draft: draft,
      deleting: deleting,
    );
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
  expect(ready(), isTrue, reason: 'Persisted debt UI state did not appear');
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
  if (tester.widget(target) is ListTile) {
    target = find.descendant(of: target, matching: find.byType(Text)).first;
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
Future<void> enter(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(field(label));
  await tester.enterText(field(label), value);
  await frames(tester);
}

Finder action(String label) => find.widgetWithText(FilledButton, label).last;

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
  late DebtController debt;
  late DailyRecordsController daily;
  late InventoryController inventory;
  late AppController app;
  final shot = GlobalKey();
  setUp(() async {
    f = InventoryDatabase();
    await f.open();
    repo = _Repository(f.database.connection, f.clock);
    debt = DebtController(clock: f.clock, resolve: () async => repo);
    daily = DailyRecordsController(
      clock: f.clock,
      resolve: () async => f.services.dailyRecords,
    );
    inventory = InventoryController(
      clock: f.clock,
      resolve: () async =>
          (inventory: f.services.inventory, settings: f.services.settings),
    );
    app = AppController(clock: f.clock, load: f.services.home.read);
  });
  tearDown(() async {
    debt.dispose();
    daily.dispose();
    inventory.dispose();
    app.dispose();
    await f.close();
  });
  Future<void> open(WidgetTester tester) async {
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
    await until(tester, () => find.text('Record today').evaluate().isNotEmpty);
  }

  Future<void> tab(WidgetTester tester) async {
    await tap(tester, find.byIcon(Icons.people_outline).last);
    await until(
      tester,
      () =>
          find
              .text('Total outstanding · All active customers')
              .evaluate()
              .isNotEmpty ||
          find.text('Unable to open local data').evaluate().isNotEmpty,
    );
  }

  Future<Customer> seedCustomer(
    WidgetTester tester, {
    String name = 'احمد',
    String? phone,
  }) async => (await tester.runAsync(
    () => repo.createCustomer(name: name, phone: phone),
  ))!;
  Future<LedgerEntry> seedEntry(
    WidgetTester tester,
    Customer c,
    String amount, {
    String date = '2026-10-05',
    LedgerKind kind = LedgerKind.debt,
    String description = '',
  }) async => (await tester.runAsync(
    () => repo.addEntry(
      operationId: const Uuid().v4(),
      customerId: c.meta.id,
      date: BusinessDate.parse(date),
      kind: kind,
      amount: Money.parse(amount),
      description: description,
    ),
  ))!;
  Future<void> showCustomer(WidgetTester tester, Customer c) async {
    await tab(tester);
    await tap(tester, find.widgetWithText(ListTile, c.name));
    await until(
      tester,
      () => find.text('Outstanding balance').evaluate().isNotEmpty,
    );
  }

  Future<void> saveEntry(
    WidgetTester tester,
    LedgerKind kind,
    String amount, {
    String description = '',
  }) async {
    await tap(tester, action(kind.action));
    expect(
      tester.widget<TextFormField>(field('Business date')).controller!.text,
      '2026-10-05',
    );
    await enter(
      tester,
      '${kind == LedgerKind.debt ? 'Debt' : 'Payment'} amount (AFN)',
      amount,
    );
    if (description.isNotEmpty) await enter(tester, 'Description', description);
    await until(
      tester,
      () => find
          .textContaining('Outstanding after saving:')
          .evaluate()
          .isNotEmpty,
    );
    await tap(tester, action(kind.action));
    await until(tester, () => find.byType(LedgerForm).evaluate().isEmpty);
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('PHASE5_SCREENSHOTS')) return;
    await frames(tester);
    await tester.runAsync(() async {
      final boundary =
          shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('build/phase5-review');
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'Persian customer without phone, 500+300-200, Home outstanding route, full settlement and archive/restore',
    (tester) async {
      await open(tester);
      await tab(tester);
      expect(find.text('No customers yet'), findsOneWidget);
      await tap(tester, find.text('Add customer'));
      await tap(tester, action('Save customer'));
      expect(find.text('Name is required.'), findsOneWidget);
      await enter(tester, 'Customer name', 'احمد');
      await tap(tester, action('Save customer'));
      await until(
        tester,
        () => find.text('Outstanding balance').evaluate().isNotEmpty,
      );
      expect(
        tester.widget<FilledButton>(action('Record payment')).onPressed,
        isNull,
      );
      await saveEntry(
        tester,
        LedgerKind.debt,
        '۵۰۰',
        description: 'Amoxicillin برای خانواده',
      );
      await saveEntry(tester, LedgerKind.debt, '300');
      await saveEntry(tester, LedgerKind.payment, '٢٠٠');
      expect(find.text('AFN 600.00'), findsOneWidget);
      final c = (await tester.runAsync(
        () => repo.searchCustomers(),
      ))!.items.single.customer;
      expect(c.phone, isNull);
      expect((await tester.runAsync(() => repo.history(c.meta.id)))!.total, 3);
      await tester.pageBack();
      await frames(tester);
      await tap(tester, find.byIcon(Icons.home_outlined));
      await until(tester, () => find.text('AFN 600.00').evaluate().isNotEmpty);
      await tap(tester, find.text('View outstanding customers'));
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Outstanding'))
            .selected,
        isTrue,
      );
      await tap(tester, find.widgetWithText(ListTile, 'احمد'));
      await tap(tester, action('Record payment'));
      expect(
        tester
            .widget<TextFormField>(field('Payment amount (AFN)'))
            .controller!
            .text,
        isEmpty,
      );
      await tap(tester, find.text('Pay full balance'));
      expect(
        tester
            .widget<TextFormField>(field('Payment amount (AFN)'))
            .controller!
            .text,
        '600.00',
      );
      expect(find.text('Outstanding after saving: AFN 0.00'), findsOneWidget);
      await tap(tester, action('Record payment'));
      await until(tester, () => find.byType(LedgerForm).evaluate().isEmpty);
      expect(find.text('Settled'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(action('Record payment')).onPressed,
        isNull,
      );
      await tap(tester, find.byTooltip('Customer actions'));
      await tap(tester, find.text('Archive customer'));
      await tap(tester, find.text('Archive'));
      await until(
        tester,
        () => find.text('Archived · History retained').evaluate().isNotEmpty,
      );
      await tester.pageBack();
      await frames(tester);
      expect(find.text('No matching customers'), findsOneWidget);
      await tap(tester, find.widgetWithText(FilterChip, 'Archived'));
      await tap(tester, find.widgetWithText(ListTile, 'احمد'));
      await tap(tester, find.byTooltip('Customer actions'));
      await tap(tester, find.text('Restore customer'));
      await tap(tester, find.text('Restore'));
      await until(tester, () => find.text('Settled').evaluate().isNotEmpty);
      expect((await tester.runAsync(() => repo.history(c.meta.id)))!.total, 4);
      expect(await tester.runAsync(() => f.count('daily_records')), 0);
      expect(await tester.runAsync(() => f.count('stock_movements')), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'duplicate-name confirmation, customer editing, text phone search and settled filter',
    (tester) async {
      await seedCustomer(tester, name: 'کریم', phone: '07000001');
      await open(tester);
      await tab(tester);
      await tap(tester, find.text('Add customer'));
      await enter(tester, 'Customer name', 'كريم');
      await enter(tester, 'Note (optional)', 'همسایه North');
      await tap(tester, action('Save customer'));
      expect(find.text('Similar customer names'), findsOneWidget);
      expect(find.textContaining('Phone: 07000001'), findsOneWidget);
      await tap(tester, find.text('Cancel'));
      expect(await tester.runAsync(() => f.count('customers')), 1);
      await tap(tester, action('Save customer'));
      await tap(tester, find.text('Continue'));
      await until(
        tester,
        () => find.text('Edit customer').evaluate().isNotEmpty,
      );
      await tap(tester, find.text('Edit customer'));
      await enter(tester, 'Phone (optional)', '۰۰۷۰ ۱۲۳');
      await enter(tester, 'Customer name', 'لیلا');
      await tap(tester, action('Save customer'));
      await until(tester, () => find.byType(CustomerForm).evaluate().isEmpty);
      expect(find.text('۰۰۷۰ ۱۲۳'), findsOneWidget);
      await tester.pageBack();
      await frames(tester);
      final search = find.widgetWithText(TextField, 'Search name or phone');
      await tester.enterText(search, '0070123');
      await frames(tester);
      expect(find.widgetWithText(ListTile, 'لیلا'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'کریم'), findsNothing);
      await tap(tester, find.widgetWithText(FilterChip, 'Outstanding'));
      expect(find.text('No matching customers'), findsOneWidget);
      await tap(tester, find.widgetWithText(FilterChip, 'Settled'));
      expect(find.widgetWithText(ListTile, 'لیلا'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ledger inline validation, past-date conflicts, safe correction, delete confirmation and complete audit',
    (tester) async {
      final c = await seedCustomer(tester);
      final original = await seedEntry(
        tester,
        c,
        '500',
        date: '2026-10-02',
        description: 'Original فارسی',
      );
      await seedEntry(
        tester,
        c,
        '200',
        kind: LedgerKind.payment,
        date: '2026-10-03',
        description: 'Paid',
      );
      await open(tester);
      await showCustomer(tester, c);
      await tap(tester, action('Record payment'));
      await enter(tester, 'Payment amount (AFN)', '0');
      expect(find.text('Enter a positive amount.'), findsWidgets);
      expect(
        tester.widget<FilledButton>(action('Record payment')).onPressed,
        isNull,
      );
      await enter(tester, 'Payment amount (AFN)', '301');
      expect(find.textContaining('negative'), findsOneWidget);
      await enter(tester, 'Payment amount (AFN)', '1');
      await enter(tester, 'Business date', '2026-10-06');
      expect(find.textContaining('Future'), findsWidgets);
      await enter(tester, 'Business date', '2026-10-01');
      expect(find.textContaining('negative'), findsOneWidget);
      await tester.pageBack();
      await frames(tester);
      await tap(tester, find.text('Cancel'));
      expect(
        tester.widget<TextFormField>(field('Business date')).controller!.text,
        '2026-10-01',
      );
      await tester.pageBack();
      await frames(tester);
      await tap(tester, find.text('Discard'));
      await tap(tester, find.widgetWithText(ListTile, 'Original فارسی'));
      await tap(tester, find.byTooltip('Entry actions'));
      await tap(tester, find.text('Delete entry'));
      expect(find.textContaining('negative'), findsOneWidget);
      expect(find.text('Delete ledger entry?'), findsNothing);
      await tap(tester, find.text('Edit entry'));
      await enter(tester, 'Debt amount (AFN)', '100');
      expect(find.textContaining('negative'), findsOneWidget);
      await enter(tester, 'Debt amount (AFN)', '600.01');
      await enter(tester, 'Description', 'تصحیح Amoxicillin\nدو بسته');
      await enter(tester, 'Correction reason (optional)', 'Amount corrected');
      expect(find.text('Outstanding after saving: AFN 400.01'), findsOneWidget);
      await tap(tester, action('Save correction'));
      await until(tester, () => find.byType(LedgerForm).evaluate().isEmpty);
      expect(
        (await tester.runAsync(() => repo.entry(original.meta.id)))!.sequence,
        original.sequence,
      );
      await tester.pageBack();
      await frames(tester);
      await tap(tester, find.widgetWithText(ListTile, 'Paid'));
      await tap(tester, find.byTooltip('Entry actions'));
      await tap(tester, find.text('Delete entry'));
      expect(
        find.textContaining('Outstanding after deletion: AFN 600.01'),
        findsOneWidget,
      );
      await tap(tester, find.text('Cancel'));
      expect(await tester.runAsync(() => f.count('ledger_entries')), 2);
      await tap(tester, find.byTooltip('Entry actions'));
      await tap(tester, find.text('Delete entry'));
      await tap(tester, find.widgetWithText(TextButton, 'Delete entry'));
      await until(tester, () => find.text('AFN 600.01').evaluate().isNotEmpty);
      await tap(tester, find.text('Correction history'));
      expect(find.text('Deleted after confirmation'), findsOneWidget);
      await tap(tester, find.text('Amount corrected'));
      expect(find.text('Original فارسی'), findsOneWidget);
      expect(find.text('تصحیح Amoxicillin\nدو بسته'), findsOneWidget);
      expect(await tester.runAsync(() => f.count('correction_audits')), 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'item suggestions replace selected text at Persian cursor and preserve description and independent amounts',
    (tester) async {
      final c = await seedCustomer(tester);
      await tester.runAsync(() async {
        final unit = (await f.services.settings.units()).first;
        await f.services.inventory.createProduct(
          name: 'Amoxicillin',
          unitId: unit.meta.id,
        );
      });
      await open(tester);
      await showCustomer(tester, c);
      await tap(tester, action('Add debt'));
      await enter(tester, 'Debt amount (AFN)', '12.34');
      await enter(tester, 'Description', 'برای XXX\nدو بسته');
      final text = tester
          .widget<TextFormField>(field('Description'))
          .controller!;
      text.selection = const TextSelection(baseOffset: 5, extentOffset: 8);
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: field('Description'),
                matching: find.byType(TextField),
              ),
            )
            .textDirection,
        TextDirection.rtl,
      );
      await tap(tester, find.text('Insert item name'));
      await tap(tester, find.widgetWithText(ListTile, 'Amoxicillin'));
      expect(text.text, 'برای Amoxicillin\nدو بسته');
      expect(text.selection, const TextSelection.collapsed(offset: 16));
      expect(
        tester
            .widget<TextFormField>(field('Debt amount (AFN)'))
            .controller!
            .text,
        '12.34',
      );
      await tap(tester, action('Add debt'));
      await until(tester, () => find.byType(LedgerForm).evaluate().isEmpty);
      final saved = (await tester.runAsync(
        () => repo.history(c.meta.id),
      ))!.lines.single.entry;
      expect(saved.description, 'برای Amoxicillin\nدو بسته');
      expect(saved.amount.minor, 1234);
      expect(await tester.runAsync(() => f.count('stock_movements')), 0);
      expect(await tester.runAsync(() => f.count('daily_records')), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'duplicate taps and lost acknowledgments reconcile customer, debt, edit and delete without duplicate history',
    (tester) async {
      await open(tester);
      await tab(tester);
      await tap(tester, find.text('Add customer'));
      await enter(tester, 'Customer name', 'Retry customer');
      repo.loseCustomer = true;
      await tap(tester, action('Save customer'));
      expect(find.textContaining('Unable to save'), findsOneWidget);
      expect(await tester.runAsync(() => f.count('customers')), 1);
      await tap(tester, action('Retry same save'));
      await until(
        tester,
        () => find.text('Outstanding balance').evaluate().isNotEmpty,
      );
      await tap(tester, action('Add debt'));
      await enter(tester, 'Debt amount (AFN)', '500');
      repo.delay = Completer<void>();
      repo.loseAdd = true;
      await tester.tap(action('Add debt'));
      await tester.tap(action('Add debt'));
      await frames(tester);
      expect(find.text('Saving…'), findsOneWidget);
      expect(repo.adds, 1);
      repo.delay!.complete();
      await frames(tester);
      expect(find.textContaining('Unable to save'), findsOneWidget);
      expect(await tester.runAsync(() => f.count('ledger_entries')), 1);
      await tap(tester, action('Retry same save'));
      await until(tester, () => find.byType(LedgerForm).evaluate().isEmpty);
      expect(await tester.runAsync(() => f.count('ledger_entries')), 1);
      await tap(
        tester,
        find.widgetWithText(ListTile, 'Debt added\n+ AFN 500.00'),
      );
      await tap(tester, find.text('Edit entry'));
      await enter(tester, 'Debt amount (AFN)', '600');
      repo.loseEdit = true;
      await tap(tester, action('Save correction'));
      await tap(tester, action('Retry same save'));
      await until(tester, () => find.byType(LedgerForm).evaluate().isEmpty);
      expect(await tester.runAsync(() => f.count('correction_audits')), 1);
      repo.loseDelete = true;
      await tap(tester, find.byTooltip('Entry actions'));
      await tap(tester, find.text('Delete entry'));
      await tap(tester, find.widgetWithText(TextButton, 'Delete entry'));
      expect(find.textContaining('Unable to save'), findsOneWidget);
      await tap(tester, find.text('Retry deletion'));
      await until(
        tester,
        () => find.text('No transactions yet').evaluate().isNotEmpty,
      );
      expect(await tester.runAsync(() => f.count('ledger_entries')), 0);
      expect(await tester.runAsync(() => f.count('correction_audits')), 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'read and preview failures retry with preserved input; resume refreshes real customer balance',
    (tester) async {
      final c = await seedCustomer(tester);
      repo.failSearch = true;
      await open(tester);
      await tab(tester);
      expect(find.text('Unable to open local data'), findsOneWidget);
      repo.failSearch = false;
      await tap(tester, find.text('Retry'));
      await tap(tester, find.widgetWithText(ListTile, c.name));
      repo.failPreview = true;
      await tap(tester, action('Add debt'));
      await enter(tester, 'Debt amount (AFN)', '500');
      expect(find.textContaining('Unable to preview'), findsOneWidget);
      repo.failPreview = false;
      await tap(tester, find.text('Retry preview'));
      expect(find.text('Outstanding after saving: AFN 500.00'), findsOneWidget);
      await tap(tester, action('Add debt'));
      await until(tester, () => find.byType(LedgerForm).evaluate().isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await seedEntry(tester, c, '1.01');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await until(tester, () => find.text('AFN 501.01').evaluate().isNotEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320px and 200 percent text support customer and ledger forms, keyboard, suggestions, history and correction review',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final semantics = tester.ensureSemantics();
      try {
        final c = await seedCustomer(tester, name: 'احمد رحیمی');
        await tester.runAsync(() async {
          final unit = (await f.services.settings.units()).first;
          await f.services.inventory.createProduct(
            name: 'Amoxicillin',
            unitId: unit.meta.id,
          );
        });
        await open(tester);
        await showCustomer(tester, c);
        await screenshot(tester, 'narrow-customer');
        await tap(tester, find.text('Edit customer'));
        tester.view.viewInsets = const FakeViewPadding(bottom: 180);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump();
        await enter(tester, 'Phone (optional)', '0700123456');
        expect(
          tester.getRect(find.text('Save customer')).bottom,
          lessThan(388),
        );
        await screenshot(tester, 'narrow-customer-form');
        tester.view.resetViewInsets();
        await tester.pump();
        await tap(tester, action('Save customer'));
        await until(tester, () => find.byType(CustomerForm).evaluate().isEmpty);
        await tap(tester, action('Add debt'));
        tester.view.viewInsets = const FakeViewPadding(bottom: 180);
        await tester.pump();
        await enter(tester, 'Debt amount (AFN)', '500');
        await enter(tester, 'Description', 'برای خانواده\nدو بسته Amoxicillin');
        expect(tester.getRect(action('Add debt')).bottom, lessThan(388));
        await screenshot(tester, 'narrow-ledger-form');
        await tap(tester, find.text('Insert item name'));
        await screenshot(tester, 'narrow-suggestions');
        await tap(tester, find.widgetWithText(ListTile, 'Amoxicillin'));
        tester.view.resetViewInsets();
        await tester.pump();
        await tap(tester, action('Add debt'));
        await until(tester, () => find.byType(LedgerForm).evaluate().isEmpty);
        await tap(
          tester,
          find.widgetWithText(ListTile, 'Debt added\n+ AFN 500.00'),
        );
        await screenshot(tester, 'narrow-entry');
        await tap(tester, find.byTooltip('Entry actions'));
        await tap(tester, find.text('Delete entry'));
        await screenshot(tester, 'narrow-delete');
        await tap(tester, find.text('Cancel'));
        expect(find.byTooltip('Entry actions'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
