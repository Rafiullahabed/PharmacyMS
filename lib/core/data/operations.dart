import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../domain/dates.dart';
import '../domain/entity.dart';
import '../domain/validation.dart';

/// Must run inside the mutation transaction. Exact retries reconcile a durable receipt.
Future<String> inventoryOperation(
  DatabaseExecutor tx,
  AppClock clock,
  String operationId,
  String kind,
  DataRow payload,
  Future<String> Function() apply,
) async {
  final encoded = jsonEncode(payload);
  final old = await tx.query(
    'inventory_operations',
    where: 'id=?',
    whereArgs: [operationId],
  );
  if (old.isNotEmpty) {
    if (old.single['kind'] != kind || old.single['payload'] != encoded) {
      throw const ValidationException(
        'This save was already used for different values. Reopen the form before saving again.',
      );
    }
    return old.single['entity_id'] as String;
  }
  final now = clock.nowUtc().toUtc();
  final meta = EntityMeta(id: operationId, createdAt: now, updatedAt: now);
  final entityId = await apply();
  await tx.insert('inventory_operations', {
    ...meta.toRow(),
    'kind': kind,
    'payload': encoded,
    'entity_id': entityId,
  });
  return entityId;
}
