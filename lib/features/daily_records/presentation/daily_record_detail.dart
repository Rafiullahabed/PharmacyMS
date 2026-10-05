import 'package:flutter/material.dart';
import '../../../core/domain/dates.dart';
import '../../../core/presentation/components.dart';
import '../../../core/presentation/workflow.dart';
import '../application/daily_records_controller.dart';
import '../domain/daily_record.dart';
import 'daily_data.dart';
import 'daily_record_form.dart';

Future<void> recordDay(
  BuildContext context,
  DailyRecordsController controller, {
  BusinessDate? date,
}) async {
  // Open a route immediately to prevent duplicate-tap lookup/navigation races.
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _OpenDay(
        controller: controller,
        date: date ?? controller.clock.today(),
      ),
    ),
  );
}

class _OpenDay extends StatelessWidget {
  const _OpenDay({required this.controller, required this.date});
  final DailyRecordsController controller;
  final BusinessDate date;
  @override
  Widget build(BuildContext context) => DailyData<DailyRecord?>(
    controller: controller,
    listen: false,
    route: true,
    load: () async => (await controller.repository).onDate(date),
    builder: (_, record) => DailyRecordForm(
      key: ValueKey(record?.meta.id ?? date.iso),
      controller: controller,
      record: record,
      date: date,
    ),
  );
}

Future<void> addDailyRecord(
  BuildContext context,
  DailyRecordsController controller, {
  BusinessDate? date,
}) async {
  // The report reloads after a commit and may dispose the initiating row.
  // Keep the navigator, not that row's BuildContext, across the save.
  final navigator = Navigator.of(context);
  final result = await navigator.push<DailyRecord>(
    MaterialPageRoute(
      builder: (_) => DailyRecordForm(controller: controller, date: date),
    ),
  );
  if (result != null && navigator.mounted) {
    await navigator.push(
      MaterialPageRoute(
        builder: (_) =>
            DailyRecordDetail(controller: controller, id: result.meta.id),
      ),
    );
  }
}

class DailyRecordDetail extends StatefulWidget {
  const DailyRecordDetail({
    super.key,
    required this.controller,
    required this.id,
  });
  final DailyRecordsController controller;
  final String id;
  @override
  State<DailyRecordDetail> createState() => _DailyRecordDetailState();
}

class _DailyRecordDetailState extends State<DailyRecordDetail> {
  final deletion = SaveController();
  bool confirming = false;
  @override
  void dispose() {
    deletion.dispose();
    super.dispose();
  }

  Future<void> remove(DailyRecord record) async {
    if (deletion.saving || confirming) return;
    if (!deletion.uncertain) {
      confirming = true;
      final confirmed = await confirmAction(
        context,
        title: 'Delete daily record?',
        message:
            '${record.date.label}\nSales: ${record.sales.formatted}\nRecorded profit: ${record.profit.formatted}\nThis day will become Not recorded. Inventory and debts are unchanged.',
        action: 'Delete record',
        destructive: true,
      );
      confirming = false;
      if (!confirmed || !mounted) return;
    }
    final success = await deletion.run((operation) async {
      await (await widget.controller.repository).delete(
        widget.id,
        operationId: operation,
      );
      return true;
    });
    if (success == true && mounted) {
      widget.controller.changed();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => DailyData<DailyRecord?>(
    controller: widget.controller,
    route: true,
    load: () async => (await widget.controller.repository).byId(widget.id),
    builder: (context, record) => ListenableBuilder(
      listenable: deletion,
      builder: (context, _) => GuardedForm(
        dirty: false,
        saving: deletion.saving,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Daily record'),
            actions: [
              if (record != null)
                PopupMenuButton<String>(
                  tooltip: 'Record actions',
                  enabled: !deletion.saving && !deletion.uncertain,
                  onSelected: (_) => remove(record),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete record'),
                    ),
                  ],
                ),
            ],
          ),
          body: SafeArea(
            child: PageContent(
              children: [
                if (record == null)
                  const EmptyState(
                    icon: Icons.event_busy_outlined,
                    title: 'Record no longer exists',
                    message:
                        'This day is now Not recorded. Return to the report to add a new entry.',
                  )
                else ...[
                  Text(
                    '${record.date.label} · Gregorian',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  const Text('Sales'),
                  MoneyText(record.sales),
                  const SizedBox(height: 16),
                  Text(
                    record.profit.minor < 0
                        ? 'Recorded profit · Loss'
                        : 'Recorded profit',
                  ),
                  MoneyText(record.profit),
                  const Text('Profit entered manually.'),
                  if (record.note != null) ...[
                    const SizedBox(height: 24),
                    const Text('Note'),
                    ContentText(record.note!),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: deletion.saving || deletion.uncertain
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DailyRecordForm(
                                controller: widget.controller,
                                record: record,
                              ),
                            ),
                          ),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit record'),
                  ),
                  ErrorNotice(deletion.error),
                  if (deletion.error != null)
                    OutlinedButton(
                      onPressed: deletion.saving ? null : () => remove(record),
                      child: const Text('Retry deletion'),
                    ),
                  if (deletion.saving) const Text('Deleting…'),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
