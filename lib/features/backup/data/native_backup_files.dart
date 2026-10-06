import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../application/backup_files.dart';
import '../domain/backup.dart';

Future<Uint8List> readBoundedBackup(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (builder.length + chunk.length > maxBackupBytes) {
      throw const BackupException(
        'This backup exceeds the 64 MiB file limit. Choose a smaller original backup.',
      );
    }
    builder.add(chunk);
  }
  return builder.takeBytes();
}

/// Native scoped document pickers and share sheets, without broad storage access.
class NativeBackupFiles implements BackupFiles {
  @override
  Future<SelectedBackup?> pick() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        allowMultiple: false,
        withData: false,
        withReadStream: true,
        dialogTitle: 'Select pharmacy backup',
      );
      if (result == null) return null;
      final file = result.files.single;
      if (file.size > maxBackupBytes) {
        throw const BackupException(
          'This backup exceeds the 64 MiB file limit.',
        );
      }
      final stream =
          file.readStream ??
          (file.path == null ? null : File(file.path!).openRead());
      if (stream == null) {
        throw const BackupException(
          'The selected file could not be read. Choose a local copy.',
        );
      }
      return SelectedBackup(file.name, await readBoundedBackup(stream));
    } finally {
      // Only the plugin's own imported-file cache; never the selected original.
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          await FilePicker.platform.clearTemporaryFiles();
        } catch (_) {
          /* OS can clear its cache later. */
        }
      }
    }
  }

  @override
  Future<ExportOutcome> save(PreparedBackup backup) async {
    final bytes = await readBoundedBackup(File(backup.path).openRead());
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save pharmacy backup',
      fileName: backup.filename,
      type: FileType.custom,
      allowedExtensions: ['zip'],
      bytes: bytes,
    );
    if (result != null && !Platform.isAndroid && !Platform.isIOS) {
      await File(result).writeAsBytes(bytes, flush: true);
    }
    return result == null ? ExportOutcome.cancelled : ExportOutcome.saved;
  }

  @override
  Future<ExportOutcome> share(PreparedBackup backup, Rect origin) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(backup.path, mimeType: 'application/zip')],
        fileNameOverrides: [backup.filename],
        sharePositionOrigin: origin,
        title: 'Pharmacy backup',
      ),
    );
    return switch (result.status) {
      ShareResultStatus.success => ExportOutcome.shared,
      ShareResultStatus.dismissed => ExportOutcome.cancelled,
      ShareResultStatus.unavailable => ExportOutcome.unconfirmed,
    };
  }
}
