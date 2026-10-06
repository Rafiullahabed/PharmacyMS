import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/data/repository_support.dart';
import '../../../core/domain/dates.dart';
import '../../../core/domain/entity.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/validation.dart';
import '../domain/debt.dart';

class SqliteDebtRepository implements DebtRepository {
  SqliteDebtRepository(this.db, this.clock);
  final Database db;
  final AppClock clock;
  String _phoneKey(String? value) => phoneSearchKey(value ?? '');

  Future<DataRow> _operation(
    DatabaseExecutor tx,
    String? id,
    String kind,
    DataRow payload,
    Future<DataRow> Function() apply,
  ) async {
    if (id == null) return apply();
    final encoded = jsonEncode(payload);
    final old = await tx.query(
      'debt_operations',
      where: 'id=?',
      whereArgs: [id],
    );
    if (old.isNotEmpty) {
      if (old.single['kind'] != kind || old.single['payload'] != encoded) {
        throw const ValidationException(
          'This operation was already used for different values. Reopen the form before saving again.',
        );
      }
      return Map<String, Object?>.from(
        jsonDecode(old.single['result'] as String) as Map,
      );
    }
    final result = await apply(), now = clock.nowUtc().toUtc();
    await tx.insert('debt_operations', {
      ...EntityMeta(id: id, createdAt: now, updatedAt: now).toRow(),
      'kind': kind,
      'payload': encoded,
      'result': jsonEncode(result),
    });
    return result;
  }

  Future<void> _active(DatabaseExecutor tx, String id) async {
    if ((await requireRow(tx, 'customers', id))['archived'] == 1) {
      throw const ValidationException(
        'Restore this customer before changing the ledger.',
      );
    }
  }

  Customer _customer(DataRow r) => Customer(
    meta: EntityMeta.fromRow(r),
    name: r['name'] as String,
    phone: r['phone'] as String?,
    note: r['note'] as String?,
    archived: r['archived'] == 1,
  );
  LedgerEntry _entry(DataRow r) => LedgerEntry(
    meta: EntityMeta.fromRow(r),
    customerId: r['customer_id'] as String,
    date: BusinessDate.parse(r['business_date'] as String),
    sequence: r['sequence'] as int,
    kind: LedgerKind.values.byName(r['kind'] as String),
    amount: Money.fromMinor(r['amount_minor'] as int),
    description: r['description'] as String,
  );
  @override
  Future<Customer> createCustomer({
    required String name,
    String? phone,
    String? note,
  }) => saveCustomer(
    operationId: const Uuid().v4(),
    name: name,
    phone: phone,
    note: note,
  );

  @override
  Future<Customer> customer(String id) async =>
      _customer(await requireRow(db, 'customers', id));
  @override
  Future<Customer> saveCustomer({
    required String operationId,
    String? id,
    required String name,
    String? phone,
    String? note,
  }) => db.transaction(
    (tx) async => _customer(
      await _operation(
        tx,
        operationId,
        'customer',
        {'id': id, 'name': name, 'phone': phone, 'note': note},
        () async {
          final previous = id == null
              ? null
              : await requireRow(tx, 'customers', id);
          final cleaned = requiredText(name, 'Name');
          final row = {
            ...(previous ?? EntityMeta.create(clock).toRow()),
            'name': cleaned,
            'name_key': searchKey(cleaned),
            'phone': phone,
            'phone_key': _phoneKey(phone),
            'note': note,
            'archived': previous?['archived'] ?? 0,
            if (previous != null) 'updated_at': updateTime(previous, clock),
          };
          if (id == null) {
            await tx.insert('customers', row);
          } else {
            await tx.update('customers', row, where: 'id=?', whereArgs: [id]);
          }
          return row;
        },
      ),
    ),
  );
  @override
  Future<List<Customer>> similarCustomers(
    String name, {
    String? excludingId,
  }) async => (await db.query(
    'customers',
    where: 'name_key=? AND id!=?',
    whereArgs: [searchKey(name), excludingId ?? ''],
    orderBy: 'archived,name_key,id',
    limit: 10,
  )).map(_customer).toList();

  static const _balances =
      "SELECT c.*,coalesce(sum(CASE WHEN l.kind='debt' THEN l.amount_minor ELSE -l.amount_minor END),0) AS balance,max(l.business_date) AS latest FROM customers c LEFT JOIN ledger_entries l ON l.customer_id=c.id GROUP BY c.id";
  @override
  Future<CustomerPage> searchCustomers({
    String search = '',
    CustomerFilter filter = CustomerFilter.all,
    bool archived = false,
    int limit = 50,
    int offset = 0,
  }) => db.transaction((tx) async {
    validatePage(limit, offset);
    final condition = switch (filter) {
      CustomerFilter.all => '1=1',
      CustomerFilter.outstanding => 'balance>0',
      CustomerFilter.settled => 'balance=0',
    };
    final query =
        "FROM ($_balances) WHERE archived=? AND (?='' OR instr(name_key,?)>0 OR (?!='' AND instr(phone_key,?)>0)) AND $condition";
    final args = [
      archived ? 1 : 0,
      search.trim(),
      searchKey(search),
      _phoneKey(search),
      _phoneKey(search),
    ];
    final count = Sqflite.firstIntValue(
      await tx.rawQuery('SELECT count(*) $query', args),
    )!;
    final rows = await tx.rawQuery(
      'SELECT * $query ORDER BY name_key,id LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    final all = await tx.rawQuery(
      'SELECT balance FROM ($_balances) WHERE archived=0',
    );
    final total = all.fold(
      BigInt.zero,
      (value, row) => value + BigInt.from(row['balance'] as int),
    );
    return CustomerPage(
      rows
          .map(
            (r) => CustomerBalance(
              _customer(r),
              Money.fromMinor(r['balance'] as int),
              r['latest'] == null
                  ? null
                  : BusinessDate.parse(r['latest'] as String),
            ),
          )
          .toList(),
      count,
      all.length,
      total,
    );
  });
  @override
  Future<List<String>> productNames(String search) async => (await db.rawQuery(
    'SELECT name FROM products WHERE archived=0 AND instr(name_key,?)>0 GROUP BY name ORDER BY name_key,name LIMIT 20',
    [searchKey(search)],
  )).map((r) => r['name'] as String).toList();
  @override
  Future<LedgerEntry?> entry(String id) async {
    final rows = await db.query(
      'ledger_entries',
      where: 'id=?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : _entry(rows.single);
  }

  @override
  Future<CustomerLedger> history(
    String customerId, {
    int limit = 50,
    int offset = 0,
  }) => db.transaction((tx) async {
    validatePage(limit, offset);
    final customer = _customer(await requireRow(tx, 'customers', customerId));
    final totals = (await tx.rawQuery(
      "SELECT count(*) AS n,coalesce(sum(CASE WHEN kind='debt' THEN amount_minor ELSE -amount_minor END),0) AS balance FROM ledger_entries WHERE customer_id=?",
      [customerId],
    )).single;
    final rows = await tx.query(
      'ledger_entries',
      where: 'customer_id=?',
      whereArgs: [customerId],
      orderBy: 'business_date DESC,sequence DESC',
      limit: limit,
      offset: offset,
    );
    var running = Money.fromMinor(0);
    if (rows.isNotEmpty) {
      final oldest = rows.last;
      running = Money.fromMinor(
        Sqflite.firstIntValue(
          await tx.rawQuery(
            "SELECT coalesce(sum(CASE WHEN kind='debt' THEN amount_minor ELSE -amount_minor END),0) FROM ledger_entries WHERE customer_id=? AND (business_date<? OR (business_date=? AND sequence<?))",
            [
              customerId,
              oldest['business_date'],
              oldest['business_date'],
              oldest['sequence'],
            ],
          ),
        )!,
      );
    }
    final lines = <LedgerLine>[];
    for (final row in rows.reversed) {
      final entry = _entry(row);
      running = entry.kind == LedgerKind.debt
          ? running + entry.amount
          : running - entry.amount;
      lines.add(LedgerLine(entry, running));
    }
    return CustomerLedger(
      customer,
      Money.fromMinor(totals['balance'] as int),
      lines.reversed.toList(),
      totals['n'] as int,
    );
  });

  @override
  Future<List<Customer>> customers({int limit = 50, int offset = 0}) async {
    validatePage(limit, offset);
    return (await db.query(
      'customers',
      where: 'archived=0',
      orderBy: 'name_key,id',
      limit: limit,
      offset: offset,
    )).map(_customer).toList();
  }

  void _validate(BusinessDate date, Money amount) {
    LedgerDraft(
      date: date,
      kind: LedgerKind.debt,
      amount: amount,
    ).validate(clock);
  }

  /// Revalidate the entire affected chronology inside the write transaction.
  Future<LedgerPreview> _validateLedger(
    DatabaseExecutor tx,
    String customerId, {
    LedgerEntry? replacement,
    String? removeId,
  }) async {
    final rows = await tx.query(
      'ledger_entries',
      where: 'customer_id=?',
      whereArgs: [customerId],
      orderBy: 'business_date,sequence',
    );
    return projectLedger(
      rows.map(_entry).toList(),
      replacement: replacement,
      removeId: removeId,
    );
  }

  @override
  Future<LedgerPreview> preview(
    String customerId, {
    String? entryId,
    LedgerDraft? draft,
    bool deleting = false,
  }) => db.transaction((tx) async {
    await _active(tx, customerId);
    final previous = entryId == null
        ? null
        : _entry(await requireRow(tx, 'ledger_entries', entryId));
    if (previous != null && previous.customerId != customerId) {
      throw const ValidationException(
        'This entry belongs to another customer.',
      );
    }
    if (deleting) {
      if (previous == null) {
        throw const ValidationException('Choose an entry to delete.');
      }
      return _validateLedger(tx, customerId, removeId: entryId);
    }
    if (draft == null) {
      throw const ValidationException(
        'Enter the date and amount to preview the balance.',
      );
    }
    draft.validate(clock);
    final sequence =
        previous?.sequence ??
        (Sqflite.firstIntValue(
              await tx.rawQuery(
                "SELECT value FROM sequence_counters WHERE name='ledger_entries'",
              ),
            )! +
            1);
    return _validateLedger(
      tx,
      customerId,
      replacement: LedgerEntry(
        meta: previous?.meta ?? EntityMeta.create(clock),
        customerId: customerId,
        date: draft.date,
        sequence: sequence,
        kind: draft.kind,
        amount: draft.amount,
        description: draft.description,
      ),
    );
  });

  @override
  Future<LedgerEntry> addEntry({
    required String operationId,
    required String customerId,
    required BusinessDate date,
    required LedgerKind kind,
    required Money amount,
    String description = '',
  }) async {
    return db.transaction((tx) async {
      final deleted = await tx.query(
        'correction_audits',
        columns: ['id'],
        where: "entry_id=? AND action='delete'",
        whereArgs: [operationId],
        limit: 1,
      );
      if (deleted.isNotEmpty) {
        throw const ValidationException(
          'This entry was deleted. Start a new entry instead of retrying it.',
        );
      }
      return _entry(
        await _operation(
          tx,
          operationId,
          'add',
          {
            'customer_id': customerId,
            'date': date.iso,
            'kind': kind.name,
            'amount': amount.minor,
            'description': description,
          },
          () async {
            _validate(date, amount);
            final previous = await tx.query(
              'ledger_entries',
              where: 'id=?',
              whereArgs: [operationId],
            );
            if (previous.isNotEmpty) {
              final entry = _entry(previous.single);
              if (entry.customerId != customerId ||
                  entry.date != date ||
                  entry.kind != kind ||
                  entry.amount != amount ||
                  entry.description != description) {
                throw const ValidationException(
                  'This operation ID was already used for another entry.',
                );
              }
              return previous.single;
            }
            await _active(tx, customerId);
            final now = clock.nowUtc().toUtc();
            final row = {
              ...EntityMeta(
                id: operationId,
                createdAt: now,
                updatedAt: now,
              ).toRow(),
              'customer_id': customerId,
              'business_date': date.iso,
              'sequence': await nextSequence(tx, 'ledger_entries'),
              'kind': kind.name,
              'amount_minor': amount.minor,
              'description': description,
            };
            await _validateLedger(tx, customerId, replacement: _entry(row));
            await tx.insert('ledger_entries', row);
            return row;
          },
        ),
      );
    });
  }

  Future<void> _audit(
    DatabaseExecutor tx,
    DataRow previous,
    DataRow? next,
    String reason,
  ) => tx.insert('correction_audits', {
    ...EntityMeta.create(clock).toRow(),
    'entry_id': previous['id'],
    'customer_id': previous['customer_id'],
    'action': next == null ? 'delete' : 'edit',
    'previous_value': jsonEncode(previous),
    'new_value': next == null ? null : jsonEncode(next),
    'reason': requiredText(reason, 'Correction reason'),
  });
  @override
  Future<LedgerEntry> editEntry({
    String? operationId,
    required String id,
    required BusinessDate date,
    required LedgerKind kind,
    required Money amount,
    required String description,
    required String reason,
  }) async {
    return db.transaction(
      (tx) async => _entry(
        await _operation(
          tx,
          operationId,
          'edit',
          {
            'id': id,
            'date': date.iso,
            'kind': kind.name,
            'amount': amount.minor,
            'description': description,
            'reason': reason,
          },
          () async {
            _validate(date, amount);
            final previous = await requireRow(tx, 'ledger_entries', id);
            await _active(tx, previous['customer_id'] as String);
            final next = {
              ...previous,
              'business_date': date.iso,
              'kind': kind.name,
              'amount_minor': amount.minor,
              'description': description,
              'updated_at': updateTime(previous, clock),
            };
            await _validateLedger(
              tx,
              previous['customer_id'] as String,
              replacement: _entry(next),
            );
            await tx.update(
              'ledger_entries',
              next,
              where: 'id=?',
              whereArgs: [id],
            );
            await _audit(tx, previous, next, reason);
            return next;
          },
        ),
      ),
    );
  }

  @override
  Future<void> deleteEntry(
    String id, {
    required String reason,
    String? operationId,
  }) => db.transaction((tx) async {
    await _operation(
      tx,
      operationId,
      'delete',
      {'id': id, 'reason': reason},
      () async {
        final previous = await requireRow(tx, 'ledger_entries', id);
        await _active(tx, previous['customer_id'] as String);
        await _validateLedger(
          tx,
          previous['customer_id'] as String,
          removeId: id,
        );
        await tx.delete('ledger_entries', where: 'id=?', whereArgs: [id]);
        await _audit(tx, previous, null, reason);
        return {'id': id};
      },
    );
  });
  @override
  Future<List<LedgerEntry>> ledger(
    String customerId, {
    int limit = 50,
    int offset = 0,
  }) async {
    validatePage(limit, offset);
    return (await db.query(
      'ledger_entries',
      where: 'customer_id=?',
      whereArgs: [customerId],
      orderBy: 'business_date,sequence',
      limit: limit,
      offset: offset,
    )).map(_entry).toList();
  }

  @override
  Future<List<CorrectionAudit>> corrections(
    String customerId, {
    int limit = 50,
    int offset = 0,
  }) async {
    validatePage(limit, offset);
    return (await db.query(
          'correction_audits',
          where: 'customer_id=?',
          whereArgs: [customerId],
          orderBy: 'created_at,id',
          limit: limit,
          offset: offset,
        ))
        .map(
          (r) => CorrectionAudit(
            meta: EntityMeta.fromRow(r),
            entryId: r['entry_id'] as String,
            customerId: r['customer_id'] as String,
            action: r['action'] as String,
            reason: r['reason'] as String,
            previous: Map<String, Object?>.from(
              jsonDecode(r['previous_value'] as String) as Map,
            ),
            next: r['new_value'] == null
                ? null
                : Map<String, Object?>.from(
                    jsonDecode(r['new_value'] as String) as Map,
                  ),
          ),
        )
        .toList();
  }

  @override
  Future<Money> balance(String customerId) async => Money.fromMinor(
    Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT coalesce(sum(CASE WHEN kind='debt' THEN amount_minor ELSE -amount_minor END),0) FROM ledger_entries WHERE customer_id=?",
        [customerId],
      ),
    )!,
  );
  @override
  Future<void> archiveCustomer(
    String id, {
    required bool archived,
    String? operationId,
  }) => db.transaction((tx) async {
    await _operation(
      tx,
      operationId,
      'archive',
      {'id': id, 'archived': archived},
      () async {
        final row = await requireRow(tx, 'customers', id);
        if (archived && (await _validateLedger(tx, id)).after.minor != 0) {
          throw const ValidationException(
            'Settle the outstanding balance before archiving this customer.',
          );
        }
        await tx.update(
          'customers',
          {'archived': archived ? 1 : 0, 'updated_at': updateTime(row, clock)},
          where: 'id=?',
          whereArgs: [id],
        );
        return {'id': id};
      },
    );
  });
}
