import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/core/domain/validation.dart';
import 'package:pharmacyms/features/backup/data/backup_integrity.dart';
import 'package:pharmacyms/features/daily_records/domain/daily_report.dart';
import 'package:pharmacyms/features/debtors/domain/debt.dart';
import 'package:pharmacyms/core/domain/money.dart';
import 'package:pharmacyms/features/inventory/domain/inventory.dart';
import 'support/inventory_database.dart';

// All data belongs to a disposable host database. Never imported by lib/.
String fixtureId(int n) =>
    '80000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

void main() {
  test(
    '5000 products, 20000 batches, 50000 history rows stay usable and portable',
    () async {
      final f = InventoryDatabase();
      await f.open();
      addTearDown(f.close);
      f.clock.date = BusinessDate(2026, 10, 6);
      final metrics = <String, Object?>{};
      Future<T> measure<T>(String name, Future<T> Function() run) async {
        final watch = Stopwatch()..start();
        final result = await run();
        metrics[name] = watch.elapsedMilliseconds;
        return result;
      }

      final unit = (await f.services.settings.units()).first.meta.id;
      final now = f.clock.nowUtc().millisecondsSinceEpoch;
      Map<String, Object?> meta(int id) => {
        'id': fixtureId(id),
        'created_at': now,
        'updated_at': now,
      };
      await measure(
        'seed_ms',
        () => f.database.connection.transaction((tx) async {
          final insert = tx.batch();
          for (var i = 0; i < 5000; i++) {
            final name = i.isEven
                ? 'کریم ${i.toString().padLeft(4, '0')}'
                : 'Medicine ${i.toString().padLeft(4, '0')}';
            insert.insert('products', {
              ...meta(i + 1),
              'name': name,
              'name_key': searchKey(name),
              'unit_id': unit,
              'minimum_stock': 28,
              'warning_days': 30,
              'archived': 0,
            });
            for (var j = 0; j < 4; j++) {
              final index = i * 4 + j;
              final expiry = switch (j) {
                0 => DateSpec(
                  calendar: DateCalendar.gregorian,
                  year: 2026,
                  month: 10,
                  day: 5,
                ),
                1 => DateSpec(
                  calendar: DateCalendar.gregorian,
                  year: 2026,
                  month: 10,
                  day: 6,
                ),
                2 => DateSpec(
                  calendar: DateCalendar.solarHijri,
                  year: 1405,
                  month: 7,
                ),
                _ => null,
              };
              if (expiry != null) {
                insert.insert('date_specs', {
                  'id': fixtureId(30000 + index),
                  ...expiry.toMap(),
                  'canonical_start': expiry.range.start.iso,
                  'canonical_end': expiry.range.end.iso,
                });
              }
              insert.insert('batches', {
                ...meta(10000 + index),
                'product_id': fixtureId(i + 1),
                'label': 'Delivery ${j + 1}',
                'received_date': '2026-09-01',
                'quantity': 0,
                'expiry_mode': expiry?.precision.name ?? 'none',
                'expiry_spec_id': expiry == null
                    ? null
                    : fixtureId(30000 + index),
                'archived': 0,
              });
              insert.insert('stock_movements', {
                ...meta(60000 + index * 2),
                'sequence': index * 2 + 1,
                'batch_id': fixtureId(10000 + index),
                'kind': 'opening',
                'delta': 10,
                'resulting_quantity': 10,
              });
              insert.insert('stock_movements', {
                ...meta(60001 + index * 2),
                'sequence': index * 2 + 2,
                'batch_id': fixtureId(10000 + index),
                'kind': 'remove',
                'delta': -1,
                'resulting_quantity': 9,
                'note': 'Manual removal · برداشتن',
              });
            }
          }
          for (var i = 0; i < 1000; i++) {
            final name = 'مشتری ${i.toString().padLeft(4, '0')}';
            insert.insert('customers', {
              ...meta(110000 + i),
              'name': name,
              'name_key': searchKey(name),
              'phone_key': '',
              'archived': 0,
            });
            for (var j = 0; j < 10; j++) {
              insert.insert('ledger_entries', {
                ...meta(120000 + i * 10 + j),
                'customer_id': fixtureId(110000 + i),
                'business_date': '2026-10-06',
                'sequence': i * 10 + j + 1,
                'kind': j.isEven ? 'debt' : 'payment',
                'amount_minor': j.isEven ? 50000 : 20000,
                'description': 'Amoxicillin · پرداخت و جنس',
              });
            }
          }
          for (var i = 0; i < 1825; i++) {
            insert.insert('daily_records', {
              ...meta(140000 + i),
              'business_date': shiftDay(f.clock.today(), -i).iso,
              'sales_minor': 5000000,
              'profit_minor': i.isEven ? 100000 : -10000,
            });
          }
          insert.update(
            'sequence_counters',
            {'value': 40000},
            where: 'name=?',
            whereArgs: ['stock_movements'],
          );
          insert.update(
            'sequence_counters',
            {'value': 10000},
            where: 'name=?',
            whereArgs: ['ledger_entries'],
          );
          await insert.commit(noResult: true);
        }),
      );
      await measure('cold_reopen_ms', f.reopen);
      final inventory = f.services.inventory, debt = f.services.debtors;
      final page = await measure(
        'inventory_page_ms',
        () => inventory.inventory(today: f.clock.today()),
      );
      expect(page.total, 5000);
      expect(page.items.length, 50);
      expect(
        page.items.every(
          (i) => i.physical == 36 && i.usable == 27 && i.lowStock,
        ),
        isTrue,
      );
      final search = await measure(
        'persian_search_ms',
        () => inventory.inventory(today: f.clock.today(), search: 'كريم 0020'),
      );
      expect(search.total, 1);
      final dashboard = await measure(
        'inventory_dashboard_ms',
        () => inventory.dashboard(f.clock.today()),
      );
      expect(dashboard.overview.batches, 20000);
      expect(dashboard.overview.expiredBatches, 5000);
      expect(dashboard.overview.expiringBatches, 10000);
      final expiryPage = await measure(
        'expiry_page_ms',
        () => inventory.alertPage(
          today: f.clock.today(),
          filter: InventoryFilter.expired,
        ),
      );
      expect(expiryPage.totalBatches, 5000);
      final history = await measure(
        'stock_history_page_ms',
        () => inventory.productMovements(fixtureId(1)),
      );
      expect(history.length, 8);
      final customers = await measure(
        'customer_page_ms',
        () => debt.searchCustomers(),
      );
      expect(customers.total, 1000);
      final home = await measure(
        'home_ms',
        () => f.services.home.read(f.clock.today()),
      );
      expect(home.outstanding, BigInt.from(150000000));
      await measure(
        'stock_adjustment_ms',
        () => inventory.adjust(
          operationId: fixtureId(200001),
          batchId: fixtureId(10000),
          delta: -1,
        ),
      );
      final entry = await measure(
        'ledger_adjustment_ms',
        () => debt.addEntry(
          operationId: fixtureId(200002),
          customerId: fixtureId(110000),
          date: f.clock.today(),
          kind: LedgerKind.payment,
          amount: Money.parse('1'),
        ),
      );
      expect(entry.amount.minor, 100);
      final report = await measure(
        'five_year_report_ms',
        () => f.services.dailyRecords.report(
          ReportRange(shiftDay(f.clock.today(), -1824), f.clock.today()),
        ),
      );
      expect(report.totals.recorded, 1825);
      expect(report.totals.sales, BigInt.from(1825) * BigInt.from(5000000));
      await measure(
        'integrity_ms',
        () => validateBackupDatabase(f.database.connection),
      );
      final backup = await measure(
        'backup_ms',
        () => f.services.backups.prepare(),
      );
      final bytes = await File(backup.path).readAsBytes();
      metrics['backup_bytes'] = bytes.length;
      if (const bool.fromEnvironment('PHASE8_LARGE_FIXTURE')) {
        await Directory('build').create(recursive: true);
        await File('build/phase8-large-fixture.zip').writeAsBytes(bytes);
      }
      final preview = await measure(
        'validate_import_ms',
        () => f.services.backups.validate(bytes, 'large.zip'),
      );
      await measure('restore_ms', () => f.services.backups.restore(preview));
      await f.reopen();
      expect(await f.count('products'), 5000);
      expect(await f.count('batches'), 20000);
      expect(await f.count('stock_movements'), 40001);
      expect(await f.count('ledger_entries'), 10001);
      expect((await f.services.inventory.batch(fixtureId(10000))).quantity, 8);
      expect(
        (await f.services.debtors.balance(fixtureId(110000))).minor,
        149900,
      );
      metrics['dataset'] = {
        'products': 5000,
        'batches': 20000,
        'stock_movements': 40001,
        'ledger_entries': 10001,
        'customers': 1000,
        'daily_records': 1825,
      };
      metrics['scope'] =
          'Windows host SQLite FFI timings; not native device frame-time certification';
      await Directory('build').create(recursive: true);
      await File(
        'build/phase8-performance.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(metrics));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
