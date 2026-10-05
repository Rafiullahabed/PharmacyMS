import '../../../core/domain/dates.dart';
import '../../../core/domain/entity.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/validation.dart';

final class Customer {
  const Customer({
    required this.meta,
    required this.name,
    this.phone,
    this.note,
    this.archived = false,
  });
  final EntityMeta meta;
  final String name;
  final String? phone, note;
  final bool archived;
}

enum LedgerKind { debt, payment }

extension LedgerKindLabel on LedgerKind {
  String get label =>
      this == LedgerKind.debt ? 'Debt added' : 'Payment received';
  String get action => this == LedgerKind.debt ? 'Add debt' : 'Record payment';
}

enum CustomerFilter { all, outstanding, settled }

extension CustomerFilterLabel on CustomerFilter {
  String get label => switch (this) {
    CustomerFilter.all => 'All',
    CustomerFilter.outstanding => 'Outstanding',
    CustomerFilter.settled => 'Settled',
  };
}

final class CustomerBalance {
  const CustomerBalance(this.customer, this.balance, this.latest);
  final Customer customer;
  final Money balance;
  final BusinessDate? latest;
}

final class CustomerPage {
  const CustomerPage(
    this.items,
    this.total,
    this.activeCount,
    this.outstanding,
  );
  final List<CustomerBalance> items;
  final int total, activeCount;
  final BigInt outstanding;
}

final class LedgerLine {
  const LedgerLine(this.entry, this.balance);
  final LedgerEntry entry;
  final Money balance;
}

final class CustomerLedger {
  const CustomerLedger(this.customer, this.balance, this.lines, this.total);
  final Customer customer;
  final Money balance;
  final List<LedgerLine> lines;
  final int total;
}

final class LedgerDraft {
  const LedgerDraft({
    required this.date,
    required this.kind,
    required this.amount,
    this.description = '',
  });
  final BusinessDate date;
  final LedgerKind kind;
  final Money amount;
  final String description;
  void validate(AppClock clock) {
    validateNotFuture(date, clock);
    if (amount.minor <= 0) {
      throw const ValidationException('Enter a positive amount.');
    }
  }
}

final class LedgerPreview {
  const LedgerPreview(this.before, this.after, {this.atEntry});
  final Money before, after;
  final Money? atEntry;
}

/// The same chronological policy serves previews and transaction validation.
/// A correction never changes another entry, its sequence, or its description.
LedgerPreview projectLedger(
  List<LedgerEntry> entries, {
  LedgerEntry? replacement,
  String? removeId,
}) {
  BigInt sum(Iterable<LedgerEntry> rows) => rows.fold(
    BigInt.zero,
    (n, e) =>
        n +
        (e.kind == LedgerKind.debt
            ? BigInt.from(e.amount.minor)
            : -BigInt.from(e.amount.minor)),
  );
  final before = Money.fromMinor(sum(entries).toInt());
  final next =
      [
        ...entries.where(
          (e) => e.meta.id != removeId && e.meta.id != replacement?.meta.id,
        ),
        ?replacement,
      ]..sort((a, b) {
        final date = a.date.compareTo(b.date);
        return date != 0 ? date : a.sequence.compareTo(b.sequence);
      });
  var balance = BigInt.zero;
  Money? atEntry;
  for (final e in next) {
    final available = balance;
    balance += e.kind == LedgerKind.debt
        ? BigInt.from(e.amount.minor)
        : -BigInt.from(e.amount.minor);
    if (balance.isNegative) {
      throw ValidationException(
        'This change would make the balance negative on ${e.date.label}. Only ${formatMinorUnits(available)} is available before that payment. Correct dependent entries first.',
      );
    }
    if (balance > BigInt.from(Money.maxMinor)) {
      throw const ValidationException(
        'A chronological balance exceeds the supported amount limit.',
      );
    }
    if (e.meta.id == replacement?.meta.id) {
      atEntry = Money.fromMinor(balance.toInt());
    }
  }
  return LedgerPreview(
    before,
    Money.fromMinor(balance.toInt()),
    atEntry: atEntry,
  );
}

final class LedgerEntry {
  const LedgerEntry({
    required this.meta,
    required this.customerId,
    required this.date,
    required this.sequence,
    required this.kind,
    required this.amount,
    required this.description,
  });
  final EntityMeta meta;
  final String customerId, description;
  final BusinessDate date;
  final int sequence;
  final LedgerKind kind;
  final Money amount;
}

final class CorrectionAudit {
  const CorrectionAudit({
    required this.meta,
    required this.entryId,
    required this.customerId,
    required this.action,
    required this.previous,
    required this.next,
    required this.reason,
  });
  final EntityMeta meta;
  final String entryId, customerId, action, reason;
  final DataRow previous;
  final DataRow? next;
}

abstract interface class DebtRepository {
  Future<Customer> customer(String id);
  Future<Customer> saveCustomer({
    required String operationId,
    String? id,
    required String name,
    String? phone,
    String? note,
  });
  Future<List<Customer>> similarCustomers(String name, {String? excludingId});
  Future<CustomerPage> searchCustomers({
    String search = '',
    CustomerFilter filter = CustomerFilter.all,
    bool archived = false,
    int limit = 50,
    int offset = 0,
  });
  Future<CustomerLedger> history(
    String customerId, {
    int limit = 50,
    int offset = 0,
  });
  Future<LedgerEntry?> entry(String id);
  Future<LedgerPreview> preview(
    String customerId, {
    String? entryId,
    LedgerDraft? draft,
    bool deleting = false,
  });
  Future<List<String>> productNames(String search);
  Future<Customer> createCustomer({
    required String name,
    String? phone,
    String? note,
  });
  Future<List<Customer>> customers({int limit = 50, int offset = 0});
  Future<LedgerEntry> addEntry({
    required String operationId,
    required String customerId,
    required BusinessDate date,
    required LedgerKind kind,
    required Money amount,
    String description = '',
  });
  Future<LedgerEntry> editEntry({
    String? operationId,
    required String id,
    required BusinessDate date,
    required LedgerKind kind,
    required Money amount,
    required String description,
    required String reason,
  });
  Future<void> deleteEntry(
    String id, {
    required String reason,
    String? operationId,
  });
  Future<List<LedgerEntry>> ledger(
    String customerId, {
    int limit = 50,
    int offset = 0,
  });
  Future<List<CorrectionAudit>> corrections(
    String customerId, {
    int limit = 50,
    int offset = 0,
  });
  Future<Money> balance(String customerId);
  Future<void> archiveCustomer(
    String id, {
    required bool archived,
    String? operationId,
  });
}
