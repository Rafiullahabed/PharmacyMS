import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pharmacyms/app/application/app_controller.dart';
import 'package:pharmacyms/app/application/app_services.dart';
import 'package:pharmacyms/app/presentation/pharmacy_app.dart';
import 'package:pharmacyms/core/domain/money.dart';
import 'package:pharmacyms/features/backup/application/backup_controller.dart';
import 'package:pharmacyms/features/backup/application/backup_files.dart';
import 'package:pharmacyms/features/backup/data/sqlite_backup_repository.dart';
import 'package:pharmacyms/features/backup/domain/backup.dart';
import 'package:pharmacyms/features/backup/presentation/backup_screen.dart';
import 'package:pharmacyms/features/daily_records/application/daily_records_controller.dart';
import 'package:pharmacyms/features/debtors/application/debt_controller.dart';
import 'package:pharmacyms/features/debtors/domain/debt.dart';
import 'package:pharmacyms/features/inventory/application/inventory_controller.dart';
import 'support/inventory_database.dart';

class _Files implements BackupFiles {
  SelectedBackup? selection;
  ExportOutcome outcome = ExportOutcome.cancelled;
  int saves = 0, shares = 0;
  bool failSave = false;
  Rect? origin;
  @override
  Future<SelectedBackup?> pick() async => selection;
  @override
  Future<ExportOutcome> save(PreparedBackup backup) async {
    saves++;
    expect(await File(backup.path).exists(), isTrue);
    if (failSave) throw const FileSystemException('No space');
    return outcome;
  }

  @override
  Future<ExportOutcome> share(PreparedBackup backup, Rect origin) async {
    shares++;
    this.origin = origin;
    return outcome;
  }
}

Future<void> frames(WidgetTester tester, {int count = 8}) async {
  for (var i = 0; i < count; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 70));
  }
}

Future<void> until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await frames(tester, count: 1);
  }
  expect(ready(), isTrue);
  await frames(tester);
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      300,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 40,
    );
  }
  await tester.ensureVisible(target);
  await tester.pump();
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await reveal(tester, target);
  await tester.tap(target);
  await frames(tester);
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
  late AppServices services;
  late _Files files;
  late SqliteBackupRepository repo;
  late BackupController backup;
  late InventoryController inventory;
  late DailyRecordsController daily;
  late DebtController debt;
  late AppController app;
  Future<void> Function(String)? hook;
  final shot = GlobalKey();
  setUp(() async {
    f = InventoryDatabase();
    await f.open();
    services = f.services;
    files = _Files();
    hook = null;
    repo = SqliteBackupRepository(
      f.database,
      f.clock,
      failureHook: (stage) async {
        await hook?.call(stage);
      },
    );
    inventory = InventoryController(
      clock: f.clock,
      resolve: () async =>
          (inventory: services.inventory, settings: services.settings),
    );
    daily = DailyRecordsController(
      clock: f.clock,
      resolve: () async => services.dailyRecords,
    );
    debt = DebtController(
      clock: f.clock,
      resolve: () async => services.debtors,
    );
    app = AppController(
      clock: f.clock,
      load: (date) => services.home.read(date),
    );
    backup = BackupController(
      resolve: () async => repo,
      files: files,
      onRestored: () async {
        services = AppServices(f.database, f.clock);
        inventory.resetRepositories();
        daily.resetRepositories();
        debt.resetRepositories();
        app.summary = null;
        app.selectTab(0);
        await app.refresh();
      },
    );
  });
  tearDown(() async {
    backup.dispose();
    inventory.dispose();
    daily.dispose();
    debt.dispose();
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
          backups: backup,
        ),
      ),
    );
    await until(tester, () => find.byTooltip('Settings').evaluate().isNotEmpty);
    await tap(tester, find.byTooltip('Settings'));
    await tap(tester, find.text('Portable backup and restore'));
    await until(tester, () => !backup.loadingStatus);
  }

  Future<void> prepareSelection(WidgetTester tester) async {
    await tester.runAsync(() async {
      final c = await services.debtors.createCustomer(
        name: 'احمد',
        phone: '00700',
      );
      await services.debtors.addEntry(
        operationId: const Uuid().v4(),
        customerId: c.meta.id,
        date: f.clock.today(),
        kind: LedgerKind.debt,
        amount: Money.parse('600'),
        description: 'Amoxicillin برای خانواده',
      );
      await services.dailyRecords.save(
        date: f.clock.today(),
        sales: Money.parse('50'),
        profit: Money.parse('-1'),
      );
      final prepared = await repo.prepare();
      files.selection = SelectedBackup(
        'phone-backup.zip',
        await File(prepared.path).readAsBytes(),
      );
      await services.debtors.createCustomer(name: 'Replace me');
      await services.dailyRecords.save(
        id: (await services.dailyRecords.onDate(f.clock.today()))!.meta.id,
        date: f.clock.today(),
        sales: Money.parse('99'),
        profit: Money.parse('10'),
      );
    });
  }

  Future<void> select(WidgetTester tester) async {
    await tap(tester, find.text('Restore backup'));
    await until(tester, () => !backup.busy);
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('PHASE6_SCREENSHOTS')) return;
    await frames(tester);
    await tester.runAsync(() async {
      final boundary =
          shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(),
          bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/phase6-review').create(recursive: true);
      await File(
        'build/phase6-review/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'duplicate create taps, neutral cancellation, saved and unconfirmed share statuses remain honest',
    (tester) async {
      await open(tester);
      expect(find.text('No backup has been prepared yet.'), findsOneWidget);
      await tester.tap(find.text('Create backup'));
      await tester.tap(find.text('Create backup'));
      await until(tester, () => !backup.busy && backup.prepared != null);
      expect(files.saves, 1);
      expect(backup.last!.outcome, ExportOutcome.cancelled);
      expect(
        find.text('File saved to your selected destination.'),
        findsNothing,
      );
      final created = backup.last!.createdUtc;
      files.outcome = ExportOutcome.unconfirmed;
      await tap(tester, find.text('Share prepared file'));
      await until(tester, () => !backup.busy);
      expect(backup.last!.outcome, ExportOutcome.unconfirmed);
      expect(files.origin!.width, greaterThan(0));
      files.outcome = ExportOutcome.shared;
      await tap(tester, find.text('Share prepared file'));
      await until(tester, () => !backup.busy);
      expect(
        find.textContaining('external saving is not confirmed.'),
        findsWidgets,
      );
      files.outcome = ExportOutcome.saved;
      await tap(tester, find.text('Save prepared file'));
      await until(tester, () => !backup.busy);
      expect(backup.last!.outcome, ExportOutcome.saved);
      expect(backup.last!.createdUtc, created);
      expect(
        (await tester.runAsync(() => repo.status()))!.outcome,
        ExportOutcome.saved,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'failed save keeps prepared file for retry without false external-save success',
    (tester) async {
      await open(tester);
      files.failSave = true;
      await tap(tester, find.text('Create backup'));
      await until(tester, () => !backup.busy && backup.prepared != null);
      expect(backup.last!.outcome, ExportOutcome.failed);
      expect(find.textContaining('delivery failed'), findsWidgets);
      files.failSave = false;
      files.outcome = ExportOutcome.saved;
      await tap(tester, find.text('Save prepared file'));
      await until(tester, () => !backup.busy);
      expect(backup.last!.outcome, ExportOutcome.saved);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'picker cancel and corrupt file keep live data and do not expose replacement confirmation',
    (tester) async {
      await open(tester);
      await select(tester);
      expect(
        find.text('File selection cancelled. Current data is unchanged.'),
        findsOneWidget,
      );
      expect(find.text('Replace with this backup'), findsNothing);
      files.selection = SelectedBackup(
        'bad.zip',
        Uint8List.fromList([1, 2, 3]),
      );
      await select(tester);
      expect(backup.error, contains('supported backup ZIP'));
      expect(find.text('Replace with this backup'), findsNothing);
      expect(await tester.runAsync(() => f.count('units')), 6);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'preview and Cancel precede replacement; restore refreshes Home and repository views',
    (tester) async {
      await prepareSelection(tester);
      await open(tester);
      await select(tester);
      expect(find.text('Restore preview'), findsOneWidget);
      await reveal(tester, find.text('Customers: 1'));
      expect(find.text('Customers: 1'), findsOneWidget);
      expect(await tester.runAsync(() => f.count('customers')), 2);
      await tap(tester, find.text('Replace with this backup'));
      expect(find.text('Replace current data?'), findsOneWidget);
      await tap(tester, find.text('Cancel'));
      expect(await tester.runAsync(() => f.count('customers')), 2);
      await tap(tester, find.text('Replace with this backup'));
      await tap(tester, find.widgetWithText(TextButton, 'Restore backup'));
      await until(
        tester,
        () =>
            find.byType(BackupScreen).evaluate().isEmpty &&
            find.text('AFN 50.00').evaluate().isNotEmpty,
      );
      expect(find.text('AFN -1.00'), findsOneWidget);
      expect(find.text('AFN 600.00'), findsOneWidget);
      expect(await tester.runAsync(() => f.count('customers')), 1);
      await tap(tester, find.byIcon(Icons.people_outline).last);
      await until(
        tester,
        () => find.widgetWithText(ListTile, 'احمد').evaluate().isNotEmpty,
      );
      expect(find.text('Replace me'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'restore saving prevents Back and double confirmation; injected failure retains data and allows retry',
    (tester) async {
      await prepareSelection(tester);
      await open(tester);
      await select(tester);
      final delay = Completer<void>();
      hook = (stage) async {
        if (stage == 'after_replace') {
          await delay.future;
          throw const FileSystemException('Injected full device');
        }
      };
      await tap(tester, find.text('Replace with this backup'));
      await tap(tester, find.widgetWithText(TextButton, 'Restore backup'));
      await until(tester, () => backup.stage == 'Replacing local data…');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Replace with this backup'),
            )
            .onPressed,
        isNull,
      );
      await tester.pageBack();
      await frames(tester);
      expect(find.byType(BackupScreen), findsOneWidget);
      delay.complete();
      await until(tester, () => !backup.busy);
      expect(backup.error, contains('previous data was retained'));
      expect(await tester.runAsync(() => f.count('customers')), 2);
      hook = null;
      await tap(tester, find.text('Replace with this backup'));
      await tap(tester, find.widgetWithText(TextButton, 'Restore backup'));
      await until(tester, () => find.byType(BackupScreen).evaluate().isEmpty);
      expect(await tester.runAsync(() => f.count('customers')), 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'cancel restore discards staging and leaves current records intact',
    (tester) async {
      await prepareSelection(tester);
      await open(tester);
      await select(tester);
      await tap(tester, find.text('Cancel restore'));
      await until(tester, () => !backup.busy);
      expect(backup.preview, isNull);
      expect(
        find.text('Restore cancelled. Current data is unchanged.'),
        findsOneWidget,
      );
      expect(await tester.runAsync(() => f.count('customers')), 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    '320px and 200 percent text keep status, preview, confirmation and errors usable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final semantics = tester.ensureSemantics();
      try {
        await prepareSelection(tester);
        await open(tester);
        await screenshot(tester, 'narrow-backup');
        await select(tester);
        await reveal(tester, find.text('Restore preview'));
        await frames(tester);
        await screenshot(tester, 'narrow-preview');
        await tap(tester, find.text('Replace with this backup'));
        await screenshot(tester, 'narrow-confirmation');
        await tap(tester, find.text('Cancel'));
        await tap(tester, find.text('Cancel restore'));
        files.selection = SelectedBackup(
          'corrupt.zip',
          Uint8List.fromList([0]),
        );
        await select(tester);
        await reveal(tester, find.text(backup.error!));
        await frames(tester);
        await screenshot(tester, 'narrow-error');
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
