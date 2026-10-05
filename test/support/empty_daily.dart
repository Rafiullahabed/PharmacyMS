import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/core/domain/money.dart';
import 'package:pharmacyms/features/daily_records/domain/daily_record.dart';
import 'package:pharmacyms/features/daily_records/domain/daily_report.dart';
import 'package:pharmacyms/features/daily_records/application/daily_records_controller.dart';
import 'fake_clock.dart';

DailyRecordsController emptyDaily() => DailyRecordsController(
  clock: FakeClock(),
  resolve: () async => _EmptyDaily(),
);

class _EmptyDaily implements DailyRecordsRepository {
  @override
  Future<DailyRecord?> onDate(BusinessDate date) async => null;
  @override
  Future<DailyRecord?> byId(String id) async => null;
  @override
  Future<List<DailyRecord>> records({int limit = 50, int offset = 0}) async =>
      [];
  @override
  Future<DailyReport> report(ReportRange range) async =>
      DailyReport(range: range, records: [], previousRecords: []);
  @override
  Future<DailyRecord> save({
    String? operationId,
    String? id,
    required BusinessDate date,
    required Money sales,
    required Money profit,
    String? note,
  }) => throw UnimplementedError('Read-only fixture');
  @override
  Future<void> delete(String id, {String? operationId}) =>
      throw UnimplementedError('Read-only fixture');
}
