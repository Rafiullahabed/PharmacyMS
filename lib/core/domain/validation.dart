class ValidationException implements Exception {
  const ValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

String requiredText(String value, String label) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) throw ValidationException('$label is required.');
  return trimmed;
}

String normalizeDigits(String value) {
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  for (var i = 0; i < 10; i++) {
    value = value.replaceAll(persian[i], '$i').replaceAll(arabic[i], '$i');
  }
  return value;
}

String searchKey(String value) =>
    value.trim().toLowerCase().replaceAll('ي', 'ی').replaceAll('ك', 'ک');

int wholeQuantity(String input, {bool positive = false}) {
  final value = normalizeDigits(input.trim());
  final parsed = int.tryParse(value);
  if (!RegExp(r'^\d+$').hasMatch(value) ||
      parsed == null ||
      parsed < (positive ? 1 : 0) ||
      parsed > maxQuantity) {
    throw ValidationException(
      'Enter a ${positive ? 'positive' : 'nonnegative'} whole quantity (up to $maxQuantity).',
    );
  }
  return parsed;
}

// Bounds keep all SQLite arithmetic exact and guard accidental huge inputs.
const maxQuantity = 2147483647;
