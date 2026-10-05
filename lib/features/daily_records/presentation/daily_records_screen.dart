import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/domain/dates.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/validation.dart';
import '../../../core/presentation/components.dart';
import '../../../core/presentation/workflow.dart';
import '../application/daily_records_controller.dart';
import '../domain/daily_report.dart';
import '../../../core/presentation/business_date_input.dart';
import 'daily_data.dart';
import 'daily_record_detail.dart';
import 'trend_panel.dart';

class DailyRecordsScreen extends StatefulWidget {
  const DailyRecordsScreen({super.key, required this.controller});
  final DailyRecordsController controller;
  @override
  State<DailyRecordsScreen> createState() => _DailyRecordsScreenState();
}

class _DailyRecordsScreenState extends State<DailyRecordsScreen> {
  ReportPeriod period = ReportPeriod.last7Days;
  ReportRange? custom;
  int daysShown = 50;
  Future<void> choose(ReportPeriod next) async {
    ReportRange? selected;
    if (next == ReportPeriod.custom) {
      selected = await showDialog<ReportRange>(
        context: context,
        builder: (_) => _RangeDialog(
          initial: custom ?? period.range(widget.controller.clock.today()),
          today: widget.controller.clock.today(),
        ),
      );
      if (selected == null || !mounted) return;
    }
    setState(() {
      period = next;
      custom = selected ?? custom;
      daysShown = 50;
    });
  }

  @override
  Widget build(BuildContext context) => DailyData<DailyReport>(
    key: ValueKey('${period.name}-${custom?.label}'),
    controller: widget.controller,
    load: () async => (await widget.controller.repository).report(
      period.range(widget.controller.clock.today(), custom: custom),
    ),
    builder: (context, report) {
      final count = math.min(daysShown, report.range.days);
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView.builder(
            key: PageStorageKey('daily-${period.name}-${custom?.label}'),
            padding: const EdgeInsets.all(16),
            itemCount: count + 2,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () =>
                            addDailyRecord(context, widget.controller),
                        icon: const Icon(Icons.add),
                        label: const Text('Add record'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in ReportPeriod.values)
                          ChoiceChip(
                            label: Text(p.label),
                            selected: period == p,
                            onSelected: (_) => choose(p),
                          ),
                      ],
                    ),
                    if (period == ReportPeriod.custom)
                      TextButton.icon(
                        onPressed: () => choose(ReportPeriod.custom),
                        icon: const Icon(Icons.date_range),
                        label: const Text('Change custom range'),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      '${report.range.label} · Gregorian',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (period == ReportPeriod.thisMonth)
                      const Text('This month through today.'),
                    const SizedBox(height: 16),
                    _ReportSummary(report: report),
                    if (report.records.isEmpty)
                      const EmptyState(
                        icon: Icons.bar_chart_outlined,
                        title: 'No records in this period',
                        message:
                            'Add a record with your own daily totals. Missing days are Not recorded; a recorded zero is a real entry.',
                      )
                    else ...[
                      TrendPanel(report: report),
                      const SizedBox(height: 24),
                    ],
                    Text(
                      'Daily data · Newest first',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Exact sales and manually recorded profit. Missing dates are shown explicitly.',
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              }
              if (index == count + 1) {
                return count < report.range.days
                    ? TextButton(
                        onPressed: () => setState(() => daysShown += 50),
                        child: const Text('Show earlier days'),
                      )
                    : const SizedBox(height: 24);
              }
              final point = report.dayAt(report.range.days - index),
                  record = point.record;
              final future =
                  point.range.start.compareTo(widget.controller.clock.today()) >
                  0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(point.label),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (record == null)
                          const Text('Not recorded')
                        else ...[
                          Text(
                            'Sales: ${record.sales.formatted}',
                            textDirection: TextDirection.ltr,
                          ),
                          Text(
                            'Recorded profit${record.profit.minor < 0 ? ' · Loss' : ''}: ${record.profit.formatted}',
                            textDirection: TextDirection.ltr,
                          ),
                          if (record.note?.isNotEmpty ?? false)
                            const Text('Note included'),
                        ],
                        if (record == null && !future)
                          const Text('Tap to record this day'),
                      ],
                    ),
                    trailing: future ? null : const Icon(Icons.chevron_right),
                    onTap: future
                        ? null
                        : record == null
                        ? () => addDailyRecord(
                            context,
                            widget.controller,
                            date: point.range.start,
                          )
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DailyRecordDetail(
                                controller: widget.controller,
                                id: record.meta.id,
                              ),
                            ),
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

class _ReportSummary extends StatelessWidget {
  const _ReportSummary({required this.report});
  final DailyReport report;
  @override
  Widget build(BuildContext context) => Section(
    title: 'Recorded totals',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Total recorded sales'),
        Text(
          report.totals.recorded == 0
              ? 'Not recorded'
              : formatMinorUnits(report.totals.sales),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text('Total recorded profit · Entered manually'),
        Text(
          report.totals.recorded == 0
              ? 'Not recorded'
              : formatMinorUnits(report.totals.profit),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (report.totals.profit.isNegative) const Text('Reported loss'),
        const SizedBox(height: 12),
        Text(
          report.totals.coverage,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text('Totals include recorded days only.'),
        ExpansionTile(
          key: const PageStorageKey('daily-period-comparison'),
          tilePadding: EdgeInsets.zero,
          title: const Text('Compare previous period'),
          children: [
            if (report.range.previous != null)
              Text('${report.range.previous!.label} · Same number of days'),
            Text('Previous: ${report.previousTotals.coverage}'),
            Text('Sales change: ${report.change(false)}'),
            Text('Recorded profit change: ${report.change(true)}'),
            const Text(
              'Changes compare recorded totals, not daily averages. Missing days can affect the comparison. Zero or missing baselines are Not available. A negative baseline uses its absolute magnitude.',
            ),
          ],
        ),
      ],
    ),
  );
}

class _RangeDialog extends StatefulWidget {
  const _RangeDialog({required this.initial, required this.today});
  final ReportRange initial;
  final BusinessDate today;
  @override
  State<_RangeDialog> createState() => _RangeDialogState();
}

class _RangeDialogState extends State<_RangeDialog> {
  final form = GlobalKey<FormState>(),
      start = TextEditingController(),
      end = TextEditingController();
  String? error;
  @override
  void initState() {
    super.initState();
    start.text = widget.initial.start.iso;
    end.text = widget.initial.end.iso;
  }

  @override
  void dispose() {
    start.dispose();
    end.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Custom range'),
    content: Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Both dates are included. Coverage counts every day in this range.',
          ),
          BusinessDateInput(
            controller: start,
            label: 'Start date',
            today: widget.today,
          ),
          BusinessDateInput(
            controller: end,
            label: 'End date',
            today: widget.today,
          ),
          ErrorNotice(error),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          try {
            Navigator.pop(
              context,
              ReportRange(
                BusinessDate.parse(normalizeDigits(start.text.trim())),
                BusinessDate.parse(normalizeDigits(end.text.trim())),
              ),
            );
          } on ValidationException catch (e) {
            setState(() => error = e.message);
          }
        },
        child: const Text('Apply range'),
      ),
    ],
  );
}
