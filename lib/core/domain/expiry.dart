import 'dates.dart';
import 'validation.dart';

enum ExpiryState { noExpiry, inDate, expiringSoon, expiresToday, expired }

/// Date status only; quantity/archive filtering belongs to inventory queries.
ExpiryState expiryState(
  DateSpec? expiry,
  BusinessDate today, {
  required int warningDays,
}) {
  if (warningDays < 0) {
    throw const ValidationException('Warning days must be nonnegative.');
  }
  if (expiry == null) return ExpiryState.noExpiry;
  final days = today.daysUntil(expiry.effectiveExpiry);
  if (days < 0) return ExpiryState.expired;
  if (days == 0) return ExpiryState.expiresToday;
  if (days <= warningDays) return ExpiryState.expiringSoon;
  return ExpiryState.inDate;
}
