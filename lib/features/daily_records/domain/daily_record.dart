import '../../../core/domain/dates.dart';
import '../../../core/domain/entity.dart';
import '../../../core/domain/money.dart';
import 'daily_report.dart';

final class DailyRecord {
  const DailyRecord({
    required this.meta,
    required this.date,
    required this.sales,
    required this.profit,
    this.note,
  });
  final EntityMeta meta;
  final BusinessDate date;
  final Money sales, profit;
  final String? note;
}

abstract interface class DailyRecordsRepository {
  Future<DailyRecord?> onDate(BusinessDate date);
  Future<List<DailyRecord>> records({int limit = 50, int offset = 0});
  Future<DailyRecord?> byId(String id);
  Future<DailyReport> report(ReportRange range);
  Future<DailyRecord> save({
    String? operationId,
    String? id,
    required BusinessDate date,
    required Money sales,
    required Money profit,
    String? note,
  });
  Future<void> delete(String id, {String? operationId});
}
