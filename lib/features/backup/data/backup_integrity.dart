import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../core/domain/dates.dart';
import '../../../core/domain/entity.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/validation.dart';
import '../../../core/data/schema.dart';
import '../../debtors/domain/debt.dart';
import '../domain/backup.dart';
import 'backup_codec.dart';

void requireBackup(bool valid, String reason) {
  if (!valid) {
    throw BackupException(
      'Invalid backup: $reason. Current data has not been replaced.',
    );
  }
}

Future<BackupTables> readBackupTables(
  DatabaseExecutor db, {
  int schema = schemaVersion,
}) async {
  final result = <String, List<BackupRow>>{};
  var total = 0;
  for (final table in backupTablesFor(schema)) {
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT count(*) FROM $table'),
    )!;
    total += count;
    requireBackup(total <= maxBackupRecords, 'record limit exceeded');
    result[table] = await db.query(
      table,
      orderBy: table == 'sequence_counters'
          ? 'name'
          : table == 'stock_movements' || table == 'ledger_entries'
          ? 'sequence'
          : 'id',
    );
  }
  return result;
}

/// Only trusted schema column names enter SQL. External rows must have exactly
/// those columns and primitive types; INTEGER wire values are canonical strings.
Future<BackupTables> decodeBackupRows(
  DatabaseExecutor db,
  BackupTables portable,
) async {
  final result = <String, List<BackupRow>>{};
  for (final table in portable.entries) {
    final info = await db.rawQuery('PRAGMA table_info(${table.key})');
    final columns = {
      for (final c in info) c['name'] as String: c['type'] as String,
    };
    result[table.key] = [];
    for (final row in table.value) {
      requireBackup(
        row.length == columns.length && row.keys.every(columns.containsKey),
        'unexpected columns in ${table.key}',
      );
      final decoded = <String, Object?>{};
      for (final cell in row.entries) {
        final value = cell.value;
        if (value == null) {
          decoded[cell.key] = null;
          continue;
        }
        requireBackup(value is String, 'invalid value type in ${table.key}');
        final text = value as String;
        requireBackup(text.length <= 1024 * 1024, 'text field exceeds 1 MiB');
        if (columns[cell.key] == 'INTEGER') {
          final number = int.tryParse(text);
          requireBackup(
            RegExp(r'^(0|-?[1-9][0-9]*)$').hasMatch(text) &&
                number != null &&
                '$number' == text,
            'invalid integer in ${table.key}',
          );
          decoded[cell.key] = number;
        } else {
          decoded[cell.key] = text;
        }
      }
      result[table.key]!.add(decoded);
    }
  }
  return result;
}

/// Dropping/reinstating guards is permitted only inside staging or the single
/// atomic replacement transaction. Incoming SQL is never executed.
Future<void> replaceRows(DatabaseExecutor db, BackupTables tables) async {
  final triggers = await db.rawQuery(
    "SELECT name,sql FROM sqlite_master WHERE type='trigger' ORDER BY name",
  );
  for (final t in triggers) {
    await db.execute('DROP TRIGGER "${t['name']}"');
  }
  // Self-referencing reversals must be removed before their original movements.
  await db.delete('stock_movements', where: 'reversal_of IS NOT NULL');
  for (final table in tables.keys.toList().reversed) {
    await db.delete(table);
  }
  for (final table in tables.entries) {
    final rows = [...table.value];
    if (table.key == 'stock_movements') {
      rows.sort(
        (a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int),
      );
    }
    final batch = db.batch();
    for (final row in rows) {
      batch.insert(table.key, row);
    }
    await batch.commit(noResult: true);
  }
  for (final t in triggers) {
    await db.execute(t['sql'] as String);
  }
}

Future<void> validateBackupDatabase(DatabaseExecutor db) async {
  requireBackup(
    (await db.rawQuery(
      'PRAGMA integrity_check',
    )).every((r) => r.values.single == 'ok'),
    'database integrity check failed',
  );
  requireBackup(
    (await db.rawQuery('PRAGMA foreign_key_check')).isEmpty,
    'broken relationships',
  );
  final tables = await readBackupTables(db);
  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  for (final table in tables.entries) {
    for (final row in table.value) {
      if (row.containsKey('created_at')) {
        final created = row['created_at'], updated = row['updated_at'];
        requireBackup(
          created is int &&
              updated is int &&
              created >= 0 &&
              updated >= created &&
              updated <= 8640000000000000,
          'invalid event timestamp',
        );
      }
      requireBackup(
        row.values.every((v) => v is! String || v.length <= 1024 * 1024),
        'text field exceeds the supported size',
      );
    }
  }
  Map<String, BackupRow> indexed(String table) => {
    for (final row in tables[table]!) row['id'] as String: row,
  };
  final dates = <String, DateSpec>{};
  for (final row in tables['date_specs']!) {
    final spec = DateSpec.fromMap(row);
    requireBackup(
      spec.range.start.iso == row['canonical_start'] &&
          spec.range.end.iso == row['canonical_end'],
      'calendar conversion does not match original date',
    );
    dates[row['id'] as String] = spec;
  }
  for (final name in ['units', 'products', 'customers']) {
    for (final row in tables[name]!) {
      requireBackup(
        row['name_key'] == searchKey(row['name'] as String),
        'inconsistent name search key',
      );
      if (name == 'customers') {
        requireBackup(
          row['phone_key'] == phoneSearchKey(row['phone'] as String? ?? ''),
          'inconsistent phone search key',
        );
      }
    }
  }
  final products = indexed('products'),
      batches = indexed('batches'),
      movements = indexed('stock_movements');
  final quantities = <String, int>{}, seen = <String>{};
  var maxMovement = 0, maxLedger = 0;
  for (final row in tables['stock_movements']!) {
    final batch = row['batch_id'] as String, sequence = row['sequence'] as int;
    maxMovement = sequence > maxMovement ? sequence : maxMovement;
    final before = quantities[batch] ?? 0,
        delta = row['delta'] as int,
        after = before + delta;
    requireBackup(
      after >= 0 && after <= maxQuantity && after == row['resulting_quantity'],
      'stock movement history does not reconcile',
    );
    requireBackup(
      row['kind'] != 'opening' || !quantities.containsKey(batch),
      'opening movement is not first',
    );
    if (row['reversal_of'] != null) {
      final original = movements[row['reversal_of']];
      requireBackup(
        original != null &&
            seen.contains(original['id']) &&
            original['kind'] != 'reversal' &&
            original['batch_id'] == batch &&
            original['delta'] == -delta,
        'invalid stock reversal',
      );
    }
    quantities[batch] = after;
    seen.add(row['id'] as String);
  }
  for (final row in batches.values) {
    requireBackup(
      row['quantity'] == (quantities[row['id']] ?? 0),
      'batch quantity does not match stock history',
    );
    requireBackup(
      (row['archived'] != 1 && products[row['product_id']]!['archived'] != 1) ||
          row['quantity'] == 0,
      'archived stock is not empty',
    );
    validateProductionExpiry(
      dates[row['production_spec_id']],
      dates[row['expiry_spec_id']],
    );
    requireBackup(
      row['expiry_mode'] ==
          (dates[row['expiry_spec_id']]?.precision.name ?? 'none'),
      'expiry precision mismatch',
    );
  }
  final entries = indexed('ledger_entries'), customers = indexed('customers');
  LedgerEntry ledger(BackupRow row) {
    requireBackup(
      row.keys.toSet().containsAll([
            'id',
            'customer_id',
            'business_date',
            'sequence',
            'kind',
            'amount_minor',
            'description',
            'created_at',
            'updated_at',
          ]) &&
          row.length == 9,
      'invalid ledger snapshot',
    );
    requireBackup(
      row['id'] is String &&
          uuid.hasMatch(row['id'] as String) &&
          customers.containsKey(row['customer_id']) &&
          row['sequence'] is int &&
          (row['sequence'] as int) > 0 &&
          row['amount_minor'] is int &&
          (row['amount_minor'] as int) > 0 &&
          row['description'] is String &&
          row['created_at'] is int &&
          row['updated_at'] is int &&
          (row['created_at'] as int) >= 0 &&
          (row['updated_at'] as int) >= (row['created_at'] as int) &&
          (row['updated_at'] as int) <= 8640000000000000,
      'invalid ledger snapshot values',
    );
    final e = LedgerEntry(
      meta: EntityMeta.fromRow(row),
      customerId: row['customer_id'] as String,
      date: BusinessDate.parse(row['business_date'] as String),
      sequence: row['sequence'] as int,
      kind: LedgerKind.values.byName(row['kind'] as String),
      amount: Money.fromMinor(row['amount_minor'] as int),
      description: row['description'] as String,
    );
    maxLedger = e.sequence > maxLedger ? e.sequence : maxLedger;
    return e;
  }

  final ledgers = <String, List<LedgerEntry>>{};
  for (final row in entries.values) {
    final e = ledger(row);
    (ledgers[e.customerId] ??= []).add(e);
  }
  for (final customer in customers.values) {
    final balance = projectLedger(ledgers[customer['id']] ?? []).after;
    requireBackup(
      customer['archived'] != 1 || balance.minor == 0,
      'archived customer has outstanding debt',
    );
  }
  for (final row in tables['correction_audits']!) {
    final previous = ledger(
      Map<String, Object?>.from(
        boundedJson(row['previous_value'] as String) as Map,
      ),
    );
    requireBackup(
      previous.meta.id == row['entry_id'] &&
          previous.customerId == row['customer_id'],
      'correction audit identity mismatch',
    );
    if (row['new_value'] != null) {
      final next = ledger(
        Map<String, Object?>.from(
          boundedJson(row['new_value'] as String) as Map,
        ),
      );
      requireBackup(
        previous.meta.id == next.meta.id &&
            previous.customerId == next.customerId &&
            previous.sequence == next.sequence &&
            previous.meta.createdAt == next.meta.createdAt &&
            !next.meta.updatedAt.isBefore(previous.meta.updatedAt),
        'correction changed immutable identity',
      );
    } else {
      requireBackup(
        !entries.containsKey(previous.meta.id),
        'deleted ledger entry still exists',
      );
    }
  }
  final counters = {
    for (final row in tables['sequence_counters']!) row['name']: row['value'],
  };
  requireBackup(
    counters.length == 2 &&
        counters['stock_movements'] is int &&
        counters['ledger_entries'] is int &&
        (counters['stock_movements'] as int) >= maxMovement &&
        (counters['ledger_entries'] as int) >= maxLedger &&
        (counters['stock_movements'] as int) < 9007199254740991 &&
        (counters['ledger_entries'] as int) < 9007199254740991,
    'invalid history sequence counters',
  );
  for (final row in tables['inventory_operations']!) {
    requireBackup(
      uuid.hasMatch(row['entity_id'] as String) &&
          boundedJson(row['payload'] as String) is Map,
      'invalid inventory retry receipt',
    );
  }
  for (final table in ['daily_operations', 'debt_operations']) {
    for (final row in tables[table]!) {
      requireBackup(
        boundedJson(row['payload'] as String) is Map,
        'invalid operation request',
      );
      final result = Map<String, Object?>.from(
        boundedJson(row['result'] as String) as Map,
      );
      requireBackup(
        result['id'] is String && uuid.hasMatch(result['id'] as String),
        'invalid operation result',
      );
      if (table == 'debt_operations' &&
          (row['kind'] == 'add' || row['kind'] == 'edit')) {
        ledger(result);
      }
      if (table == 'daily_operations' && row['kind'] == 'save') {
        BusinessDate.parse(result['business_date'] as String);
        requireBackup(
          Money.fromMinor(result['sales_minor'] as int).minor >= 0,
          'invalid recorded sales receipt',
        );
        Money.fromMinor(result['profit_minor'] as int);
      }
    }
  }
  // Audit/receipt JSON must never contain non-JSON native object values.
  requireBackup(
    (counters['ledger_entries'] as int) >= maxLedger,
    'history counter is below a retained receipt',
  );
  jsonEncode(tables);
}
