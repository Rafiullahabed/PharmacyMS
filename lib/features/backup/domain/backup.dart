import 'dart:typed_data';

typedef BackupRow = Map<String, Object?>;
typedef BackupTables = Map<String, List<BackupRow>>;
const backupFormatVersion = 1;
const backupAppVersion = '0.6.0+6';
const maxBackupBytes = 64 * 1024 * 1024;
const maxPayloadBytes = 63 * 1024 * 1024;
const maxBackupRecords = 250000;
const backupStatusKey = 'backup.last_prepared';
const restoreStatusKey = 'backup.last_restore';

List<String> backupTablesFor(int schema) => [
  'units',
  'products',
  'date_specs',
  'batches',
  'stock_movements',
  'daily_records',
  'customers',
  'ledger_entries',
  'correction_audits',
  'app_settings',
  if (schema >= 2) 'sequence_counters',
  if (schema >= 3) 'inventory_operations',
  if (schema >= 4) 'daily_operations',
  if (schema >= 5) 'debt_operations',
];

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupManifest {
  const BackupManifest({
    required this.schema,
    required this.appVersion,
    required this.createdUtc,
    required this.timezone,
    required this.offsetMinutes,
    required this.counts,
    required this.checksum,
    required this.payloadBytes,
  });
  final int schema, offsetMinutes, payloadBytes;
  final String appVersion, timezone, checksum;
  final DateTime createdUtc;
  final Map<String, int> counts;
  Map<String, Object?> toJson() => {
    'format': 'pharmacy-companion-backup',
    'format_version': backupFormatVersion,
    'schema_version': schema,
    'app_version': appVersion,
    'created_utc': createdUtc.toUtc().toIso8601String(),
    'timezone': timezone,
    'utc_offset_minutes': offsetMinutes,
    'counts': counts,
    'payload_bytes': payloadBytes,
    'checksum_algorithm': 'SHA-256',
    'payload_sha256': checksum,
    'integer_encoding': 'decimal-strings',
  };
}

class BackupDocument {
  const BackupDocument(this.manifest, this.tables);
  final BackupManifest manifest;

  /// Portable rows: all SQLite INTEGER columns are decimal strings.
  final BackupTables tables;
}

class PreparedBackup {
  const PreparedBackup(this.path, this.filename, this.manifest);
  final String path, filename;
  final BackupManifest manifest;
}

class RestorePreview {
  const RestorePreview(this.token, this.filename, this.manifest);
  final String token, filename;
  final BackupManifest manifest;
}

enum ExportOutcome { prepared, saved, shared, unconfirmed, cancelled, failed }

extension ExportOutcomeLabel on ExportOutcome {
  String get label => switch (this) {
    ExportOutcome.prepared =>
      'Prepared on this device; no external save confirmed.',
    ExportOutcome.saved => 'File saved to your selected destination.',
    ExportOutcome.shared =>
      'Shared with the selected app; external saving is not confirmed.',
    ExportOutcome.unconfirmed =>
      'Share sheet opened; external saving is not confirmed.',
    ExportOutcome.cancelled => 'Cancelled. No external save confirmed.',
    ExportOutcome.failed =>
      'File prepared, but delivery failed. Try saving or sharing again.',
  };
}

class BackupStatus {
  const BackupStatus(this.createdUtc, this.filename, this.outcome);
  final DateTime createdUtc;
  final String filename;
  final ExportOutcome outcome;
}

typedef BackupProgress = void Function(String stage);

abstract interface class BackupRepository {
  Future<BackupStatus?> status();
  Future<PreparedBackup> prepare({BackupProgress? progress});
  Future<void> recordOutcome(PreparedBackup backup, ExportOutcome outcome);
  Future<RestorePreview> validate(
    Uint8List bytes,
    String filename, {
    BackupProgress? progress,
  });
  Future<void> discard(RestorePreview preview);
  Future<void> restore(RestorePreview preview, {BackupProgress? progress});
}
