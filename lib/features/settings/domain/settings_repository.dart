import '../../../core/domain/entity.dart';
import '../../inventory/domain/inventory.dart';

final class AppPreference {
  const AppPreference(this.meta, this.key, this.value, this.version);
  final EntityMeta meta;
  final String key, value;
  final int version;
}

abstract interface class SettingsRepository {
  Future<List<StockUnit>> units();
  Future<Map<String, int>> unitUsage();
  Future<StockUnit> saveUnit({
    String? id,
    required String name,
    bool inactive = false,
    String? operationId,
  });
  Future<void> deleteUnusedUnit(String id, {String? operationId});
  Future<AppPreference?> preference(String key);
  Future<void> setPreference(String key, String value, {int version = 1});
}
