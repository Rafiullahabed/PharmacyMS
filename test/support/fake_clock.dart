import 'package:pharmacyms/core/domain/dates.dart';

class FakeClock implements AppClock {
  FakeClock({BusinessDate? date}) : date = date ?? BusinessDate(2026, 10, 5);
  BusinessDate date;
  @override
  DateTime nowUtc() => DateTime.utc(date.year, date.month, date.day, 8);
  @override
  BusinessDate today() => date;
}
