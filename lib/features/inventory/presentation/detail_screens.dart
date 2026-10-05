import 'package:flutter/material.dart';
import '../../../core/presentation/components.dart';
import '../../../core/presentation/workflow.dart';
import '../application/inventory_controller.dart';
import '../domain/inventory.dart';
import 'batch_form.dart';
import 'product_form.dart';
import 'history_screen.dart';
import 'inventory_widgets.dart';
import 'stock_adjustment.dart';

Future<void> addProduct(
  BuildContext context,
  InventoryController controller,
) async {
  final result = await Navigator.push<Product>(
    context,
    MaterialPageRoute(builder: (_) => ProductForm(controller: controller)),
  );
  if (result != null && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Item saved')));
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
          controller: controller,
          productId: result.meta.id,
        ),
      ),
    );
  }
}

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.controller,
    required this.productId,
  });
  final InventoryController controller;
  final String productId;
  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  bool showEmpty = false, showArchived = false;
  final save = SaveController();
  Future<void> archive(Product product) async {
    if (save.saving) return;
    if (!await confirmAction(
      context,
      title: product.archived ? 'Restore item?' : 'Archive item?',
      message: product.archived
          ? 'The item will return to active inventory. Archived batches stay archived.'
          : 'The item will leave active inventory. Its batches and stock history will be retained.',
      action: product.archived ? 'Restore' : 'Archive',
    )) {
      return;
    }
    save.newAttempt();
    final done = await save.run((id) async {
      await (await widget.controller.repository).archiveProduct(
        product.meta.id,
        archived: !product.archived,
        operationId: id,
      );
      return true;
    });
    if (done == true) widget.controller.changed();
  }

  @override
  void dispose() {
    save.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Item details')),
    body: SafeArea(
      child: InventoryData(
        controller: widget.controller,
        load: () async {
          final today = widget.controller.clock.today();
          final repo = await widget.controller.repository,
              p = await repo.product(widget.productId);
          final batches = await repo.batches(widget.productId),
              units = await (await widget.controller.settings).units();
          final unit = units.singleWhere((u) => u.meta.id == p.unitId).name;
          batches.sort((a, b) {
            final left = a.expiry?.effectiveExpiry.iso ?? '9999',
                right = b.expiry?.effectiveExpiry.iso ?? '9999';
            final order = left.compareTo(right);
            return order == 0 ? a.meta.id.compareTo(b.meta.id) : order;
          });
          return (
            today: today,
            product: p,
            batches: batches,
            unit: unit,
            item: InventoryItem.fromBatches(p, unit, batches, today),
            recent: await repo.productMovements(p.meta.id, limit: 5),
          );
        },
        builder: (context, data) => ListenableBuilder(
          listenable: save,
          builder: (context, _) => PageContent(
            storageKey: 'product-${widget.productId}',
            children: [
              ContentText(
                data.product.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              if (data.product.archived)
                const StatusBadge(
                  label: 'Archived item',
                  icon: Icons.archive_outlined,
                ),
              const SizedBox(height: 16),
              InventoryQuantities(item: data.item),
              const SizedBox(height: 16),
              Text('Minimum stock: ${data.product.minimumStock} ${data.unit}'),
              Text('Expiry warning: ${data.product.warningDays} days'),
              if (data.product.category?.isNotEmpty ?? false)
                ContentText('Category: ${data.product.category}'),
              if (data.product.notes?.isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ContentText(data.product.notes!),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!data.product.archived)
                    TextButton.icon(
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit item'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProductForm(
                            controller: widget.controller,
                            product: data.product,
                          ),
                        ),
                      ),
                    ),
                  PopupMenuButton<String>(
                    tooltip: 'Item actions',
                    enabled: !save.saving,
                    onSelected: (_) => archive(data.product),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'archive',
                        enabled:
                            data.product.archived || data.item.physical == 0,
                        child: Text(
                          data.product.archived
                              ? 'Restore item'
                              : 'Archive item',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (!data.product.archived && data.item.physical > 0)
                const Text(
                  'Archiving is available after all physical stock is removed.',
                ),
              ErrorNotice(save.error),
              if (!data.product.archived) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add stock'),
                      onPressed: () => adjustStock(
                        context,
                        widget.controller,
                        widget.productId,
                        remove: false,
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.remove),
                      label: const Text('Remove stock'),
                      onPressed: data.item.physical == 0
                          ? null
                          : () => adjustStock(
                              context,
                              widget.controller,
                              widget.productId,
                              remove: true,
                            ),
                    ),
                  ],
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Add new batch'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BatchForm(
                        controller: widget.controller,
                        product: data.product,
                        unit: data.unit,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Section(
                title: 'Batches',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show empty batches'),
                      value: showEmpty,
                      onChanged: (v) => setState(() => showEmpty = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show archived batches'),
                      value: showArchived,
                      onChanged: (v) => setState(() => showArchived = v),
                    ),
                    if (data.batches.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No batches yet. Add a new batch for each delivery.',
                        ),
                      ),
                    if (data.batches.isNotEmpty &&
                        !data.batches.any(
                          (b) => b.archived
                              ? showArchived
                              : showEmpty || b.quantity > 0,
                        ))
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No stocked batches. Turn on Show empty batches to review earlier deliveries.',
                        ),
                      ),
                    for (final batch in data.batches.where(
                      (b) => b.archived
                          ? showArchived
                          : showEmpty || b.quantity > 0,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                InkWell(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => BatchDetailScreen(
                                        controller: widget.controller,
                                        batchId: batch.meta.id,
                                      ),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: BatchSummary(
                                      batch: batch,
                                      unit: data.unit,
                                      today: data.today,
                                      warningDays: data.product.warningDays,
                                    ),
                                  ),
                                ),
                                if (!batch.archived && !data.product.archived)
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      TextButton(
                                        onPressed: () => adjustStock(
                                          context,
                                          widget.controller,
                                          widget.productId,
                                          remove: false,
                                          batchId: batch.meta.id,
                                        ),
                                        child: Text('Add to ${batch.label}'),
                                      ),
                                      TextButton(
                                        onPressed: batch.quantity == 0
                                            ? null
                                            : () => adjustStock(
                                                context,
                                                widget.controller,
                                                widget.productId,
                                                remove: true,
                                                batchId: batch.meta.id,
                                              ),
                                        child: Text(
                                          'Remove from ${batch.label}',
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Section(
                title: 'Recent stock history',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (data.recent.isEmpty)
                      const Text('No stock movements yet.'),
                    for (final m in data.recent)
                      MovementTile(
                        movement: m,
                        batchLabel: data.batches
                            .singleWhere((b) => b.meta.id == m.batchId)
                            .label,
                        unit: data.unit,
                      ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HistoryScreen(
                            controller: widget.controller,
                            productId: widget.productId,
                            unit: data.unit,
                          ),
                        ),
                      ),
                      child: const Text('View all stock history'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class BatchDetailScreen extends StatefulWidget {
  const BatchDetailScreen({
    super.key,
    required this.controller,
    required this.batchId,
  });
  final InventoryController controller;
  final String batchId;
  @override
  State<BatchDetailScreen> createState() => _BatchDetailScreenState();
}

class _BatchDetailScreenState extends State<BatchDetailScreen> {
  final save = SaveController();
  Future<void> archive(Batch batch) async {
    if (save.saving) return;
    if (!await confirmAction(
      context,
      title: batch.archived ? 'Restore batch?' : 'Archive batch?',
      message: 'Stock history and dates will be retained.',
      action: batch.archived ? 'Restore' : 'Archive',
    )) {
      return;
    }
    save.newAttempt();
    final done = await save.run((id) async {
      await (await widget.controller.repository).archiveBatch(
        batch.meta.id,
        archived: !batch.archived,
        operationId: id,
      );
      return true;
    });
    if (done == true) widget.controller.changed();
  }

  @override
  void dispose() {
    save.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Batch details')),
    body: SafeArea(
      child: InventoryData(
        controller: widget.controller,
        load: () async {
          final today = widget.controller.clock.today();
          final repo = await widget.controller.repository,
              b = await repo.batch(widget.batchId),
              p = await repo.product(b.productId);
          final units = await (await widget.controller.settings).units();
          return (
            today: today,
            batch: b,
            product: p,
            unit: units.singleWhere((u) => u.meta.id == p.unitId).name,
            recent: await repo.movements(b.meta.id, limit: 5),
          );
        },
        builder: (context, data) => ListenableBuilder(
          listenable: save,
          builder: (context, _) => PageContent(
            storageKey: 'batch-${widget.batchId}',
            children: [
              ContentText(
                data.product.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              BatchSummary(
                batch: data.batch,
                unit: data.unit,
                today: data.today,
                warningDays: data.product.warningDays,
              ),
              const SizedBox(height: 24),
              Section(
                title: 'Dates',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Received: ${data.batch.receivedDate.label} · Gregorian',
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Production: ${dateLabel(data.batch.production, absent: 'Not entered')}',
                    ),
                    if (data.batch.production != null)
                      Text(
                        dateEquivalent(data.batch.production!),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 16),
                    Text('Expiry: ${dateLabel(data.batch.expiry)}'),
                    if (data.batch.expiry != null)
                      Text(
                        dateEquivalent(data.batch.expiry!),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (data.batch.expiry?.day == null &&
                        data.batch.expiry != null)
                      const ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text('How month-only expiry works'),
                        children: [
                          Text(
                            'For inventory alerts, expiry is the last day of the entered month in its original calendar. The printed date remains month-only.',
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (data.batch.notes?.isNotEmpty ?? false)
                Section(title: 'Notes', child: ContentText(data.batch.notes!)),
              if (!data.product.archived && !data.batch.archived) ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add stock'),
                      onPressed: () => adjustStock(
                        context,
                        widget.controller,
                        data.product.meta.id,
                        remove: false,
                        batchId: widget.batchId,
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.remove),
                      label: const Text('Remove stock'),
                      onPressed: data.batch.quantity == 0
                          ? null
                          : () => adjustStock(
                              context,
                              widget.controller,
                              data.product.meta.id,
                              remove: true,
                              batchId: widget.batchId,
                            ),
                    ),
                  ],
                ),
                TextButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit batch details'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BatchForm(
                        controller: widget.controller,
                        product: data.product,
                        unit: data.unit,
                        batch: data.batch,
                      ),
                    ),
                  ),
                ),
              ],
              TextButton.icon(
                icon: const Icon(Icons.archive_outlined),
                label: Text(
                  data.batch.archived ? 'Restore batch' : 'Archive batch',
                ),
                onPressed:
                    save.saving ||
                        data.product.archived ||
                        (!data.batch.archived && data.batch.quantity > 0)
                    ? null
                    : () => archive(data.batch),
              ),
              if (data.product.archived)
                const Text('Restore the item before changing this batch.')
              else if (data.batch.quantity > 0)
                const Text('Remove all stock before archiving this batch.'),
              ErrorNotice(save.error),
              const SizedBox(height: 24),
              Section(
                title: 'Recent stock history',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final m in data.recent)
                      MovementTile(
                        movement: m,
                        batchLabel: data.batch.label,
                        unit: data.unit,
                      ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HistoryScreen(
                            controller: widget.controller,
                            productId: data.product.meta.id,
                            batchId: widget.batchId,
                            unit: data.unit,
                          ),
                        ),
                      ),
                      child: const Text('View all stock history'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
