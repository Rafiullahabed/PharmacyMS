import 'package:pharmacyms/features/debtors/application/debt_controller.dart';
import 'package:pharmacyms/features/debtors/domain/debt.dart';
import 'fake_clock.dart';

DebtController emptyDebt() =>
    DebtController(clock: FakeClock(), resolve: () async => _EmptyDebt());

class _EmptyDebt implements DebtRepository {
  @override
  Future<CustomerPage> searchCustomers({
    String search = '',
    CustomerFilter filter = CustomerFilter.all,
    bool archived = false,
    int limit = 50,
    int offset = 0,
  }) async => CustomerPage([], 0, 0, BigInt.zero);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Read-only empty fixture');
}
