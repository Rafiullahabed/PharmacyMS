import '../../../core/domain/dates.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/validation.dart';
import 'daily_record.dart';

BusinessDate shiftDay(BusinessDate day, int offset) {
  final value = DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).add(Duration(days: offset));
  return BusinessDate(value.year, value.month, value.day);
}

enum ReportPeriod { today, last7Days, thisMonth, custom }

extension ReportPeriodLabel on ReportPeriod {
  String get label => switch (this) {
    ReportPeriod.today => 'Today',
    ReportPeriod.last7Days => 'Last 7 days',
    ReportPeriod.thisMonth => 'This month',
    ReportPeriod.custom => 'Custom range',
  };
  ReportRange range(BusinessDate today, {ReportRange? custom}) =>
      switch (this) {
        ReportPeriod.today => ReportRange(today, today),
        ReportPeriod.last7Days => ReportRange(shiftDay(today, -6), today),
        ReportPeriod.thisMonth => ReportRange(
          BusinessDate(today.year, today.month, 1),
          today,
        ),
        ReportPeriod.custom => custom ?? ReportRange(today, today),
      };
}

final class ReportRange {
  ReportRange(this.start, this.end) {
    if (start.compareTo(end) > 0) {
      throw const ValidationException(
        'Start date must be on or before end date.',
      );
    }
  }
  final BusinessDate start, end;
  int get days => start.daysUntil(end) + 1;
  String get label => '${start.label} – ${end.label}';
  bool contains(BusinessDate date) =>
      date.compareTo(start) >= 0 && date.compareTo(end) <= 0;
  ReportRange? get previous {
    if (BusinessDate(1, 1, 1).daysUntil(start) < days) return null;
    return ReportRange(shiftDay(start, -days), shiftDay(start, -1));
  }
}

final class RecordedTotals {
  RecordedTotals(Iterable<DailyRecord> records, this.days) {
    for (final record in records) {
      sales += BigInt.from(record.sales.minor);
      profit += BigInt.from(record.profit.minor);
      recorded++;
    }
  }
  BigInt sales = BigInt.zero, profit = BigInt.zero;
  int recorded = 0;
  final int days;
  String get coverage => '$recorded of $days days recorded';
}

/// A rounded display percentage, computed with integers. A negative baseline
/// uses its magnitude so moving from loss to profit reads as an increase.
String recordedChange(
  BigInt current,
  BigInt previous, {
  required bool hasData,
}) {
  if (!hasData || previous == BigInt.zero) return 'Not available';
  final numerator = (current - previous) * BigInt.from(10000);
  final rounded =
      (numerator.abs() + previous.abs() ~/ BigInt.two) ~/ previous.abs();
  return '${numerator.isNegative ? '-' : '+'}${rounded ~/ BigInt.from(100)}.${(rounded % BigInt.from(100)).toString().padLeft(2, '0')}%';
}

final class ReportPoint {
  const ReportPoint({
    required this.range,
    required this.label,
    required this.totals,
    this.record,
  });
  final ReportRange range;
  final String label;
  final RecordedTotals totals;
  final DailyRecord? record;
  bool get recorded => totals.recorded > 0;
  BigInt? value(bool profit) =>
      !recorded ? null : (profit ? totals.profit : totals.sales);
  String valueLabel(bool profit) =>
      !recorded ? 'Not recorded' : formatMinorUnits(value(profit)!);
}

final class DailyReport {
  DailyReport({
    required this.range,
    required List<DailyRecord> records,
    required List<DailyRecord> previousRecords,
  }) : records = List.unmodifiable(
         records.where((r) => range.contains(r.date)).toList()
           ..sort((a, b) => b.date.compareTo(a.date)),
       ),
       totals = RecordedTotals(
         records.where((r) => range.contains(r.date)),
         range.days,
       ),
       previousTotals = RecordedTotals(
         previousRecords.where(
           (r) => range.previous?.contains(r.date) ?? false,
         ),
         range.previous?.days ?? 0,
       ) {
    byDate = {for (final record in this.records) record.date.iso: record};
    final grouped = <String, List<DailyRecord>>{};
    for (final record in this.records) {
      (grouped[record.date.iso.substring(0, 7)] ??= []).add(record);
    }
    var year = range.start.year, month = range.start.month;
    final results = <ReportPoint>[];
    while (year < range.end.year ||
        (year == range.end.year && month <= range.end.month)) {
      final first = BusinessDate(year, month, 1);
      final last = BusinessDate(
        year,
        month,
        DateTime.utc(year, month + 1, 0).day,
      );
      final part = ReportRange(
        first.compareTo(range.start) < 0 ? range.start : first,
        last.compareTo(range.end) > 0 ? range.end : last,
      );
      results.add(
        ReportPoint(
          range: part,
          label: first.label.substring(3),
          totals: RecordedTotals(
            grouped[first.iso.substring(0, 7)] ?? [],
            part.days,
          ),
        ),
      );
      if (month == 12) {
        year++;
        month = 1;
      } else {
        month++;
      }
    }
    months = List.unmodifiable(results);
  }
  final ReportRange range;
  final List<DailyRecord> records;
  final RecordedTotals totals, previousTotals;
  late final Map<String, DailyRecord> byDate;
  late final List<ReportPoint> months;
  ReportPoint dayAt(int chronologicalIndex) {
    final date = shiftDay(range.start, chronologicalIndex),
        record = byDate[shiftDay(range.start, chronologicalIndex).iso];
    return ReportPoint(
      range: ReportRange(date, date),
      label: date.label,
      totals: RecordedTotals(record == null ? [] : [record], 1),
      record: record,
    );
  }

  String change(bool profit) => recordedChange(
    profit ? totals.profit : totals.sales,
    profit ? previousTotals.profit : previousTotals.sales,
    hasData: totals.recorded > 0 && previousTotals.recorded > 0,
  );
}
