import '../../core/data/app_database.dart';
import '../../core/domain/dates.dart';
import '../../features/daily_records/data/sqlite_daily_records_repository.dart';
import '../../features/daily_records/domain/daily_record.dart';
import '../../features/debtors/data/sqlite_debt_repository.dart';
import '../../features/debtors/domain/debt.dart';
import '../../features/home/data/sqlite_home_repository.dart';
import '../../features/home/domain/home_summary.dart';
import '../../features/inventory/data/sqlite_inventory_repository.dart';
import '../../features/inventory/domain/inventory.dart';
import '../../features/settings/data/sqlite_settings_repository.dart';
import '../../features/settings/domain/settings_repository.dart';
import '../../features/backup/data/sqlite_backup_repository.dart';
import '../../features/backup/domain/backup.dart';

/// Composition root. Future adapters belong behind these interfaces.
class AppServices {
  AppServices(this.database, AppClock clock)
    : inventory = SqliteInventoryRepository(database.connection, clock),
      dailyRecords = SqliteDailyRecordsRepository(database.connection, clock),
      debtors = SqliteDebtRepository(database.connection, clock),
      settings = SqliteSettingsRepository(database.connection, clock),
      home = SqliteHomeRepository(database.connection),
      backups = SqliteBackupRepository(database, clock);
  final AppDatabase database;
  final InventoryRepository inventory;
  final DailyRecordsRepository dailyRecords;
  final DebtRepository debtors;
  final SettingsRepository settings;
  final HomeRepository home;
  final BackupRepository backups;
}
