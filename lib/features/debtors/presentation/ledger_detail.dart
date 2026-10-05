import 'package:flutter/material.dart';
import '../../../core/domain/money.dart';
import '../../../core/presentation/components.dart';
import '../../../core/presentation/repository_view.dart';
import '../../../core/presentation/workflow.dart';
import '../application/debt_controller.dart';
import '../domain/debt.dart';
import 'ledger_form.dart';

typedef _EntryData = ({LedgerEntry entry, Customer customer, Money balance});

class LedgerDetail extends StatefulWidget {
  const LedgerDetail({super.key, required this.controller, required this.id});
  final DebtController controller;
  final String id;
  @override
  State<LedgerDetail> createState() => _LedgerDetailState();
}

class _LedgerDetailState extends State<LedgerDetail> {
  final deletion = SaveController();
  bool checking = false;
  @override
  void dispose() {
    deletion.dispose();
    super.dispose();
  }

  Future<_EntryData?> load() async {
    final repo = await widget.controller.repository,
        entry = await (await widget.controller.repository).entry(widget.id);
    if (entry == null) return null;
    return (
      entry: entry,
      customer: await repo.customer(entry.customerId),
      balance: await repo.balance(entry.customerId),
    );
  }

  Future<void> remove(_EntryData data) async {
    if (deletion.saving || checking) return;
    setState(() => checking = true);
    try {
      final repo = await widget.controller.repository;
      if (!deletion.uncertain) {
        final preview = await repo.preview(
          data.customer.meta.id,
          entryId: widget.id,
          deleting: true,
        );
        if (!mounted) return;
        if (!await confirmAction(
          context,
          title: 'Delete ledger entry?',
          message:
              '${data.entry.kind.label}: ${data.entry.amount.formatted}\n${data.entry.date.label}\nOutstanding before: ${preview.before.formatted}\nOutstanding after deletion: ${preview.after.formatted}\nThe correction audit keeps the original entry.',
          action: 'Delete entry',
          destructive: true,
        )) {
          return;
        }
      }
      if (!mounted) return;
      final result = await deletion.run((operation) async {
        await repo.deleteEntry(
          widget.id,
          reason: 'Deleted after confirmation',
          operationId: operation,
        );
        return true;
      });
      if (result == true && mounted) {
        widget.controller.changed();
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) setState(() => deletion.error = persistenceMessage(error));
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => RepositoryView<_EntryData?>(
    changes: widget.controller,
    routeTitle: 'Ledger entry',
    load: load,
    builder: (context, data) => ListenableBuilder(
      listenable: deletion,
      builder: (context, _) => GuardedForm(
        dirty: false,
        saving: deletion.saving,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Ledger entry'),
            actions: [
              if (data != null && !data.customer.archived)
                PopupMenuButton<String>(
                  tooltip: 'Entry actions',
                  enabled: !checking && !deletion.saving && !deletion.uncertain,
                  onSelected: (_) => remove(data),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete entry'),
                    ),
                  ],
                ),
            ],
          ),
          body: SafeArea(
            child: PageContent(
              children: [
                if (data == null)
                  const EmptyState(
                    icon: Icons.history,
                    title: 'Entry deleted',
                    message:
                        'The original values remain in correction history.',
                  )
                else ...[
                  ContentText(
                    data.customer.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  StatusBadge(
                    label: data.entry.kind.label,
                    icon: data.entry.kind == LedgerKind.debt
                        ? Icons.add_circle_outline
                        : Icons.payments_outlined,
                  ),
                  const SizedBox(height: 12),
                  MoneyText(
                    data.entry.amount,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text('${data.entry.date.label} · Gregorian'),
                  Text('Saved sequence: ${data.entry.sequence}'),
                  const SizedBox(height: 16),
                  const Text('Description'),
                  ContentText(
                    data.entry.description.isEmpty
                        ? 'No description entered.'
                        : data.entry.description,
                  ),
                  const SizedBox(height: 24),
                  if (data.customer.archived)
                    const Text(
                      'Restore the customer before correcting this entry.',
                    )
                  else
                    FilledButton.icon(
                      onPressed:
                          deletion.saving || deletion.uncertain || checking
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LedgerForm(
                                  controller: widget.controller,
                                  customer: data.customer,
                                  balance: data.balance,
                                  kind: data.entry.kind,
                                  entry: data.entry,
                                ),
                              ),
                            ),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit entry'),
                    ),
                  ErrorNotice(deletion.error),
                  if (deletion.error != null)
                    TextButton(
                      onPressed: checking || deletion.saving
                          ? null
                          : () => remove(data),
                      child: const Text('Retry deletion'),
                    ),
                  if (checking) const Text('Checking balances…'),
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

class CorrectionHistory extends StatefulWidget {
  const CorrectionHistory({
    super.key,
    required this.controller,
    required this.customerId,
  });
  final DebtController controller;
  final String customerId;
  @override
  State<CorrectionHistory> createState() => _CorrectionHistoryState();
}

class _CorrectionHistoryState extends State<CorrectionHistory> {
  int pages = 1;
  Future<List<CorrectionAudit>> load() async {
    final repo = await widget.controller.repository,
        result = <CorrectionAudit>[];
    for (var page = 0; page < pages; page++) {
      final rows = await repo.corrections(widget.customerId, offset: page * 50);
      result.addAll(rows);
      if (rows.length < 50) break;
    }
    return result;
  }

  Widget values(Map<String, Object?> row) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '${row['kind'] == 'debt' ? 'Debt' : 'Payment'} · ${Money.fromMinor(row['amount_minor'] as int).formatted}',
      ),
      Text('${row['business_date']} · Gregorian'),
      ContentText(row['description'] as String),
    ],
  );
  @override
  Widget build(BuildContext context) => RepositoryView<List<CorrectionAudit>>(
    key: ValueKey(pages),
    changes: widget.controller,
    routeTitle: 'Correction history',
    load: load,
    builder: (context, rows) => Scaffold(
      appBar: AppBar(title: const Text('Correction history')),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length + 1,
          itemBuilder: (context, i) {
            if (i == rows.length) {
              return rows.isEmpty
                  ? const EmptyState(
                      icon: Icons.history,
                      title: 'No corrections',
                      message:
                          'Edits and deletions retain the previous values here.',
                    )
                  : rows.length == pages * 50
                  ? TextButton(
                      onPressed: () => setState(() => pages++),
                      child: const Text('Load more corrections'),
                    )
                  : const SizedBox(height: 16);
            }
            final audit = rows[i];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${audit.action == 'edit' ? 'Edited' : 'Deleted'} · ${audit.meta.createdAt.toLocal()}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('Entry: ${audit.entryId.substring(0, 8)}'),
                    ContentText(audit.reason),
                    const SizedBox(height: 12),
                    const Text('Before'),
                    values(audit.previous),
                    if (audit.next != null) ...[
                      const SizedBox(height: 12),
                      const Text('After'),
                      values(audit.next!),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
