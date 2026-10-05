import 'validation.dart';

/// AFN uses 100 minor units. No double conversion, rounding, or silent truncation.
final class Money implements Comparable<Money> {
  Money.fromMinor(this.minor) {
    if (minor < -maxMinor || minor > maxMinor) {
      throw const ValidationException('Amount is outside the supported range.');
    }
  }
  static const maxMinor = 9000000000000000;
  final int minor;

  factory Money.parse(String input) {
    final text = normalizeDigits(
      input.trim(),
    ).replaceAll('٫', '.').replaceAll('٬', ',').replaceAll('−', '-');
    if (!RegExp(
      r'^[+-]?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$',
    ).hasMatch(text)) {
      throw const ValidationException(
        'Enter an amount with up to two decimal places. Use commas only for groups of three digits.',
      );
    }
    final negative = text.startsWith('-');
    final parts = text.replaceAll(RegExp(r'[,+-]'), '').split('.');
    final amount =
        BigInt.parse(parts[0]) * BigInt.from(100) +
        BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
    if (amount > BigInt.from(maxMinor)) {
      throw const ValidationException('Amount is outside the supported range.');
    }
    return Money.fromMinor(negative ? -amount.toInt() : amount.toInt());
  }

  Money operator +(Money other) =>
      _checked(BigInt.from(minor) + BigInt.from(other.minor));
  Money operator -(Money other) =>
      _checked(BigInt.from(minor) - BigInt.from(other.minor));
  static Money _checked(BigInt value) {
    if (value.abs() > BigInt.from(maxMinor)) {
      throw const ValidationException('Total is outside the supported range.');
    }
    return Money.fromMinor(value.toInt());
  }

  String get decimal =>
      '${minor < 0 ? '-' : ''}${minor.abs() ~/ 100}.${(minor.abs() % 100).toString().padLeft(2, '0')}';
  String get formatted {
    return formatMinorUnits(BigInt.from(minor));
  }

  @override
  int compareTo(Money other) => minor.compareTo(other.minor);
  @override
  bool operator ==(Object other) => other is Money && other.minor == minor;
  @override
  int get hashCode => minor.hashCode;
}

/// Reports may sum many valid entries beyond a single entry's storage bound.
/// Keep these totals exact too; doubles are only suitable for chart coordinates.
String formatMinorUnits(BigInt minor) {
  final absolute = minor.abs();
  final whole = (absolute ~/ BigInt.from(100)).toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return 'AFN ${minor.isNegative ? '-' : ''}$whole.${(absolute % BigInt.from(100)).toString().padLeft(2, '0')}';
}
