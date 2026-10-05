import '../../../core/domain/dates.dart';
import '../../../core/domain/entity.dart';
import '../../../core/domain/expiry.dart';
import '../../../core/domain/validation.dart';

final class StockUnit {
  const StockUnit(this.meta, this.name, this.inactive);
  final EntityMeta meta;
  final String name;
  final bool inactive;
}

final class Product {
  const Product({
    required this.meta,
    required this.name,
    required this.unitId,
    required this.minimumStock,
    required this.warningDays,
    this.category,
    this.notes,
    this.archived = false,
  });
  final EntityMeta meta;
  final String name, unitId;
  final int minimumStock, warningDays;
  final String? category, notes;
  final bool archived;
}

final class Batch {
  const Batch({
    required this.meta,
    required this.productId,
    required this.label,
    required this.receivedDate,
    required this.quantity,
    this.production,
    this.expiry,
    this.notes,
    this.archived = false,
  });
  final EntityMeta meta;
  final String productId, label;
  final BusinessDate receivedDate;
  final int quantity;
  final DateSpec? production, expiry;
  final String? notes;
  final bool archived;
}

enum MovementKind { opening, add, remove, reversal }

final class StockMovement {
  const StockMovement({
    required this.meta,
    required this.batchId,
    required this.sequence,
    required this.kind,
    required this.delta,
    required this.resultingQuantity,
    this.reversalOf,
    this.note,
  });
  final EntityMeta meta;
  final String batchId;
  final int sequence, delta, resultingQuantity;
  final MovementKind kind;
  final String? reversalOf, note;
}

abstract interface class InventoryRepository {
  Future<Product> saveProduct({
    required String operationId,
    String? productId,
    required ProductDraft draft,
    BatchDraft? initialStock,
  });
  Future<Batch> saveBatch({
    required String operationId,
    required String productId,
    String? batchId,
    required BatchDraft draft,
  });
  Future<Product> product(String id);
  Future<Batch> batch(String id);
  Future<bool> hasStockHistory(String productId);
  Future<List<Product>> similarProducts(String name, {String? excludingId});
  Future<void> archiveProduct(
    String id, {
    required bool archived,
    required String operationId,
  });
  Future<void> archiveBatch(
    String id, {
    required bool archived,
    required String operationId,
  });
  Future<InventoryPage> inventory({
    required BusinessDate today,
    String search = '',
    InventoryFilter filter = InventoryFilter.all,
    bool archived = false,
    int limit = 50,
    int offset = 0,
  });
  Future<List<BatchAlert>> alerts({
    required BusinessDate today,
    required InventoryFilter filter,
    String search = '',
    int limit = 50,
    int offset = 0,
  });
  Future<InventoryOverview> overview(BusinessDate today);
  Future<InventoryDashboard> dashboard(BusinessDate today);
  Future<BatchAlertPage> alertPage({
    required BusinessDate today,
    required InventoryFilter filter,
    String search = '',
    int limit = 50,
    int offset = 0,
  });
  Future<List<StockMovement>> productMovements(
    String productId, {
    int limit = 50,
    int offset = 0,
  });
  Future<List<Product>> products({int limit = 50, int offset = 0});
  Future<Product> createProduct({
    required String name,
    required String unitId,
    int minimumStock = 0,
    int warningDays = 30,
    String? category,
    String? notes,
  });
  Future<Batch> createBatch({
    required String productId,
    required BusinessDate receivedDate,
    required int openingQuantity,
    String? label,
    DateSpec? production,
    DateSpec? expiry,
    String? notes,
  });
  Future<List<Batch>> batches(String productId);
  Future<StockMovement> adjust({
    required String operationId,
    required String batchId,
    required int delta,
    String? note,
  });
  Future<StockMovement> reverse({
    required String operationId,
    required String movementId,
  });
  Future<List<StockMovement>> movements(
    String batchId, {
    int limit = 50,
    int offset = 0,
  });
}

final class ProductDraft {
  const ProductDraft({
    required this.name,
    required this.unitId,
    this.minimumStock = 0,
    this.warningDays = 30,
    this.category,
    this.notes,
  });
  final String name, unitId;
  final int minimumStock, warningDays;
  final String? category, notes;
  void validate() {
    requiredText(name, 'Name');
    wholeQuantity('$minimumStock');
    wholeQuantity('$warningDays');
  }

  DataRow toMap() => {
    'name': name.trim(),
    'unit_id': unitId,
    'minimum_stock': minimumStock,
    'warning_days': warningDays,
    'category': category,
    'notes': notes,
  };
}

final class BatchDraft {
  const BatchDraft({
    required this.receivedDate,
    this.quantity = 0,
    this.label,
    this.production,
    this.expiry,
    this.notes,
  });
  final BusinessDate receivedDate;
  final int quantity;
  final String? label, notes;
  final DateSpec? production, expiry;
  void validate({required bool creating}) {
    if (creating) wholeQuantity('$quantity', positive: true);
    if (!creating && quantity != 0) {
      throw const ValidationException(
        'Edit batch dates and notes here. Use Add or Remove stock for quantity changes.',
      );
    }
    validateProductionExpiry(production, expiry);
  }

  DataRow toMap() => {
    'received_date': receivedDate.iso,
    'quantity': quantity,
    'label': label?.trim(),
    'production': production?.toMap(),
    'expiry': expiry?.toMap(),
    'notes': notes,
  };
}

enum InventoryFilter {
  all,
  lowStock,
  outOfStock,
  expiringSoon,
  expired,
  expiresToday,
  needsAttention,
}

extension InventoryFilterLabel on InventoryFilter {
  String get label => switch (this) {
    InventoryFilter.all => 'All',
    InventoryFilter.lowStock => 'Low stock',
    InventoryFilter.outOfStock => 'Out of stock',
    InventoryFilter.expiringSoon => 'Expiring soon',
    InventoryFilter.expired => 'Expired',
    InventoryFilter.expiresToday => 'Expires today',
    InventoryFilter.needsAttention => 'Needs attention',
  };
  bool get isExpiry =>
      this == InventoryFilter.expiringSoon ||
      this == InventoryFilter.expired ||
      this == InventoryFilter.expiresToday;
}

/// Combines the shared calendar rule with inventory eligibility. Empty/history
/// batches retain their date metadata without producing active expiry warnings.
final class BatchInventoryStatus {
  BatchInventoryStatus(
    Batch batch,
    BusinessDate today, {
    required int warningDays,
    bool productArchived = false,
  }) : active = !batch.archived && !productArchived,
       quantity = batch.quantity,
       dateState = expiryState(batch.expiry, today, warningDays: warningDays),
       daysRemaining = batch.expiry == null
           ? null
           : today.daysUntil(batch.expiry!.effectiveExpiry);
  final bool active;
  final int quantity;
  final ExpiryState dateState;
  final int? daysRemaining;
  bool get empty => quantity == 0;
  int get physical => active ? quantity : 0;
  int get usable => active && dateState != ExpiryState.expired ? quantity : 0;
  bool get expired => active && !empty && dateState == ExpiryState.expired;
  bool get expiresToday =>
      active && !empty && dateState == ExpiryState.expiresToday;
  bool get expiringSoon =>
      active &&
      !empty &&
      (dateState == ExpiryState.expiringSoon ||
          dateState == ExpiryState.expiresToday);
}

final class InventoryItem {
  const InventoryItem({
    required this.product,
    required this.unit,
    required this.physical,
    required this.usable,
    required this.expiringBatches,
    required this.expiredBatches,
    this.expiresTodayBatches = 0,
  });
  final Product product;
  final String unit;
  final int physical,
      usable,
      expiringBatches,
      expiredBatches,
      expiresTodayBatches;
  int get expiredQuantity => physical - usable;
  bool get outOfStock => !product.archived && usable == 0;
  bool get lowStock =>
      !product.archived &&
      product.minimumStock > 0 &&
      usable < product.minimumStock;
  bool get needsAttention =>
      !product.archived &&
      (lowStock || outOfStock || expiringBatches > 0 || expiredBatches > 0);
  bool matches(InventoryFilter filter) => switch (filter) {
    InventoryFilter.all => true,
    InventoryFilter.lowStock => lowStock,
    InventoryFilter.outOfStock => outOfStock,
    InventoryFilter.expiringSoon => !product.archived && expiringBatches > 0,
    InventoryFilter.expired => !product.archived && expiredBatches > 0,
    InventoryFilter.expiresToday =>
      !product.archived && expiresTodayBatches > 0,
    InventoryFilter.needsAttention => needsAttention,
  };

  /// Detail screens and tests use the same inventory/date policy as query views.
  factory InventoryItem.fromBatches(
    Product product,
    String unit,
    Iterable<Batch> batches,
    BusinessDate today,
  ) {
    var physical = 0, usable = 0, expired = 0, expiring = 0, expiresToday = 0;
    for (final batch in batches) {
      final status = BatchInventoryStatus(
        batch,
        today,
        warningDays: product.warningDays,
        productArchived: product.archived,
      );
      physical += status.physical;
      usable += status.usable;
      if (status.expired) expired++;
      if (status.expiringSoon) expiring++;
      if (status.expiresToday) expiresToday++;
    }
    return InventoryItem(
      product: product,
      unit: unit,
      physical: physical,
      usable: usable,
      expiringBatches: expiring,
      expiredBatches: expired,
      expiresTodayBatches: expiresToday,
    );
  }
}

final class InventoryPage {
  const InventoryPage(this.items, this.total);
  final List<InventoryItem> items;
  final int total;
}

final class BatchAlert {
  const BatchAlert(this.product, this.unit, this.batch);
  final Product product;
  final String unit;
  final Batch batch;
}

final class BatchAlertPage {
  const BatchAlertPage(
    this.items, {
    required this.totalBatches,
    required this.totalProducts,
  });
  final List<BatchAlert> items;
  final int totalBatches, totalProducts;
}

/// A consistent database snapshot, bounded to a short selection from each kind
/// of issue so low/zero stock remains visible alongside expiry problems.
final class InventoryDashboard {
  const InventoryDashboard({
    required this.today,
    required this.overview,
    required this.expiryAttention,
    required this.stockAttention,
  });
  final BusinessDate today;
  final InventoryOverview overview;
  final List<BatchAlert> expiryAttention;
  final List<InventoryItem> stockAttention;
}

final class InventoryOverview {
  const InventoryOverview({
    this.products = 0,
    this.batches = 0,
    this.lowStock = 0,
    this.outOfStock = 0,
    this.expiringBatches = 0,
    this.expiredBatches = 0,
    this.expiresTodayBatches = 0,
  });
  final int products,
      batches,
      lowStock,
      outOfStock,
      expiringBatches,
      expiredBatches,
      expiresTodayBatches;
  bool get hasAlerts =>
      lowStock > 0 ||
      outOfStock > 0 ||
      expiringBatches > 0 ||
      expiredBatches > 0;
}
