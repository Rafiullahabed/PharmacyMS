import 'package:sqflite/sqflite.dart';
import '../../../core/domain/dates.dart';
import '../../../core/domain/entity.dart';
import '../../../core/domain/money.dart';
import '../../daily_records/domain/daily_record.dart';
import '../../inventory/domain/inventory.dart';
import '../domain/home_summary.dart';

class SqliteHomeRepository implements HomeRepository {
  SqliteHomeRepository(this.db);
  final Database db;
  @override
  Future<HomeSummary> read(BusinessDate today) => db.transaction((tx) async {
    Future<int> count(String table, {String where = '1=1'}) async =>
        Sqflite.firstIntValue(
          await tx.rawQuery('SELECT count(*) FROM $table WHERE $where'),
        )!;
    final records = await tx.query(
      'daily_records',
      where: 'business_date=?',
      whereArgs: [today.iso],
    );
    final r = records.isEmpty ? null : records.single;
    final amounts = await tx.rawQuery(
      '''SELECT l.amount_minor,l.kind FROM ledger_entries l
      JOIN customers c ON c.id=l.customer_id WHERE c.archived=0''',
    );
    var sum = BigInt.zero;
    for (final entry in amounts) {
      final value = BigInt.from(entry['amount_minor'] as int);
      sum += entry['kind'] == 'debt' ? value : -value;
    }
    return HomeSummary(
      today: today,
      products: await count('products', where: 'archived=0'),
      batches: await count(
        'batches',
        where:
            'archived=0 AND product_id IN (SELECT id FROM products WHERE archived=0)',
      ),
      dailyRecords: await count('daily_records'),
      customers: await count('customers', where: 'archived=0'),
      outstanding: sum,
      todayRecord: r == null
          ? null
          : DailyRecord(
              meta: EntityMeta.fromRow(r),
              date: today,
              sales: Money.fromMinor(r['sales_minor'] as int),
              profit: Money.fromMinor(r['profit_minor'] as int),
              note: r['note'] as String?,
            ),
      units: (await tx.query('units', orderBy: 'inactive,name_key'))
          .map(
            (r) => StockUnit(
              EntityMeta.fromRow(r),
              r['name'] as String,
              r['inactive'] == 1,
            ),
          )
          .toList(),
    );
  });
}
