import 'package:flutter/material.dart';
import '../../../core/presentation/components.dart';
import '../../../core/presentation/workflow.dart';
import '../application/backup_controller.dart';
import '../domain/backup.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.controller});
  final BackupController controller;
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool confirming = false;
  @override
  void initState() {
    super.initState();
    widget.controller.loadStatus();
  }

  Future<void> confirmRestore() async {
    if (confirming || widget.controller.busy) return;
    confirming = true;
    final confirmed = await confirmAction(
      context,
      title: 'Replace current data?',
      message:
          'Restoring this backup replaces the information currently in this app. It does not merge records. An internal safety snapshot will be created first.',
      action: 'Restore backup',
      destructive: true,
    );
    confirming = false;
    if (confirmed && mounted) await widget.controller.restore();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller, preview = c.preview, prepared = c.prepared;
      return GuardedForm(
        dirty: false,
        saving: c.busy,
        child: Scaffold(
          appBar: pageAppBar(context, title: 'Backup & Restore'),
          body: SafeArea(
            child: PageContent(
              children: [
                const Text(
                  'Includes your inventory, daily records, customer debts, and settings. Keep the file somewhere private.',
                ),
                const SizedBox(height: 20),
                Section(
                  title: 'Last backup preparation',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (c.loadingStatus)
                        const Text('Reading backup status…')
                      else if (c.statusError != null) ...[
                        ErrorNotice(c.statusError),
                        TextButton(
                          onPressed: c.busy ? null : c.loadStatus,
                          child: const Text('Retry status'),
                        ),
                      ] else if (c.last == null)
                        const Text('No backup has been prepared yet.')
                      else ...[
                        Text(localEventLabel(c.last!.createdUtc)),
                        Text(c.last!.filename),
                        Text(c.last!.outcome.label),
                      ],
                    ],
                  ),
                ),
                if (c.busy)
                  Semantics(
                    liveRegion: true,
                    child: Column(
                      children: [
                        LoadingState(label: c.stage ?? 'Working…'),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                if (c.message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Semantics(liveRegion: true, child: Text(c.message!)),
                  ),
                ErrorNotice(c.error),
                FilledButton.icon(
                  onPressed: c.busy || preview != null
                      ? null
                      : () async {
                          await c.create();
                          if (!context.mounted ||
                              c.prepared == null ||
                              c.error != null) {
                            return;
                          }
                          // Preparation succeeds independently of whether a destination is chosen.
                          await c.deliver(share: false);
                        },
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Create backup'),
                ),
                if (prepared != null) ...[
                  const SizedBox(height: 12),
                  Text('Prepared file: ${prepared.filename}'),
                  OutlinedButton.icon(
                    onPressed: c.busy || preview != null
                        ? null
                        : () => c.deliver(share: false),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Save prepared file'),
                  ),
                  Builder(
                    builder: (buttonContext) => OutlinedButton.icon(
                      onPressed: c.busy || preview != null
                          ? null
                          : () {
                              final box =
                                  buttonContext.findRenderObject()!
                                      as RenderBox;
                              c.deliver(
                                share: true,
                                origin:
                                    box.localToGlobal(Offset.zero) & box.size,
                              );
                            },
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Share prepared file'),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: c.busy ? null : c.select,
                  icon: const Icon(Icons.restore_page_outlined),
                  label: Text(
                    preview == null ? 'Restore backup' : 'Choose another file',
                  ),
                ),
                if (preview != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Restore preview',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(preview.filename),
                  Text(
                    'Created: ${localEventLabel(preview.manifest.createdUtc)}',
                  ),
                  Text(
                    'Source timezone: ${preview.manifest.timezone} (UTC offset ${preview.manifest.offsetMinutes} minutes)',
                  ),
                  Text(
                    'App ${preview.manifest.appVersion} · Format $backupFormatVersion · Schema ${preview.manifest.schema}',
                  ),
                  const SizedBox(height: 12),
                  for (final count in preview.manifest.counts.entries.where(
                    (e) =>
                        !e.key.endsWith('_operations') &&
                        e.key != 'sequence_counters',
                  ))
                    Text('${_tableLabel(count.key)}: ${count.value}'),
                  const SizedBox(height: 16),
                  const StatusBadge(
                    icon: Icons.warning_amber_rounded,
                    label:
                        'Replaces all current data. Records will not be merged.',
                    color: Color(0xFFB91C1C),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: c.busy ? null : confirmRestore,
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    icon: const Icon(Icons.restore),
                    label: const Text('Replace with this backup'),
                  ),
                  TextButton(
                    onPressed: c.busy ? null : c.cancelPreview,
                    child: const Text('Cancel restore'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

String _tableLabel(String table) => switch (table) {
  'date_specs' => 'Original dates',
  'stock_movements' => 'Stock history',
  'daily_records' => 'Daily records',
  'ledger_entries' => 'Ledger entries',
  'correction_audits' => 'Correction history',
  'app_settings' => 'Settings',
  _ => '${table[0].toUpperCase()}${table.substring(1)}',
};
