import 'package:sqflite/sqflite.dart' hide Batch;
import '../../../core/domain/dates.dart';
import '../../../core/domain/entity.dart';
import '../../../core/domain/validation.dart';
import '../../../core/data/repository_support.dart';
import '../domain/inventory.dart';

/// SQL projections of the domain policy, checked against InventoryItem and
/// BatchInventoryStatus in contract tests. One predicate serves counts and pages.
class InventoryQueries {
  InventoryQueries(this.db, this.productFromRow);
  final Database db;
  final Product Function(DataRow) productFromRow;
  static const _activeBatch = 'b.archived=0 AND p.archived=0';
  static const _stockAlert =
      'usable=0 OR (minimum_stock>0 AND usable<minimum_stock)';
  static const _productColumns = [
    'id',
    'created_at',
    'updated_at',
    'name',
    'unit_id',
    'minimum_stock',
    'warning_days',
    'category',
    'notes',
    'archived',
  ];
  static const _dateColumns = ['calendar', 'year', 'month', 'day', 'precision'];

  String _expiry(
    InventoryFilter filter,
    BusinessDate today,
  ) => switch (filter) {
    InventoryFilter.expired => "e.canonical_end<'${today.iso}'",
    InventoryFilter.expiresToday => "e.canonical_end='${today.iso}'",
    InventoryFilter.expiringSoon =>
      "e.canonical_end>='${today.iso}' AND julianday(e.canonical_end)-julianday('${today.iso}')<=p.warning_days",
    _ => throw const ValidationException('Choose an expiry filter.'),
  };
  String _aggregate(BusinessDate today) =>
      '''SELECT p.*,u.name AS unit_name,
    coalesce(s.physical,0) AS physical,coalesce(s.usable,0) AS usable,
    coalesce(s.expired,0) AS expired_count,coalesce(s.expiring,0) AS expiring_count,
    coalesce(s.expires_today,0) AS today_count,coalesce(s.batch_count,0) AS batch_count
    FROM products p JOIN units u ON u.id=p.unit_id LEFT JOIN (
      SELECT b.product_id,count(*) AS batch_count,sum(b.quantity) AS physical,
      sum(CASE WHEN e.canonical_end IS NULL OR NOT (${_expiry(InventoryFilter.expired, today)}) THEN b.quantity ELSE 0 END) AS usable,
      sum(CASE WHEN b.quantity>0 AND ${_expiry(InventoryFilter.expired, today)} THEN 1 ELSE 0 END) AS expired,
      sum(CASE WHEN b.quantity>0 AND ${_expiry(InventoryFilter.expiringSoon, today)} THEN 1 ELSE 0 END) AS expiring,
      sum(CASE WHEN b.quantity>0 AND ${_expiry(InventoryFilter.expiresToday, today)} THEN 1 ELSE 0 END) AS expires_today
      FROM batches b JOIN products p ON p.id=b.product_id LEFT JOIN date_specs e ON e.id=b.expiry_spec_id
      WHERE $_activeBatch GROUP BY b.product_id) s ON s.product_id=p.id''';
  InventoryItem _item(DataRow row) => InventoryItem(
    product: productFromRow(row),
    unit: row['unit_name'] as String,
    physical: row['physical'] as int,
    usable: row['usable'] as int,
    expiringBatches: row['expiring_count'] as int,
    expiredBatches: row['expired_count'] as int,
    expiresTodayBatches: row['today_count'] as int,
  );
  String _filter(InventoryFilter filter) => switch (filter) {
    InventoryFilter.all => '1=1',
    InventoryFilter.lowStock =>
      'archived=0 AND minimum_stock>0 AND usable<minimum_stock',
    InventoryFilter.outOfStock => 'archived=0 AND usable=0',
    InventoryFilter.expiringSoon => 'archived=0 AND expiring_count>0',
    InventoryFilter.expired => 'archived=0 AND expired_count>0',
    InventoryFilter.expiresToday => 'archived=0 AND today_count>0',
    InventoryFilter.needsAttention =>
      'archived=0 AND ($_stockAlert OR expiring_count>0 OR expired_count>0)',
  };
  Future<InventoryPage> inventory({
    required BusinessDate today,
    String search = '',
    InventoryFilter filter = InventoryFilter.all,
    bool archived = false,
    int limit = 50,
    int offset = 0,
  }) => db.transaction((tx) async {
    validatePage(limit, offset);
    final query =
        'FROM (${_aggregate(today)}) WHERE archived=? AND instr(name_key,?)>0 AND ${_filter(filter)}';
    final args = [archived ? 1 : 0, searchKey(search)];
    final total = Sqflite.firstIntValue(
      await tx.rawQuery('SELECT count(*) $query', args),
    )!;
    final rows = await tx.rawQuery(
      'SELECT * $query ORDER BY name_key,id LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return InventoryPage(rows.map(_item).toList(), total);
  });

  DateSpec? _date(DataRow row, String prefix) =>
      row['${prefix}_calendar'] == null
      ? null
      : DateSpec.fromMap({
          for (final key in _dateColumns) key: row['${prefix}_$key'],
        });
  BatchAlert _alert(DataRow row) => BatchAlert(
    productFromRow({for (final key in _productColumns) key: row['owner_$key']}),
    row['unit_name'] as String,
    Batch(
      meta: EntityMeta.fromRow(row),
      productId: row['product_id'] as String,
      label: row['label'] as String,
      receivedDate: BusinessDate.parse(row['received_date'] as String),
      quantity: row['quantity'] as int,
      production: _date(row, 'production'),
      expiry: _date(row, 'expiry'),
      notes: row['notes'] as String?,
      archived: row['archived'] == 1,
    ),
  );
  Future<BatchAlertPage> alertPage({
    required BusinessDate today,
    required InventoryFilter filter,
    String search = '',
    int limit = 50,
    int offset = 0,
  }) => db.transaction(
    (tx) => _alertPage(
      tx,
      today,
      filter,
      search: search,
      limit: limit,
      offset: offset,
    ),
  );
  Future<BatchAlertPage> _alertPage(
    DatabaseExecutor tx,
    BusinessDate today,
    InventoryFilter filter, {
    String search = '',
    int limit = 50,
    int offset = 0,
  }) async {
    validatePage(limit, offset);
    final from = '''FROM batches b JOIN products p ON p.id=b.product_id
      JOIN units u ON u.id=p.unit_id JOIN date_specs e ON e.id=b.expiry_spec_id
      LEFT JOIN date_specs d ON d.id=b.production_spec_id
      WHERE $_activeBatch AND b.quantity>0 AND ${_expiry(filter, today)} AND instr(p.name_key,?)>0''';
    final args = [searchKey(search)];
    final counts = (await tx.rawQuery(
      'SELECT count(*) AS batches,count(DISTINCT p.id) AS products $from',
      args,
    )).single;
    final columns = [
      'b.*',
      'u.name AS unit_name',
      for (final key in _productColumns) 'p.$key AS owner_$key',
      for (final key in _dateColumns) 'e.$key AS expiry_$key',
      for (final key in _dateColumns) 'd.$key AS production_$key',
    ].join(',');
    final rows = await tx.rawQuery(
      'SELECT $columns $from ORDER BY e.canonical_end,p.name_key,b.id LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return BatchAlertPage(
      rows.map(_alert).toList(),
      totalBatches: counts['batches'] as int,
      totalProducts: counts['products'] as int,
    );
  }

  Future<InventoryOverview> overview(BusinessDate today) =>
      db.transaction((tx) => _overview(tx, today));
  Future<InventoryOverview> _overview(
    DatabaseExecutor tx,
    BusinessDate today,
  ) async {
    final row = (await tx.rawQuery(
      '''SELECT count(*) AS products,coalesce(sum(batch_count),0) AS batches,
      coalesce(sum(minimum_stock>0 AND usable<minimum_stock),0) AS low_stock,
      coalesce(sum(usable=0),0) AS out_of_stock,coalesce(sum(expiring_count),0) AS expiring,
      coalesce(sum(expired_count),0) AS expired,coalesce(sum(today_count),0) AS expires_today
      FROM (${_aggregate(today)}) WHERE archived=0''',
    )).single;
    return InventoryOverview(
      products: row['products'] as int,
      batches: row['batches'] as int,
      lowStock: row['low_stock'] as int,
      outOfStock: row['out_of_stock'] as int,
      expiringBatches: row['expiring'] as int,
      expiredBatches: row['expired'] as int,
      expiresTodayBatches: row['expires_today'] as int,
    );
  }

  Future<InventoryDashboard> dashboard(BusinessDate today) =>
      db.transaction((tx) async {
        final overview = await _overview(tx, today);
        final expired = await _alertPage(
          tx,
          today,
          InventoryFilter.expired,
          limit: 2,
        );
        final soon = await _alertPage(
          tx,
          today,
          InventoryFilter.expiringSoon,
          limit: 2,
        );
        final stock = await tx.rawQuery(
          '''SELECT * FROM (${_aggregate(today)})
      WHERE archived=0 AND ($_stockAlert) ORDER BY (usable=0) DESC,name_key,id LIMIT 2''',
        );
        return InventoryDashboard(
          today: today,
          overview: overview,
          expiryAttention: [...expired.items, ...soon.items],
          stockAttention: stock.map(_item).toList(),
        );
      });
}
