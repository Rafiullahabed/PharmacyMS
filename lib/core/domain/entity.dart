import 'package:uuid/uuid.dart';
import 'dates.dart';
import 'validation.dart';

typedef DataRow = Map<String, Object?>;

final class EntityMeta {
  EntityMeta({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  }) {
    if (!RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(id) ||
        !createdAt.isUtc ||
        !updatedAt.isUtc ||
        updatedAt.isBefore(createdAt)) {
      throw const ValidationException(
        'Invalid record identity or event timestamps.',
      );
    }
  }
  factory EntityMeta.create(AppClock clock) {
    final now = clock.nowUtc().toUtc();
    return EntityMeta(id: const Uuid().v4(), createdAt: now, updatedAt: now);
  }
  factory EntityMeta.fromRow(DataRow row) => EntityMeta(
    id: row['id'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row['created_at'] as int,
      isUtc: true,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      row['updated_at'] as int,
      isUtc: true,
    ),
  );
  final String id;
  final DateTime createdAt, updatedAt;
  DataRow toRow() => {
    'id': id,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };
}
