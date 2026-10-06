import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../domain/dates.dart';
import 'schema.dart';

class AppDatabase {
  AppDatabase._(this.connection, this.factory);
  final Database connection;
  final DatabaseFactory factory;

  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
    AppClock clock = const SystemClock(),
  }) async {
    final engine = factory ?? databaseFactory;
    final location =
        path ??
        p.join(await engine.getDatabasesPath(), 'pharmacy_companion.sqlite');
    final db = await engine.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys=ON');
          // This assignment returns a row. Android's execute API rejects it.
          await db.rawQuery('PRAGMA busy_timeout=5000');
          await db.execute('PRAGMA synchronous=FULL');
        },
        onCreate: (db, version) async {
          await migrate(db, 0, version);
          final now = clock.nowUtc().millisecondsSinceEpoch;
          for (final name in [
            'Strip',
            'Bottle',
            'Box',
            'Piece',
            'Pack',
            'Tube',
          ]) {
            await db.insert('units', {
              'id': const Uuid().v4(),
              'name': name,
              'name_key': name.toLowerCase(),
              'inactive': 0,
              'created_at': now,
              'updated_at': now,
            });
          }
        },
        onUpgrade: migrate,
        onDowngrade: (db, old, next) => throw StateError(
          'This database requires a newer app. Its data has been preserved.',
        ),
      ),
    );
    return AppDatabase._(db, engine);
  }

  Future<void> close() => connection.close();
}
