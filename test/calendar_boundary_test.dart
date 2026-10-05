import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/core/domain/expiry.dart';
import 'package:pharmacyms/core/domain/validation.dart';

void main() {
  test(
    'full-date range endpoints convert both ways; partial endpoints are validated',
    () {
      final first = DateSpec(
        calendar: DateCalendar.solarHijri,
        year: 1,
        month: 1,
        day: 1,
      );
      expect(
        first
            .representationIn(DateCalendar.gregorian)
            .representationIn(DateCalendar.solarHijri)
            .toMap(),
        first.toMap(),
      );
      final last = DateSpec(
        calendar: DateCalendar.gregorian,
        year: 3798,
        month: 12,
        day: 31,
      );
      expect(last.representationIn(DateCalendar.solarHijri).toMap(), {
        'calendar': 'solarHijri',
        'year': 3177,
        'month': 10,
        'day': 11,
        'precision': 'full',
      });
      expect(
        () =>
            DateSpec(calendar: DateCalendar.solarHijri, year: 3177, month: 10),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => DateSpec(
          calendar: DateCalendar.solarHijri,
          year: 3177,
          month: 11,
          day: 1,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => DateSpec(
          calendar: DateCalendar.gregorian,
          year: 622,
          month: 1,
          day: 1,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => DateSpec(calendar: DateCalendar.solarHijri, year: 0, month: 1),
        throwsA(isA<ValidationException>()),
      );
    },
  );
  test(
    'expires today becomes expired on next civil day and warning boundary is inclusive',
    () {
      final expiry = DateSpec(
        calendar: DateCalendar.gregorian,
        year: 2026,
        month: 10,
        day: 5,
      );
      expect(
        expiryState(expiry, BusinessDate(2026, 10, 5), warningDays: 0),
        ExpiryState.expiresToday,
      );
      expect(
        expiryState(expiry, BusinessDate(2026, 10, 6), warningDays: 30),
        ExpiryState.expired,
      );
      expect(
        expiryState(expiry, BusinessDate(2026, 10, 4), warningDays: 0),
        ExpiryState.inDate,
      );
      expect(
        expiryState(expiry, BusinessDate(2026, 8, 21), warningDays: 45),
        ExpiryState.expiringSoon,
      );
      expect(
        expiryState(expiry, BusinessDate(2026, 8, 20), warningDays: 45),
        ExpiryState.inDate,
      );
      expect(
        expiryState(null, BusinessDate(2026, 10, 6), warningDays: 30),
        ExpiryState.noExpiry,
      );
    },
  );
}
