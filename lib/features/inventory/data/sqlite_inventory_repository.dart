import 'package:sqflite/sqflite.dart' hide Batch;
import 'package:uuid/uuid.dart';
import '../../../core/data/repository_support.dart';
import '../../../core/data/operations.dart';
import '../../../core/domain/dates.dart';
import '../../../core/domain/entity.dart';
import '../../../core/domain/validation.dart';
import '../domain/inventory.dart';
import 'inventory_queries.dart';

class SqliteInventoryRepository implements InventoryRepository {
  SqliteInventoryRepository(this.db, this.clock);
  final Database db;
  final AppClock clock;

  Product _product(DataRow r) => Product(
    meta: EntityMeta.fromRow(r),
    name: r['name'] as String,
    unitId: r['unit_id'] as String,
    minimumStock: r['minimum_stock'] as int,
    warningDays: r['warning_days'] as int,
    category: r['category'] as String?,
    notes: r['notes'] as String?,
    archived: r['archived'] == 1,
  );
  @override
  Future<List<Product>> products({int limit = 50, int offset = 0}) async {
    validatePage(limit, offset);
    return (await db.query(
      'products',
      where: 'archived=0',
      orderBy: 'name_key,id',
      limit: limit,
      offset: offset,
    )).map(_product).toList();
  }

  @override
  Future<Product> createProduct({
    required String name,
    required String unitId,
    int minimumStock = 0,
    int warningDays = 30,
    String? category,
    String? notes,
  }) async {
    return saveProduct(
      operationId: const Uuid().v4(),
      draft: ProductDraft(
        name: name,
        unitId: unitId,
        minimumStock: minimumStock,
        warningDays: warningDays,
        category: category,
        notes: notes,
      ),
    );
  }

  Future<String?> _saveDate(DatabaseExecutor tx, DateSpec? spec) async {
    if (spec == null) return null;
    final id = const Uuid().v4();
    await tx.insert('date_specs', {
      'id': id,
      ...spec.toMap(),
      'canonical_start': spec.range.start.iso,
      'canonical_end': spec.range.end.iso,
    });
    return id;
  }

  Future<DateSpec?> _date(DatabaseExecutor tx, Object? id) async => id == null
      ? null
      : DateSpec.fromMap(await requireRow(tx, 'date_specs', id as String));
  Future<Batch> _batch(DatabaseExecutor tx, DataRow r) async => Batch(
    meta: EntityMeta.fromRow(r),
    productId: r['product_id'] as String,
    label: r['label'] as String,
    receivedDate: BusinessDate.parse(r['received_date'] as String),
    quantity: r['quantity'] as int,
    production: await _date(tx, r['production_spec_id']),
    expiry: await _date(tx, r['expiry_spec_id']),
    notes: r['notes'] as String?,
    archived: r['archived'] == 1,
  );
  @override
  Future<List<Batch>> batches(String productId) async {
    final rows = await db.query(
      'batches',
      where: 'product_id=?',
      whereArgs: [productId],
      orderBy: 'received_date,id',
    );
    return Future.wait(rows.map((r) => _batch(db, r)));
  }

  @override
  Future<Batch> createBatch({
    required String productId,
    required BusinessDate receivedDate,
    required int openingQuantity,
    String? label,
    DateSpec? production,
    DateSpec? expiry,
    String? notes,
  }) async {
    return saveBatch(
      operationId: const Uuid().v4(),
      productId: productId,
      draft: BatchDraft(
        receivedDate: receivedDate,
        quantity: openingQuantity,
        label: label,
        production: production,
        expiry: expiry,
        notes: notes,
      ),
    );
  }

  StockMovement _movement(DataRow r) => StockMovement(
    meta: EntityMeta.fromRow(r),
    batchId: r['batch_id'] as String,
    sequence: r['sequence'] as int,
    kind: MovementKind.values.byName(r['kind'] as String),
    delta: r['delta'] as int,
    resultingQuantity: r['resulting_quantity'] as int,
    reversalOf: r['reversal_of'] as String?,
    note: r['note'] as String?,
  );
  Future<StockMovement> _move(
    DatabaseExecutor tx, {
    required String operationId,
    required String batchId,
    required int delta,
    required MovementKind kind,
    String? reversalOf,
    String? note,
  }) async {
    wholeQuantity('${delta.abs()}', positive: true);
    final existing = await tx.query(
      'stock_movements',
      where: 'id=?',
      whereArgs: [operationId],
    );
    if (existing.isNotEmpty) {
      final found = _movement(existing.single);
      if (found.batchId != batchId ||
          found.delta != delta ||
          found.kind != kind ||
          found.reversalOf != reversalOf ||
          found.note != note) {
        throw const ValidationException(
          'This operation ID was already used for another change.',
        );
      }
      return found;
    }
    final batch = await requireRow(tx, 'batches', batchId);
    final result = (batch['quantity'] as int) + delta;
    if (result < 0) {
      throw const ValidationException('This batch does not have enough stock.');
    }
    wholeQuantity('$result');
    final now = clock.nowUtc().toUtc();
    final row = {
      ...EntityMeta(id: operationId, createdAt: now, updatedAt: now).toRow(),
      'sequence': await nextSequence(tx, 'stock_movements'),
      'batch_id': batchId,
      'kind': kind.name,
      'delta': delta,
      'resulting_quantity': result,
      'reversal_of': reversalOf,
      'note': note,
    };
    await tx.insert('stock_movements', row);
    return _movement(row);
  }

  @override
  Future<StockMovement> adjust({
    required String operationId,
    required String batchId,
    required int delta,
    String? note,
  }) => db.transaction(
    (tx) => _move(
      tx,
      operationId: operationId,
      batchId: batchId,
      delta: delta,
      kind: delta > 0 ? MovementKind.add : MovementKind.remove,
      note: note,
    ),
  );
  @override
  Future<StockMovement> reverse({
    required String operationId,
    required String movementId,
  }) => db.transaction((tx) async {
    final original = _movement(
      await requireRow(tx, 'stock_movements', movementId),
    );
    if (original.kind == MovementKind.reversal) {
      throw const ValidationException(
        'Correct this batch with a new manual adjustment.',
      );
    }
    return _move(
      tx,
      operationId: operationId,
      batchId: original.batchId,
      delta: -original.delta,
      kind: MovementKind.reversal,
      reversalOf: movementId,
    );
  });
  @override
  Future<List<StockMovement>> movements(
    String batchId, {
    int limit = 50,
    int offset = 0,
  }) async {
    validatePage(limit, offset);
    return (await db.query(
      'stock_movements',
      where: 'batch_id=?',
      whereArgs: [batchId],
      orderBy: 'sequence DESC',
      limit: limit,
      offset: offset,
    )).map(_movement).toList();
  }

  @override
  Future<Product> product(String id) async =>
      _product(await requireRow(db, 'products', id));
  @override
  Future<Batch> batch(String id) async =>
      _batch(db, await requireRow(db, 'batches', id));
  Future<bool> _hasHistory(
    DatabaseExecutor tx,
    String productId,
  ) async => (await tx.rawQuery(
    'SELECT 1 FROM stock_movements m JOIN batches b ON b.id=m.batch_id WHERE b.product_id=? LIMIT 1',
    [productId],
  )).isNotEmpty;
  @override
  Future<bool> hasStockHistory(String productId) => _hasHistory(db, productId);
  @override
  Future<List<Product>> similarProducts(
    String name, {
    String? excludingId,
  }) async => (await db.query(
    'products',
    where: 'name_key=?${excludingId == null ? '' : ' AND id!=?'}',
    whereArgs: [searchKey(name), ?excludingId],
    limit: 5,
  )).map(_product).toList();

  @override
  Future<Product> saveProduct({
    required String operationId,
    String? productId,
    required ProductDraft draft,
    BatchDraft? initialStock,
  }) async {
    draft.validate();
    if (initialStock != null && productId != null) {
      throw const ValidationException('Add a new batch from item detail.');
    }
    return db.transaction((tx) async {
      final id = await inventoryOperation(
        tx,
        clock,
        operationId,
        'save_product',
        {
          'product_id': productId,
          ...draft.toMap(),
          'initial_stock': initialStock?.toMap(),
        },
        () async {
          final previous = productId == null
              ? null
              : await requireRow(tx, 'products', productId);
          if (previous?['archived'] == 1) {
            throw const ValidationException(
              'Restore this item before editing.',
            );
          }
          final unit = await requireRow(tx, 'units', draft.unitId);
          if (unit['inactive'] == 1 && previous?['unit_id'] != draft.unitId) {
            throw const ValidationException('Choose an active unit.');
          }
          if (previous != null &&
              previous['unit_id'] != draft.unitId &&
              await _hasHistory(tx, productId!)) {
            throw const ValidationException(
              'The unit is locked because this item has stock history. Create a new item for a different counting unit.',
            );
          }
          final row = {
            ...(previous ?? EntityMeta.create(clock).toRow()),
            ...draft.toMap(),
            'name_key': searchKey(draft.name),
            'archived': 0,
            if (previous != null) 'updated_at': updateTime(previous, clock),
          };
          final id = row['id'] as String;
          if (previous == null) {
            await tx.insert('products', row);
          } else {
            await tx.update('products', row, where: 'id=?', whereArgs: [id]);
          }
          if (initialStock != null) {
            await _saveBatch(tx, id, null, initialStock);
          }
          return id;
        },
      );
      return _product(await requireRow(tx, 'products', id));
    });
  }

  Future<String> _saveBatch(
    DatabaseExecutor tx,
    String productId,
    String? batchId,
    BatchDraft draft,
  ) async {
    draft.validate(creating: batchId == null);
    final product = await requireRow(tx, 'products', productId);
    if (product['archived'] == 1) {
      throw const ValidationException(
        'Restore the item before changing its batches.',
      );
    }
    final previous = batchId == null
        ? null
        : await requireRow(tx, 'batches', batchId);
    if (previous != null &&
        (previous['product_id'] != productId || previous['archived'] == 1)) {
      throw const ValidationException('Restore the batch before editing it.');
    }
    final meta = previous == null
        ? EntityMeta.create(clock)
        : EntityMeta.fromRow(previous);
    final row = {
      ...(previous ?? meta.toRow()),
      'product_id': productId,
      'label': draft.label == null || draft.label!.trim().isEmpty
          ? 'Batch ${meta.id.substring(0, 8).toUpperCase()}'
          : draft.label!.trim(),
      'received_date': draft.receivedDate.iso,
      'quantity': previous?['quantity'] ?? 0,
      'production_spec_id': await _saveDate(tx, draft.production),
      'expiry_spec_id': await _saveDate(tx, draft.expiry),
      'expiry_mode': draft.expiry?.precision.name ?? 'none',
      'notes': draft.notes,
      'archived': 0,
      if (previous != null) 'updated_at': updateTime(previous, clock),
    };
    if (previous == null) {
      await tx.insert('batches', row);
      await _move(
        tx,
        operationId: const Uuid().v4(),
        batchId: meta.id,
        delta: draft.quantity,
        kind: MovementKind.opening,
      );
    } else {
      // Metadata writes never set quantity; movement history remains authoritative.
      row.remove('quantity');
      await tx.update('batches', row, where: 'id=?', whereArgs: [meta.id]);
    }
    return meta.id;
  }

  @override
  Future<Batch> saveBatch({
    required String operationId,
    required String productId,
    String? batchId,
    required BatchDraft draft,
  }) => db.transaction((tx) async {
    final id = await inventoryOperation(tx, clock, operationId, 'save_batch', {
      'product_id': productId,
      'batch_id': batchId,
      ...draft.toMap(),
    }, () => _saveBatch(tx, productId, batchId, draft));
    return _batch(tx, await requireRow(tx, 'batches', id));
  });

  @override
  Future<void> deleteUnusedProduct(
    String id, {
    required String operationId,
  }) => db.transaction((tx) async {
    await inventoryOperation(
      tx,
      clock,
      operationId,
      'delete_product',
      {'id': id},
      () async {
        await requireRow(tx, 'products', id);
        if (await _hasHistory(tx, id)) {
          throw const ValidationException(
            'This item has stock history. Archive it when empty to keep that history.',
          );
        }
        final stocked = await tx.query(
          'batches',
          columns: ['id'],
          where: 'product_id=? AND quantity>0',
          whereArgs: [id],
          limit: 1,
        );
        if (stocked.isNotEmpty) {
          throw const ValidationException(
            'An item with physical stock cannot be deleted.',
          );
        }
        await tx.delete('batches', where: 'product_id=?', whereArgs: [id]);
        await tx.delete('products', where: 'id=?', whereArgs: [id]);
        return id;
      },
    );
  });

  @override
  Future<void> archiveProduct(
    String id, {
    required bool archived,
    required String operationId,
  }) => db.transaction((tx) async {
    await inventoryOperation(
      tx,
      clock,
      operationId,
      'archive_product',
      {'id': id, 'archived': archived},
      () async {
        final row = await requireRow(tx, 'products', id);
        if (archived &&
            (await tx.query(
              'batches',
              where: 'product_id=? AND quantity>0',
              whereArgs: [id],
              limit: 1,
            )).isNotEmpty) {
          throw const ValidationException(
            'Remove all physical stock before archiving this item.',
          );
        }
        await tx.update(
          'products',
          {'archived': archived ? 1 : 0, 'updated_at': updateTime(row, clock)},
          where: 'id=?',
          whereArgs: [id],
        );
        return id;
      },
    );
  });
  @override
  Future<void> archiveBatch(
    String id, {
    required bool archived,
    required String operationId,
  }) => db.transaction((tx) async {
    await inventoryOperation(
      tx,
      clock,
      operationId,
      'archive_batch',
      {'id': id, 'archived': archived},
      () async {
        final row = await requireRow(tx, 'batches', id);
        if (archived && row['quantity'] != 0) {
          throw const ValidationException(
            'Remove all stock before archiving this batch.',
          );
        }
        final parent = await requireRow(
          tx,
          'products',
          row['product_id'] as String,
        );
        if (!archived && parent['archived'] == 1) {
          throw const ValidationException(
            'Restore the item before restoring its batch.',
          );
        }
        await tx.update(
          'batches',
          {'archived': archived ? 1 : 0, 'updated_at': updateTime(row, clock)},
          where: 'id=?',
          whereArgs: [id],
        );
        return id;
      },
    );
  });
  @override
  Future<List<StockMovement>> productMovements(
    String productId, {
    int limit = 50,
    int offset = 0,
  }) async {
    validatePage(limit, offset);
    return (await db.rawQuery(
      '''SELECT m.* FROM stock_movements m JOIN batches b ON b.id=m.batch_id
      WHERE b.product_id=? ORDER BY m.sequence DESC LIMIT ? OFFSET ?''',
      [productId, limit, offset],
    )).map(_movement).toList();
  }

  late final _queries = InventoryQueries(db, _product);
  @override
  Future<InventoryPage> inventory({
    required BusinessDate today,
    String search = '',
    InventoryFilter filter = InventoryFilter.all,
    bool archived = false,
    int limit = 50,
    int offset = 0,
  }) => _queries.inventory(
    today: today,
    search: search,
    filter: filter,
    archived: archived,
    limit: limit,
    offset: offset,
  );
  @override
  Future<BatchAlertPage> alertPage({
    required BusinessDate today,
    required InventoryFilter filter,
    String search = '',
    int limit = 50,
    int offset = 0,
  }) => _queries.alertPage(
    today: today,
    filter: filter,
    search: search,
    limit: limit,
    offset: offset,
  );
  @override
  Future<List<BatchAlert>> alerts({
    required BusinessDate today,
    required InventoryFilter filter,
    String search = '',
    int limit = 50,
    int offset = 0,
  }) async => (await alertPage(
    today: today,
    filter: filter,
    search: search,
    limit: limit,
    offset: offset,
  )).items;
  @override
  Future<InventoryOverview> overview(BusinessDate today) =>
      _queries.overview(today);
  @override
  Future<InventoryDashboard> dashboard(BusinessDate today) =>
      _queries.dashboard(today);
}
