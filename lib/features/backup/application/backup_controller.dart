import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../domain/backup.dart';
import 'backup_files.dart';

class BackupController extends ChangeNotifier {
  BackupController({
    required this.resolve,
    required this.files,
    required this.onRestored,
  });
  final Future<BackupRepository> Function() resolve;
  final BackupFiles files;
  final Future<void> Function() onRestored;
  bool busy = false, loadingStatus = false, disposed = false;
  String? stage, error, message, statusError;
  BackupStatus? last;
  PreparedBackup? prepared;
  RestorePreview? preview;
  int restoreRevision = 0;
  Map<String, int>? restoredCounts;
  void changed() {
    if (!disposed) notifyListeners();
  }

  void progress(String value) {
    stage = value;
    changed();
  }

  Future<void> loadStatus() async {
    if (loadingStatus) return;
    loadingStatus = true;
    statusError = null;
    changed();
    try {
      last = await (await resolve()).status();
    } catch (_) {
      statusError = 'Unable to read the last backup status.';
    } finally {
      loadingStatus = false;
      changed();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    message = null;
    changed();
    try {
      await action();
    } catch (e) {
      error = e is BackupException
          ? e.message
          : 'The file operation could not complete. Check available storage or choose another local file or destination, then try again.';
    } finally {
      busy = false;
      stage = null;
      changed();
    }
  }

  Future<void> create() => _run(() async {
    prepared = await (await resolve()).prepare(progress: progress);
    message = ExportOutcome.prepared.label;
    await loadStatus();
  });
  Future<void> deliver({required bool share, Rect? origin}) => _run(() async {
    final backup = prepared;
    if (backup == null) return;
    progress(share ? 'Opening share sheet…' : 'Choose a destination…');
    ExportOutcome outcome;
    try {
      outcome = share
          ? await files.share(backup, origin!)
          : await files.save(backup);
    } catch (_) {
      outcome = ExportOutcome.failed;
    }
    message = outcome.label;
    try {
      await (await resolve()).recordOutcome(backup, outcome);
    } catch (_) {
      error =
          'The file workflow finished, but its status could not be saved on this device. ${outcome.label}';
    }
    await loadStatus();
  });
  Future<void> select() => _run(() async {
    await _discard();
    progress('Choose a backup file…');
    final selected = await files.pick();
    if (selected == null) {
      message = 'File selection cancelled. Current data is unchanged.';
      return;
    }
    preview = await (await resolve()).validate(
      selected.bytes,
      selected.name,
      progress: progress,
    );
  });
  Future<void> _discard() async {
    final old = preview;
    preview = null;
    if (old != null) await (await resolve()).discard(old);
  }

  Future<void> cancelPreview() => _run(() async {
    await _discard();
    message = 'Restore cancelled. Current data is unchanged.';
  });

  /// Called only after the screen's explicit replacement confirmation.
  Future<void> restore() => _run(() async {
    final current = preview;
    if (current == null) return;
    await (await resolve()).restore(current, progress: progress);
    preview = null;
    prepared = null;
    restoredCounts = current.manifest.counts;
    message =
        'Backup restored. ${restoredCounts!['products']} products, ${restoredCounts!['daily_records']} daily records and ${restoredCounts!['customers']} customers.';
    // Database commit is already durable. Refresh failure must not claim rollback.
    try {
      await onRestored();
    } catch (_) {
      message = '$message Reopen the app if a screen does not refresh.';
    }
    restoreRevision++;
    changed();
    await loadStatus();
  });
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
