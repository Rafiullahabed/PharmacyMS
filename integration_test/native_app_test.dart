import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:pharmacyms/app/application/app_controller.dart';
import 'package:pharmacyms/app/application/app_services.dart';
import 'package:pharmacyms/app/presentation/pharmacy_app.dart';
import 'package:pharmacyms/core/data/app_database.dart';
import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/core/domain/money.dart';
import 'package:pharmacyms/core/domain/validation.dart';
import 'package:pharmacyms/core/presentation/form_fields.dart';
import 'package:pharmacyms/features/backup/data/backup_integrity.dart';
import 'package:pharmacyms/features/backup/domain/backup.dart';
import 'package:pharmacyms/features/daily_records/application/daily_records_controller.dart';
import 'package:pharmacyms/features/daily_records/domain/daily_report.dart';
import 'package:pharmacyms/features/debtors/application/debt_controller.dart';
import 'package:pharmacyms/features/debtors/domain/debt.dart';
import 'package:pharmacyms/features/inventory/application/inventory_controller.dart';
import 'package:pharmacyms/features/inventory/domain/inventory.dart';
import '../test/support/fake_clock.dart';

// Uses the real sqflite mobile plugin in a unique private directory. Running this
// test never opens, resets, or restores the user's pharmacy_companion.sqlite.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDatabase database;
  late AppServices services;
  final clock = FakeClock(date: BusinessDate(2026, 10, 6));
  String id() => const Uuid().v4();
  Future<void> reopen() async {
    await database.close();
    database = await AppDatabase.open(
      path: p.join(directory.path, 'acceptance.sqlite'),
      clock: clock,
    );
    services = AppServices(database, clock);
  }

  setUp(() async {
    final parent = Directory(await getDatabasesPath());
    await parent.create(recursive: true);
    directory = await parent.createTemp('phase8_acceptance_');
    database = await AppDatabase.open(
      path: p.join(directory.path, 'acceptance.sqlite'),
      clock: clock,
    );
    services = AppServices(database, clock);
  });
  tearDown(() async {
    await database.close();
    final root = p.normalize(await getDatabasesPath());
    if (p.isWithin(root, p.normalize(directory.path)) &&
        p.basename(directory.path).startsWith('phase8_acceptance_')) {
      await directory.delete(recursive: true);
    }
  });

  testWidgets(
    'native SQLite: owner acceptance, atomic failure, portable restore and reopen',
    (tester) async {
      final unit = await services.settings.saveUnit(name: 'Counting strip');
      final product = await services.inventory.saveProduct(
        operationId: id(),
        draft: ProductDraft(
          name: 'Amoxicillin · اموکسی سیلین',
          unitId: unit.meta.id,
          minimumStock: 10,
          warningDays: 45,
        ),
        initialStock: BatchDraft(
          receivedDate: clock.today(),
          quantity: 8,
          label: 'A',
          expiry: DateSpec(
            calendar: DateCalendar.gregorian,
            year: 2026,
            month: 11,
            day: 20,
          ),
        ),
      );
      final first = (await services.inventory.batches(product.meta.id)).single;
      final second = await services.inventory.createBatch(
        productId: product.meta.id,
        label: 'B',
        receivedDate: clock.today(),
        openingQuantity: 12,
        expiry: DateSpec(
          calendar: DateCalendar.solarHijri,
          year: 1405,
          month: 8,
        ),
      );
      final operation = id();
      await Future.wait([
        services.inventory.adjust(
          operationId: operation,
          batchId: second.meta.id,
          delta: -3,
        ),
        services.inventory.adjust(
          operationId: operation,
          batchId: second.meta.id,
          delta: -3,
        ),
      ]);
      expect((await services.inventory.batch(first.meta.id)).quantity, 8);
      expect((await services.inventory.batch(second.meta.id)).quantity, 9);
      await expectLater(
        services.inventory.adjust(
          operationId: id(),
          batchId: second.meta.id,
          delta: -10,
        ),
        throwsA(isA<ValidationException>()),
      );
      await services.inventory.reverse(
        operationId: id(),
        movementId: operation,
      );
      expect((await services.inventory.batch(second.meta.id)).quantity, 12);
      expect(
        (await services.inventory.overview(clock.today())).expiringBatches,
        1,
      );
      await services.settings.saveUnit(
        id: unit.meta.id,
        name: 'Strip renamed',
        inactive: true,
      );
      expect(
        (await services.inventory.product(product.meta.id)).unitId,
        unit.meta.id,
      );
      await expectLater(
        services.settings.deleteUnusedUnit(unit.meta.id),
        throwsA(isA<DatabaseException>()),
      );
      await services.settings.saveUnit(id: unit.meta.id, name: 'Strip renamed');

      // Failure after batch/product writes must roll back the entire initial save.
      await database.connection.execute(
        "CREATE TRIGGER injected_failure BEFORE INSERT ON inventory_operations WHEN NEW.kind='save_product' BEGIN SELECT RAISE(ABORT,'simulated interrupted write'); END",
      );
      await expectLater(
        services.inventory.saveProduct(
          operationId: id(),
          draft: ProductDraft(name: 'Must roll back', unitId: unit.meta.id),
          initialStock: BatchDraft(receivedDate: clock.today(), quantity: 2),
        ),
        throwsA(isA<DatabaseException>()),
      );
      await database.connection.execute('DROP TRIGGER injected_failure');
      expect(
        (await services.inventory.inventory(today: clock.today())).total,
        1,
      );

      final daily = await services.dailyRecords.save(
        operationId: id(),
        date: clock.today(),
        sales: Money.parse('۵۰٬۰۰۰'),
        profit: Money.parse('-۱۰۰۰.۲۵'),
      );
      final customer = await services.debtors.createCustomer(
        name: 'احمد محمدی',
      );
      for (final amount in ['500', '300']) {
        await services.debtors.addEntry(
          operationId: id(),
          customerId: customer.meta.id,
          date: clock.today(),
          kind: LedgerKind.debt,
          amount: Money.parse(amount),
          description: 'دو بسته Amoxicillin\nبرای خانواده',
        );
      }
      final payment = await services.debtors.addEntry(
        operationId: id(),
        customerId: customer.meta.id,
        date: clock.today(),
        kind: LedgerKind.payment,
        amount: Money.parse('200'),
        description: 'پرداخت نقدی',
      );
      expect((await services.debtors.balance(customer.meta.id)).minor, 60000);
      await services.debtors.editEntry(
        operationId: id(),
        id: payment.meta.id,
        date: payment.date,
        kind: payment.kind,
        amount: payment.amount,
        description: 'پرداخت نقدی · Cash',
        reason: 'Clarified description',
      );
      await expectLater(
        services.debtors.editEntry(
          operationId: id(),
          id: payment.meta.id,
          date: shiftDay(clock.today(), -1),
          kind: payment.kind,
          amount: payment.amount,
          description: payment.description,
          reason: 'Invalid backdate',
        ),
        throwsA(isA<ValidationException>()),
      );
      expect((await services.debtors.corrections(customer.meta.id)).length, 1);
      expect(
        (await services.dailyRecords.byId(daily.meta.id))!.profit.minor,
        -100025,
      );
      expect((await services.inventory.batch(second.meta.id)).quantity, 12);
      await services.settings.setPreference('appearance.display_size', 'small');
      final backup = await services.backups.prepare();
      final bytes = await File(backup.path).readAsBytes();
      final corrupt = bytes.sublist(0, bytes.length - 5);
      await expectLater(
        services.backups.validate(corrupt, 'truncated.zip'),
        throwsA(isA<BackupException>()),
      );
      await services.inventory.adjust(
        operationId: id(),
        batchId: first.meta.id,
        delta: -1,
      );
      for (var i = 0; i < 2; i++) {
        await services.backups.restore(
          await services.backups.validate(bytes, 'portable.zip'),
        );
      }
      await reopen();
      expect((await services.inventory.batches(product.meta.id)).length, 2);
      expect((await services.inventory.batch(first.meta.id)).quantity, 8);
      expect(
        (await services.inventory.batch(second.meta.id)).expiry!.toMap(),
        second.expiry!.toMap(),
      );
      expect((await services.debtors.customer(customer.meta.id)).phone, isNull);
      expect((await services.debtors.balance(customer.meta.id)).minor, 60000);
      expect(
        (await services.debtors.entry(payment.meta.id))!.description,
        'پرداخت نقدی · Cash',
      );
      expect(
        (await services.settings.preference('appearance.display_size'))!.value,
        'small',
      );
      expect((await services.dailyRecords.records()).length, 1);
      expect((await services.inventory.movements(second.meta.id)).length, 3);
      await validateBackupDatabase(database.connection);
    },
  );

  testWidgets(
    'native Flutter forms: daily record, Persian customer, payment and tab state',
    (tester) async {
      final inventory = InventoryController(
        clock: clock,
        resolve: () async =>
            (inventory: services.inventory, settings: services.settings),
      );
      final daily = DailyRecordsController(
        clock: clock,
        resolve: () async => services.dailyRecords,
      );
      final debt = DebtController(
        clock: clock,
        resolve: () async => services.debtors,
      );
      final app = AppController(
        clock: clock,
        load: (today) => services.home.read(today),
      );
      addTearDown(() {
        inventory.dispose();
        daily.dispose();
        debt.dispose();
        app.dispose();
      });
      Future<void> settle() async {
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 30),
        );
      }

      Future<void> ready(bool Function() predicate) async {
        for (var i = 0; i < 200 && !predicate(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          predicate(),
          isTrue,
          reason: 'Native persisted UI did not become ready',
        );
      }

      Future<void> tap(Finder target) async {
        await ready(() => target.evaluate().isNotEmpty);
        await tester.ensureVisible(target);
        await settle();
        final button = find.ancestor(
          of: target,
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        );
        await ready(() {
          final widget = target.evaluate().single.widget;
          if (widget is ButtonStyleButton) return widget.onPressed != null;
          if (button.evaluate().isNotEmpty) {
            return tester.widget<ButtonStyleButton>(button.first).onPressed !=
                null;
          }
          return true;
        });
        await tester.tap(target);
        await settle();
      }

      Future<void> enter(String label, String value) async {
        final field = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is AppTextField && w.label == label,
          ),
          matching: find.byType(TextFormField),
        );
        await tester.ensureVisible(field);
        await settle();
        await tester.enterText(field, value);
        await settle();
      }

      await tester.pumpWidget(
        PharmacyApp(
          controller: app,
          inventory: inventory,
          daily: daily,
          debt: debt,
        ),
      );
      await settle();
      expect(find.text('Not recorded'), findsOneWidget);
      await tap(find.text('Record today'));
      await enter('Sales (AFN)', '50000.50');
      await enter('Profit (AFN)', '1000');
      await tap(find.text('Save record'));
      expect(
        (await services.dailyRecords.onDate(clock.today()))!.sales.minor,
        5000050,
      );
      await tap(find.byIcon(Icons.people_outline).last);
      await tap(find.text('Add customer'));
      await enter('Customer name', 'مریم احمدی');
      await tap(find.text('Save customer'));
      await tap(find.widgetWithText(FilledButton, 'Add debt'));
      await enter('Debt amount (AFN)', '500');
      await enter('Description', 'دو بسته Amoxicillin\nیادداشت فارسی');
      await tap(find.widgetWithText(FilledButton, 'Add debt'));
      await tap(find.text('Record payment'));
      await enter('Payment amount (AFN)', '200');
      await tap(find.widgetWithText(FilledButton, 'Record payment'));
      final customer = (await services.debtors.customers()).single;
      expect((await services.debtors.balance(customer.meta.id)).minor, 30000);
      expect((await services.inventory.products()).isEmpty, isTrue);
      expect((await services.dailyRecords.records()).length, 1);
      await ready(
        () =>
            find.widgetWithText(FilledButton, 'Add debt').evaluate().isNotEmpty,
      );
      await settle();
      await tester.pageBack();
      await settle();
      await ready(() => find.byType(TextField).evaluate().isNotEmpty);
      await tester.ensureVisible(find.byType(TextField));
      await settle();
      await tester.enterText(find.byType(TextField), 'مریم');
      await tester.pump(const Duration(milliseconds: 350));
      await settle();
      await tap(find.byIcon(Icons.home_outlined).last);
      await tap(find.byIcon(Icons.people_outline).last);
      expect(find.text('مریم'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
