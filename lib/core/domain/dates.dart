import 'package:shamsi_date/shamsi_date.dart';
import 'validation.dart';

/// A Gregorian civil date, never a saved instant or timezone offset.
final class BusinessDate implements Comparable<BusinessDate> {
  BusinessDate(this.year, this.month, this.day) {
    if (year < 1 ||
        year > 9999 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > DateTime.utc(year, month + 1, 0).day) {
      throw const ValidationException('Enter a valid Gregorian date.');
    }
  }
  factory BusinessDate.parse(String input) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input)) {
      throw const ValidationException('Use a date in YYYY-MM-DD format.');
    }
    final parts = input.split('-').map(int.parse).toList();
    return BusinessDate(parts[0], parts[1], parts[2]);
  }
  factory BusinessDate.fromLocal(DateTime local) =>
      BusinessDate(local.year, local.month, local.day);
  final int year, month, day;
  String get iso =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  String get label =>
      '${day.toString().padLeft(2, '0')} ${_months[month - 1]} $year';
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  int daysUntil(BusinessDate other) => DateTime.utc(
    other.year,
    other.month,
    other.day,
  ).difference(DateTime.utc(year, month, day)).inDays;
  @override
  int compareTo(BusinessDate other) => iso.compareTo(other.iso);
  @override
  bool operator ==(Object other) => other is BusinessDate && iso == other.iso;
  @override
  int get hashCode => iso.hashCode;
  @override
  String toString() => iso;
}

enum DateCalendar { gregorian, solarHijri }

enum DatePrecision { full, month }

final class DateRange {
  const DateRange(this.start, this.end);
  final BusinessDate start, end;
}

/// Source components are authoritative. Canonical ranges are derived, never edited.
final class DateSpec {
  DateSpec({
    required this.calendar,
    required this.year,
    required this.month,
    this.day,
  }) {
    // Keep a documented common supported range within shamsi_date's algorithm.
    final validYear = calendar == DateCalendar.gregorian
        ? year >= 622 && year <= 3798
        : year >= 1 && year <= 3177;
    if (!validYear || month < 1 || month > 12) {
      throw const ValidationException(
        'Enter valid date components in the supported calendar range.',
      );
    }
    try {
      if (day != null && (day! < 1 || day! > daysInMonth)) {
        throw const ValidationException('Enter a valid day for this month.');
      }
      final canonical = range;
      final lower = Jalali(1, 1, 1).toGregorian();
      if (canonical.start.compareTo(
                BusinessDate(lower.year, lower.month, lower.day),
              ) <
              0 ||
          canonical.end.compareTo(BusinessDate(3798, 12, 31)) > 0) {
        throw const ValidationException(
          'Date is outside the supported calendar range.',
        );
      }
    } on DateException {
      throw const ValidationException(
        'Date is outside the supported calendar range.',
      );
    }
  }
  final DateCalendar calendar;
  final int year, month;
  final int? day;
  DatePrecision get precision =>
      day == null ? DatePrecision.month : DatePrecision.full;
  int get daysInMonth => calendar == DateCalendar.gregorian
      ? DateTime.utc(year, month + 1, 0).day
      : Jalali(year, month).monthLength;
  BusinessDate _canonical(int d) {
    if (calendar == DateCalendar.gregorian) return BusinessDate(year, month, d);
    final g = Jalali(year, month, d).toGregorian();
    return BusinessDate(g.year, g.month, g.day);
  }

  DateRange get range =>
      DateRange(_canonical(day ?? 1), _canonical(day ?? daysInMonth));
  BusinessDate get effectiveExpiry => range.end;
  String get label =>
      '${year.toString().padLeft(4, '0')}/${month.toString().padLeft(2, '0')}${day == null ? '' : '/${day.toString().padLeft(2, '0')}'} · ${calendar == DateCalendar.gregorian ? 'Gregorian' : 'Solar Hijri'} · ${day == null ? 'Month only' : 'Full date'}';

  /// Display conversion leaves this original specification untouched.
  DateSpec representationIn(DateCalendar target) {
    if (target == calendar) return this;
    if (day == null) {
      throw const ValidationException(
        'A month spans a date range. Keep its original calendar or explicitly enter a new month.',
      );
    }
    final g = range.start;
    if (target == DateCalendar.gregorian) {
      return DateSpec(
        calendar: target,
        year: g.year,
        month: g.month,
        day: g.day,
      );
    }
    final j = Gregorian(g.year, g.month, g.day).toJalali();
    return DateSpec(calendar: target, year: j.year, month: j.month, day: j.day);
  }

  Map<String, Object?> toMap() => {
    'calendar': calendar.name,
    'year': year,
    'month': month,
    'day': day,
    'precision': precision.name,
  };
  factory DateSpec.fromMap(Map<String, Object?> map) {
    final spec = DateSpec(
      calendar: DateCalendar.values.byName(map['calendar'] as String),
      year: map['year'] as int,
      month: map['month'] as int,
      day: map['day'] as int?,
    );
    if (spec.precision.name != map['precision']) {
      throw const ValidationException(
        'Date precision does not match its components.',
      );
    }
    return spec;
  }
}

void validateProductionExpiry(DateSpec? production, DateSpec? expiry) {
  if (production != null &&
      expiry != null &&
      production.range.start.compareTo(expiry.range.end) > 0) {
    throw const ValidationException('Production is after expiry.');
  }
}

abstract interface class AppClock {
  DateTime nowUtc();
  BusinessDate today();
}

class SystemClock implements AppClock {
  const SystemClock();
  @override
  DateTime nowUtc() => DateTime.now().toUtc();
  @override
  BusinessDate today() => BusinessDate.fromLocal(DateTime.now());
}

void validateNotFuture(BusinessDate date, AppClock clock) {
  if (date.compareTo(clock.today()) > 0) {
    throw const ValidationException('Future business dates are not allowed.');
  }
}
