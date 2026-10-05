import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app/application/app_controller.dart';
import 'app/application/app_services.dart';
import 'app/presentation/pharmacy_app.dart';
import 'core/data/app_database.dart';
import 'core/domain/dates.dart';
import 'features/inventory/application/inventory_controller.dart';
import 'features/daily_records/application/daily_records_controller.dart';
import 'features/debtors/application/debt_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Vazirmatn',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  const clock = SystemClock();
  AppServices? services;
  Future<AppServices> resolve() async =>
      services ??= AppServices(await AppDatabase.open(clock: clock), clock);
  final inventory = InventoryController(
    clock: clock,
    resolve: () async {
      final s = await resolve();
      return (inventory: s.inventory, settings: s.settings);
    },
  );
  final controller = AppController(
    clock: clock,
    load: (today) async {
      return (await resolve()).home.read(today);
    },
  );
  final daily = DailyRecordsController(
    clock: clock,
    resolve: () async => (await resolve()).dailyRecords,
  );
  runApp(
    PharmacyApp(
      controller: controller,
      inventory: inventory,
      daily: daily,
      debt: DebtController(
        clock: clock,
        resolve: () async => (await resolve()).debtors,
      ),
    ),
  );
}
