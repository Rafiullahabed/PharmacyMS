import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/data/operations.dart';
import '../../../core/data/repository_support.dart';
import '../../../core/domain/dates.dart';
import '../../../core/domain/entity.dart';
import '../../../core/domain/validation.dart';
import '../../inventory/domain/inventory.dart';
import '../domain/settings_repository.dart';

class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(this.db, this.clock);
  final Database db;
  final AppClock clock;
  StockUnit _unit(DataRow r) =>
      StockUnit(EntityMeta.fromRow(r), r['name'] as String, r['inactive'] == 1);
  @override
  Future<List<StockUnit>> units() async => (await db.query(
    'units',
    orderBy: 'inactive,name_key',
  )).map(_unit).toList();
  @override
  Future<StockUnit> saveUnit({
    String? id,
    required String name,
    bool inactive = false,
    String? operationId,
  }) async {
    name = requiredText(name, 'Unit name');
    return db.transaction((tx) async {
      final savedId = await inventoryOperation(
        tx,
        clock,
        operationId ?? const Uuid().v4(),
        'save_unit',
        {'id': id, 'name': name, 'inactive': inactive},
        () async {
          final previous = id == null
              ? null
              : await requireRow(tx, 'units', id);
          final row = {
            ...(previous ?? EntityMeta.create(clock).toRow()),
            'name': name,
            'name_key': searchKey(name),
            'inactive': inactive ? 1 : 0,
            if (previous != null) 'updated_at': updateTime(previous, clock),
          };
          if (id == null) {
            await tx.insert('units', row);
          } else {
            await tx.update('units', row, where: 'id=?', whereArgs: [id]);
          }
          return row['id'] as String;
        },
      );
      return _unit(await requireRow(tx, 'units', savedId));
    });
  }

  @override
  Future<void> deleteUnusedUnit(String id, {String? operationId}) async {
    await db.transaction((tx) async {
      await inventoryOperation(
        tx,
        clock,
        operationId ?? const Uuid().v4(),
        'delete_unit',
        {'id': id},
        () async {
          await tx.delete('units', where: 'id=?', whereArgs: [id]);
          return id;
        },
      );
    });
  }

  @override
  Future<Map<String, int>> unitUsage() async => {
    for (final r in await db.rawQuery(
      'SELECT unit_id,count(*) AS uses FROM products GROUP BY unit_id',
    ))
      r['unit_id'] as String: r['uses'] as int,
  };

  @override
  Future<AppPreference?> preference(String key) async {
    final rows = await db.query(
      'app_settings',
      where: 'preference_key=?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    return AppPreference(
      EntityMeta.fromRow(r),
      r['preference_key'] as String,
      r['value'] as String,
      r['version'] as int,
    );
  }

  @override
  Future<void> setPreference(
    String key,
    String value, {
    int version = 1,
  }) async {
    requiredText(key, 'Preference key');
    if (version < 1) {
      throw const ValidationException('Invalid preference version.');
    }
    await db.transaction((tx) async {
      final rows = await tx.query(
        'app_settings',
        where: 'preference_key=?',
        whereArgs: [key],
      );
      final previous = rows.isEmpty ? null : rows.single;
      final row = {
        ...(previous ?? EntityMeta.create(clock).toRow()),
        'preference_key': key,
        'value': value,
        'version': version,
        if (previous != null) 'updated_at': updateTime(previous, clock),
      };
      if (previous == null) {
        await tx.insert('app_settings', row);
      } else {
        await tx.update(
          'app_settings',
          row,
          where: 'id=?',
          whereArgs: [previous['id']],
        );
      }
    });
  }
}
