import '../../../core/domain/dates.dart';
import '../../daily_records/domain/daily_record.dart';
import '../../inventory/domain/inventory.dart';

final class HomeSummary {
  const HomeSummary({
    required this.today,
    required this.products,
    required this.batches,
    required this.dailyRecords,
    required this.customers,
    required this.outstanding,
    required this.units,
    this.todayRecord,
  });
  final BusinessDate today;
  final int products, batches, dailyRecords, customers;
  final BigInt outstanding;
  final DailyRecord? todayRecord;
  final List<StockUnit> units;
}

abstract interface class HomeRepository {
  Future<HomeSummary> read(BusinessDate today);
}
