import 'dart:typed_data';
import 'dart:ui';
import '../domain/backup.dart';

class SelectedBackup {
  const SelectedBackup(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

abstract interface class BackupFiles {
  Future<SelectedBackup?> pick();
  Future<ExportOutcome> save(PreparedBackup backup);
  Future<ExportOutcome> share(PreparedBackup backup, Rect origin);
}
