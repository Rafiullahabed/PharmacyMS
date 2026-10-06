import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/domain/dates.dart';
import '../../settings/domain/settings_repository.dart';
import '../domain/inventory.dart';

typedef InventoryDependencies = ({
  InventoryRepository inventory,
  SettingsRepository settings,
});

/// One shared change signal refreshes lists, details, units and Home after commits.
class InventoryController extends ChangeNotifier {
  InventoryController({required this.resolve, required this.clock}) {
    _lastDay = clock.today();
  }
  final Future<InventoryDependencies> Function() resolve;
  final AppClock clock;
  InventoryDependencies? _dependencies;
  int revision = 0;
  bool adjustmentOpen = false;
  bool _disposed = false;
  BusinessDate? _lastDay;
  Timer? _dayTimer;
  Future<InventoryDependencies> get dependencies async =>
      _dependencies ??= await resolve();
  Future<InventoryRepository> get repository async =>
      (await dependencies).inventory;
  Future<SettingsRepository> get settings async =>
      (await dependencies).settings;
  void changed() {
    if (_disposed) return;
    revision++;
    _lastDay = clock.today();
    notifyListeners();
  }

  void resetRepositories() {
    _dependencies = null;
    adjustmentOpen = false;
    changed();
  }

  void refreshDay() {
    if (_lastDay != clock.today()) changed();
  }

  /// Watches local civil dates independently of Home's other repository reads.
  /// This timer only invalidates in-app views; it schedules no notifications.
  void startDayWatch() {
    _dayTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => refreshDay(),
    );
  }

  void stopDayWatch() {
    _dayTimer?.cancel();
    _dayTimer = null;
  }

  Future<InventoryListData> loadList({
    required String search,
    required InventoryFilter filter,
    required bool archived,
    required int pages,
  }) async {
    final repo = await repository, today = clock.today();
    final overview = await repo.overview(today);
    final items = <InventoryItem>[], alerts = <BatchAlert>[];
    var totalProducts = 0, totalBatches = 0;
    for (var page = 0; page < pages; page++) {
      if (filter.isExpiry) {
        final result = await repo.alertPage(
          today: today,
          filter: filter,
          search: search,
          offset: page * 50,
        );
        alerts.addAll(result.items);
        totalProducts = result.totalProducts;
        totalBatches = result.totalBatches;
      } else {
        final result = await repo.inventory(
          today: today,
          search: search,
          filter: filter,
          archived: archived,
          offset: page * 50,
        );
        items.addAll(result.items);
        totalProducts = result.total;
      }
    }
    return InventoryListData(
      today: today,
      overview: overview,
      items: items,
      alerts: alerts,
      totalProducts: totalProducts,
      totalBatches: totalBatches,
      more: filter.isExpiry
          ? alerts.length < totalBatches
          : items.length < totalProducts,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    stopDayWatch();
    super.dispose();
  }
}

final class InventoryListData {
  const InventoryListData({
    required this.today,
    required this.overview,
    required this.items,
    required this.alerts,
    required this.totalProducts,
    required this.totalBatches,
    required this.more,
  });
  final BusinessDate today;
  final InventoryOverview overview;
  final List<InventoryItem> items;
  final List<BatchAlert> alerts;
  final int totalProducts, totalBatches;
  final bool more;
}
