import 'package:flutter/material.dart';
import '../../../core/presentation/components.dart';
import '../../../core/presentation/repository_view.dart';
import '../../../core/presentation/workflow.dart';
import '../application/debt_controller.dart';
import '../domain/debt.dart';
import 'customer_form.dart';
import 'ledger_form.dart';
import 'ledger_detail.dart';

class CustomerDetail extends StatefulWidget {
  const CustomerDetail({super.key, required this.controller, required this.id});
  final DebtController controller;
  final String id;
  @override
  State<CustomerDetail> createState() => _CustomerDetailState();
}

class _CustomerDetailState extends State<CustomerDetail> {
  int pages = 1;
  final archive = SaveController();
  bool confirming = false;
  bool? archiveTarget;
  @override
  void dispose() {
    archive.dispose();
    super.dispose();
  }

  Future<void> toggleArchive(CustomerLedger data) async {
    if (archive.saving || confirming) return;
    final target = archive.uncertain ? archiveTarget! : !data.customer.archived;
    archiveTarget = target;
    if (!archive.uncertain) {
      confirming = true;
      final yes = await confirmAction(
        context,
        title: target ? 'Archive customer?' : 'Restore customer?',
        message: target
            ? 'This settled customer will leave active lists. All entries and corrections are kept.'
            : 'This customer will return to active lists with the same history.',
        action: target ? 'Archive' : 'Restore',
      );
      confirming = false;
      if (!yes || !mounted) return;
    }
    final success = await archive.run((operation) async {
      await (await widget.controller.repository).archiveCustomer(
        widget.id,
        archived: target,
        operationId: operation,
      );
      return true;
    });
    if (success == true && mounted) {
      archive.newAttempt();
      widget.controller.changed();
    }
  }

  @override
  Widget build(BuildContext context) => RepositoryView<CustomerLedger>(
    key: ValueKey(pages),
    changes: widget.controller,
    routeTitle: 'Customer',
    load: () => widget.controller.history(widget.id, pages: pages),
    builder: (context, data) => ListenableBuilder(
      listenable: archive,
      builder: (context, _) => GuardedForm(
        dirty: false,
        saving: archive.saving,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Customer'),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Customer actions',
                enabled: !archive.saving && !archive.uncertain,
                onSelected: (_) => toggleArchive(data),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'archive',
                    enabled: data.customer.archived || data.balance.minor == 0,
                    child: Text(
                      data.customer.archived
                          ? 'Restore customer'
                          : 'Archive customer',
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: data.lines.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ContentText(
                            data.customer.name,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          if (data.customer.phone?.isNotEmpty ?? false)
                            Text(
                              data.customer.phone!,
                              textDirection: TextDirection.ltr,
                            ),
                          if (data.customer.note?.isNotEmpty ?? false) ...[
                            const SizedBox(height: 12),
                            ContentText(data.customer.note!),
                          ],
                          const SizedBox(height: 16),
                          const Text('Outstanding balance'),
                          MoneyText(
                            data.balance,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          StatusBadge(
                            label: data.customer.archived
                                ? 'Archived · History retained'
                                : data.balance.minor == 0
                                ? 'Settled'
                                : 'Outstanding',
                            icon: data.customer.archived
                                ? Icons.archive_outlined
                                : data.balance.minor == 0
                                ? Icons.check_circle_outline
                                : Icons.account_balance_wallet_outlined,
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: archive.saving || archive.uncertain
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CustomerForm(
                                        controller: widget.controller,
                                        customer: data.customer,
                                      ),
                                    ),
                                  ),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit customer'),
                          ),
                          if (!data.customer.archived)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final kind in LedgerKind.values)
                                  FilledButton.icon(
                                    onPressed:
                                        archive.saving ||
                                            archive.uncertain ||
                                            (kind == LedgerKind.payment &&
                                                data.balance.minor == 0)
                                        ? null
                                        : () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => LedgerForm(
                                                controller: widget.controller,
                                                customer: data.customer,
                                                balance: data.balance,
                                                kind: kind,
                                              ),
                                            ),
                                          ),
                                    icon: Icon(
                                      kind == LedgerKind.debt
                                          ? Icons.add
                                          : Icons.payments_outlined,
                                    ),
                                    label: Text(kind.action),
                                  ),
                              ],
                            ),
                          const SizedBox(height: 8),
                          Text(
                            data.customer.archived
                                ? 'Restore this customer to add or correct entries.'
                                : data.balance.minor == 0
                                ? 'No payment is due. Add debt when needed; past entries remain available.'
                                : 'Settle the outstanding balance before archiving.',
                          ),
                          ErrorNotice(archive.error),
                          if (archive.error != null)
                            TextButton(
                              onPressed: archive.saving
                                  ? null
                                  : () => toggleArchive(data),
                              child: const Text('Retry archive change'),
                            ),
                          TextButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CorrectionHistory(
                                  controller: widget.controller,
                                  customerId: widget.id,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.history),
                            label: const Text('Correction history'),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Transactions · Newest first',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '${data.total} entries · Ordered by business date, then saved sequence',
                          ),
                          const SizedBox(height: 12),
                        ],
                      );
                    }
                    if (index == data.lines.length + 1) {
                      if (data.total == 0) {
                        return const EmptyState(
                          icon: Icons.menu_book_outlined,
                          title: 'No transactions yet',
                          message:
                              'Add debt with a description. For an opening balance, use an ordinary debt entry and an Opening balance note.',
                        );
                      }
                      return data.lines.length < data.total
                          ? TextButton(
                              onPressed: () => setState(() => pages++),
                              child: const Text('Load earlier transactions'),
                            )
                          : const SizedBox(height: 24);
                    }
                    final line = data.lines[index - 1], entry = line.entry;
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: Icon(
                          entry.kind == LedgerKind.debt
                              ? Icons.add_circle_outline
                              : Icons.payments_outlined,
                        ),
                        title: Text(
                          '${entry.kind.label}\n${entry.kind == LedgerKind.debt ? '+' : '−'} ${entry.amount.formatted}',
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${entry.date.label} · Sequence ${entry.sequence}',
                            ),
                            if (entry.description.isNotEmpty)
                              Text(
                                entry.description,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                textDirection: contentDirection(
                                  entry.description,
                                ),
                              ),
                            Text('Balance after: ${line.balance.formatted}'),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LedgerDetail(
                              controller: widget.controller,
                              id: entry.meta.id,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
