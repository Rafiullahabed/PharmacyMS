import 'package:sqflite/sqflite.dart';
import '../domain/dates.dart';
import '../domain/entity.dart';
import '../domain/validation.dart';

void validatePage(int limit, int offset) {
  if (limit < 1 || limit > 200 || offset < 0) {
    throw const ValidationException('Invalid page.');
  }
}

Future<DataRow> requireRow(DatabaseExecutor db, String table, String id) async {
  final rows = await db.query(table, where: 'id=?', whereArgs: [id], limit: 1);
  if (rows.isEmpty) {
    throw const ValidationException('This record no longer exists.');
  }
  return rows.single;
}

int updateTime(DataRow row, AppClock clock) {
  final now = clock.nowUtc().millisecondsSinceEpoch;
  return now < (row['updated_at'] as int) ? row['updated_at'] as int : now;
}

Future<int> nextSequence(DatabaseExecutor db, String table) async {
  // Called inside the same transaction as the new entry. Deletion never reuses order.
  await db.rawUpdate(
    'UPDATE sequence_counters SET value=value+1 WHERE name=?',
    [table],
  );
  return Sqflite.firstIntValue(
    await db.rawQuery('SELECT value FROM sequence_counters WHERE name=?', [
      table,
    ]),
  )!;
}
