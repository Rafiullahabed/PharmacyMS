import 'package:flutter/foundation.dart';
import '../../../core/domain/dates.dart';
import '../domain/debt.dart';

class DebtController extends ChangeNotifier {
  DebtController({required this.resolve, required this.clock})
    : _day = clock.today();
  final Future<DebtRepository> Function() resolve;
  final AppClock clock;
  Future<DebtRepository>? _repository;
  BusinessDate _day;
  bool _disposed = false;
  Future<DebtRepository> get repository async {
    try {
      return await (_repository ??= resolve());
    } catch (_) {
      _repository = null;
      rethrow;
    }
  }

  void changed() {
    if (_disposed) return;
    _day = clock.today();
    notifyListeners();
  }

  void resetRepositories() {
    _repository = null;
    changed();
  }

  void refreshDay() {
    if (_day != clock.today()) changed();
  }

  Future<CustomerPage> customers({
    required String search,
    required CustomerFilter filter,
    required bool archived,
    required int pages,
  }) async {
    final repo = await repository;
    final items = <CustomerBalance>[];
    late CustomerPage data;
    for (var page = 0; page < pages; page++) {
      data = await repo.searchCustomers(
        search: search,
        filter: filter,
        archived: archived,
        offset: page * 50,
      );
      items.addAll(data.items);
      if (items.length >= data.total) break;
    }
    return CustomerPage(items, data.total, data.activeCount, data.outstanding);
  }

  Future<CustomerLedger> history(String id, {required int pages}) async {
    final repo = await repository;
    final lines = <LedgerLine>[];
    late CustomerLedger data;
    for (var page = 0; page < pages; page++) {
      data = await repo.history(id, offset: page * 50);
      lines.addAll(data.lines);
      if (lines.length >= data.total) break;
    }
    return CustomerLedger(data.customer, data.balance, lines, data.total);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
