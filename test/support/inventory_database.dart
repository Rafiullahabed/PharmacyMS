import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacyms/app/application/app_services.dart';
import 'package:pharmacyms/core/data/app_database.dart';
import 'fake_clock.dart';

/// Real temporary on-disk SQLite, shared by inventory repository and UI tests.
class InventoryDatabase {
  final clock = FakeClock();
  late Directory directory;
  late AppDatabase database;
  late AppServices services;
  String get path => p.join(directory.path, 'inventory.sqlite');
  Future<void> open() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('pharmacy_inventory_');
    await _open();
  }

  Future<void> _open() async {
    database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
      clock: clock,
    );
    services = AppServices(database, clock);
  }

  Future<void> reopen() async {
    await database.close();
    await _open();
  }

  Future<int> count(String table) async =>
      (await database.connection.rawQuery(
            'SELECT count(*) AS n FROM $table',
          )).single['n']
          as int;
  Future<void> close() async {
    await database.close();
    final resolved = p.normalize(directory.absolute.path);
    if (p.isWithin(p.normalize(Directory.systemTemp.absolute.path), resolved) &&
        p.basename(resolved).startsWith('pharmacy_inventory_')) {
      await directory.delete(recursive: true);
    }
  }
}
