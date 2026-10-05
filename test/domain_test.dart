import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/core/domain/money.dart';
import 'package:pharmacyms/core/domain/validation.dart';

void main() {
  group('Exact AFN', () {
    test('normalizes Persian/Arabic digits and validated separators', () {
      expect(Money.parse('۵۰٬۰۰۰٫۵۰').minor, 5000050);
      expect(Money.parse('١٢.٣').minor, 1230);
      expect(Money.parse('-0.01').minor, -1);
      expect(Money.parse('50,000').formatted, 'AFN 50,000.00');
      expect(Money.parse('-1000.5').formatted, 'AFN -1,000.50');
    });
    test('decimal arithmetic never rounds through a double', () {
      expect(Money.parse('0.10') + Money.parse('0.20'), Money.parse('0.30'));
      expect(Money.parse('90000000000000').minor, Money.maxMinor);
      expect(
        () => Money.parse('90000000000000.01'),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => Money.fromMinor(Money.maxMinor) + Money.fromMinor(1),
        throwsA(isA<ValidationException>()),
      );
    });
    for (final value in [
      '',
      '1,23',
      '1 234',
      '1.234',
      '1e3',
      'NaN',
      '1.2.3',
      '--2',
      '.50',
      '1,000,00',
    ]) {
      test('rejects ambiguous or invalid amount "$value"', () {
        expect(() => Money.parse(value), throwsA(isA<ValidationException>()));
      });
    }
  });
  group('Civil dates and retained precision', () {
    test('rejects Gregorian normalization and honors century leap rules', () {
      expect(BusinessDate(2000, 2, 29).iso, '2000-02-29');
      for (final date in [
        '1900-02-29',
        '2025-02-29',
        '2026-04-31',
        '2026-13-01',
        '2026-01-00',
        '2026-1-01',
        '2026-10-05T00:00:00Z',
      ]) {
        expect(
          () => BusinessDate.parse(date),
          throwsA(isA<ValidationException>()),
        );
      }
      expect(BusinessDate(2024, 3, 9).daysUntil(BusinessDate(2024, 3, 11)), 2);
    });
    test('known Nowruz boundary and leap Esfand conversion', () {
      final leap = DateSpec(
        calendar: DateCalendar.solarHijri,
        year: 1399,
        month: 12,
        day: 30,
      );
      expect(leap.range.start.iso, '2021-03-20');
      final next = DateSpec(
        calendar: DateCalendar.solarHijri,
        year: 1400,
        month: 1,
        day: 1,
      );
      expect(next.range.start.iso, '2021-03-21');
      expect(
        () => DateSpec(
          calendar: DateCalendar.solarHijri,
          year: 1400,
          month: 12,
          day: 30,
        ),
        throwsA(isA<ValidationException>()),
      );
    });
    test(
      'month end uses original calendar and retains supplied components',
      () {
        final spec = DateSpec(
          calendar: DateCalendar.solarHijri,
          year: 1403,
          month: 12,
        );
        expect(spec.day, isNull);
        expect(spec.range.start.iso, '2025-02-19');
        expect(spec.effectiveExpiry.iso, '2025-03-20');
        expect(DateSpec.fromMap(spec.toMap()).toMap(), spec.toMap());
        expect(
          () => spec.representationIn(DateCalendar.gregorian),
          throwsA(isA<ValidationException>()),
        );
        expect(
          DateSpec(
            calendar: DateCalendar.gregorian,
            year: 2024,
            month: 2,
          ).effectiveExpiry.iso,
          '2024-02-29',
        );
      },
    );
    test('full representations round trip every day across 1900–2100', () {
      var day = DateTime.utc(1900);
      final end = DateTime.utc(2101);
      while (day.isBefore(end)) {
        final spec = DateSpec(
          calendar: DateCalendar.gregorian,
          year: day.year,
          month: day.month,
          day: day.day,
        );
        final converted = spec.representationIn(DateCalendar.solarHijri);
        expect(
          converted.representationIn(DateCalendar.gregorian).toMap(),
          spec.toMap(),
        );
        day = day.add(const Duration(days: 1));
      }
    });
    test('production overlap is valid; unambiguously later is rejected', () {
      final month = DateSpec(
        calendar: DateCalendar.gregorian,
        year: 2026,
        month: 10,
      );
      final early = DateSpec(
        calendar: DateCalendar.gregorian,
        year: 2026,
        month: 10,
        day: 2,
      );
      expect(() => validateProductionExpiry(month, early), returnsNormally);
      expect(
        () => validateProductionExpiry(
          DateSpec(calendar: DateCalendar.gregorian, year: 2026, month: 11),
          month,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(() => validateProductionExpiry(month, null), returnsNormally);
    });
    test('invalid precision and out of range inputs are rejected', () {
      expect(
        () => DateSpec.fromMap({
          'calendar': 'gregorian',
          'year': 2026,
          'month': 10,
          'day': 5,
          'precision': 'month',
        }),
        throwsA(isA<ValidationException>()),
      );
      for (final month in [0, 13]) {
        expect(
          () => DateSpec(
            calendar: DateCalendar.solarHijri,
            year: 1405,
            month: month,
          ),
          throwsA(isA<ValidationException>()),
        );
      }
    });
  });
  test('Unicode search normalization preserves stored source', () {
    const original = '  كريمي  ';
    expect(searchKey(original), 'کریمی');
    expect(original, '  كريمي  ');
    expect(wholeQuantity('۱۲'), 12);
    expect(() => wholeQuantity('1.5'), throwsA(isA<ValidationException>()));
    expect(
      () => wholeQuantity('0', positive: true),
      throwsA(isA<ValidationException>()),
    );
  });
}
