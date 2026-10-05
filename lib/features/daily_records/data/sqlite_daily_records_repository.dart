import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../core/data/repository_support.dart';
import '../../../core/domain/dates.dart';
import '../../../core/domain/entity.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/validation.dart';
import '../domain/daily_record.dart';
import '../domain/daily_report.dart';

class SqliteDailyRecordsRepository implements DailyRecordsRepository {
  SqliteDailyRecordsRepository(this.db, this.clock);
  final Database db;
  final AppClock clock;
  DailyRecord _record(DataRow r) => DailyRecord(
    meta: EntityMeta.fromRow(r),
    date: BusinessDate.parse(r['business_date'] as String),
    sales: Money.fromMinor(r['sales_minor'] as int),
    profit: Money.fromMinor(r['profit_minor'] as int),
    note: r['note'] as String?,
  );
  @override
  Future<DailyRecord?> onDate(BusinessDate date) async {
    final rows = await db.query(
      'daily_records',
      where: 'business_date=?',
      whereArgs: [date.iso],
    );
    return rows.isEmpty ? null : _record(rows.single);
  }

  @override
  Future<DailyRecord?> byId(String id) async {
    final rows = await db.query(
      'daily_records',
      where: 'id=?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : _record(rows.single);
  }

  @override
  Future<DailyReport> report(ReportRange range) => db.transaction((tx) async {
    Future<List<DailyRecord>> read(ReportRange? period) async => period == null
        ? []
        : (await tx.query(
            'daily_records',
            where: 'business_date>=? AND business_date<=?',
            whereArgs: [period.start.iso, period.end.iso],
            orderBy: 'business_date DESC',
          )).map(_record).toList();
    return DailyReport(
      range: range,
      records: await read(range),
      previousRecords: await read(range.previous),
    );
  });

  /// A lost acknowledgment can be retried even after reopening, without
  /// reapplying an old edit or resurrecting a subsequently deleted record.
  Future<DataRow> _operation(
    DatabaseExecutor tx,
    String? id,
    String kind,
    DataRow payload,
    Future<DataRow> Function() apply,
  ) async {
    if (id == null) return apply();
    final encoded = jsonEncode(payload);
    final rows = await tx.query(
      'daily_operations',
      where: 'id=?',
      whereArgs: [id],
    );
    if (rows.isNotEmpty) {
      if (rows.single['kind'] != kind || rows.single['payload'] != encoded) {
        throw const ValidationException(
          'This save was already used for different values. Reopen the form before saving again.',
        );
      }
      return Map<String, Object?>.from(
        jsonDecode(rows.single['result'] as String) as Map,
      );
    }
    final result = await apply(), now = clock.nowUtc();
    await tx.insert('daily_operations', {
      ...EntityMeta(id: id, createdAt: now, updatedAt: now).toRow(),
      'kind': kind,
      'payload': encoded,
      'result': jsonEncode(result),
    });
    return result;
  }

  @override
  Future<List<DailyRecord>> records({int limit = 50, int offset = 0}) async {
    validatePage(limit, offset);
    return (await db.query(
      'daily_records',
      orderBy: 'business_date DESC',
      limit: limit,
      offset: offset,
    )).map(_record).toList();
  }

  @override
  Future<DailyRecord> save({
    String? operationId,
    String? id,
    required BusinessDate date,
    required Money sales,
    required Money profit,
    String? note,
  }) async {
    return db.transaction(
      (tx) async => _record(
        await _operation(
          tx,
          operationId,
          'save',
          {
            'id': id,
            'date': date.iso,
            'sales': sales.minor,
            'profit': profit.minor,
            'note': note,
          },
          () async {
            validateNotFuture(date, clock);
            if (sales.minor < 0) {
              throw const ValidationException('Sales must be nonnegative.');
            }
            final conflicts = await tx.query(
              'daily_records',
              where: 'business_date=?',
              whereArgs: [date.iso],
            );
            if (conflicts.isNotEmpty && conflicts.single['id'] != id) {
              throw const ValidationException(
                'A record already exists for this date. Open it to edit.',
              );
            }
            final previous = id == null
                ? null
                : await requireRow(tx, 'daily_records', id);
            final row = {
              ...(previous ?? EntityMeta.create(clock).toRow()),
              'business_date': date.iso,
              'sales_minor': sales.minor,
              'profit_minor': profit.minor,
              'note': note,
              if (previous != null) 'updated_at': updateTime(previous, clock),
            };
            if (id == null) {
              await tx.insert('daily_records', row);
            } else {
              await tx.update(
                'daily_records',
                row,
                where: 'id=?',
                whereArgs: [id],
              );
            }
            return row;
          },
        ),
      ),
    );
  }

  @override
  Future<void> delete(String id, {String? operationId}) =>
      db.transaction((tx) async {
        await _operation(tx, operationId, 'delete', {'id': id}, () async {
          await tx.delete('daily_records', where: 'id=?', whereArgs: [id]);
          return {'id': id};
        });
      });
}
