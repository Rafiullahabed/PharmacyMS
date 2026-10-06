import 'package:pharmacyms/core/domain/dates.dart';
import 'package:pharmacyms/features/inventory/application/inventory_controller.dart';
import 'package:pharmacyms/features/inventory/domain/inventory.dart';
import 'package:pharmacyms/features/settings/domain/settings_repository.dart';
import 'fake_clock.dart';

InventoryController emptyInventory() => InventoryController(
  clock: FakeClock(),
  resolve: () async =>
      (inventory: _EmptyRepository(), settings: _EmptySettings()),
);

class _EmptyRepository implements InventoryRepository {
  @override
  Future<InventoryOverview> overview(BusinessDate today) async =>
      const InventoryOverview();
  @override
  Future<InventoryDashboard> dashboard(BusinessDate today) async =>
      InventoryDashboard(
        today: today,
        overview: const InventoryOverview(),
        expiryAttention: [],
        stockAttention: [],
      );
  @override
  Future<BatchAlertPage> alertPage({
    required BusinessDate today,
    required InventoryFilter filter,
    String search = '',
    int limit = 50,
    int offset = 0,
  }) async => const BatchAlertPage([], totalBatches: 0, totalProducts: 0);
  @override
  Future<InventoryPage> inventory({
    required BusinessDate today,
    String search = '',
    InventoryFilter filter = InventoryFilter.all,
    bool archived = false,
    int limit = 50,
    int offset = 0,
  }) async => const InventoryPage([], 0);
  @override
  Future<List<BatchAlert>> alerts({
    required BusinessDate today,
    required InventoryFilter filter,
    String search = '',
    int limit = 50,
    int offset = 0,
  }) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptySettings implements SettingsRepository {
  @override
  Future<AppPreference?> preference(String key) async => null;
  @override
  Future<List<StockUnit>> units() async => [];
  @override
  Future<Map<String, int>> unitUsage() async => {};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
