import 'package:flutter/material.dart';
import '../../../core/presentation/components.dart';
import '../../../core/presentation/app_theme.dart';
import '../application/inventory_controller.dart';
import '../domain/inventory.dart';
import 'inventory_widgets.dart';
import 'inventory_screen.dart';
import 'detail_screens.dart';

class InventoryHome extends StatelessWidget {
  const InventoryHome({
    super.key,
    required this.controller,
    this.betweenSections,
  });
  final InventoryController controller;
  final Widget? betweenSections;

  void open(BuildContext context, InventoryFilter filter) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: pageAppBar(context, title: filter.label),
        body: SafeArea(
          child: InventoryScreen(controller: controller, initialFilter: filter),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => InventoryData(
    controller: controller,
    load: () async =>
        (await controller.repository).dashboard(controller.clock.today()),
    builder: (context, data) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: 'Inventory',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${data.overview.products} active products · ${data.overview.batches} active batches',
              ),
              const SizedBox(height: 12),
              if (data.overview.products > 0)
                Card(
                  elevation: 0,
                  color: AppColors.canvas,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final pair in [
                          (InventoryFilter.lowStock, data.overview.lowStock),
                          (
                            InventoryFilter.outOfStock,
                            data.overview.outOfStock,
                          ),
                          (
                            InventoryFilter.expired,
                            data.overview.expiredBatches,
                          ),
                          (
                            InventoryFilter.expiresToday,
                            data.overview.expiresTodayBatches,
                          ),
                          (
                            InventoryFilter.expiringSoon,
                            data.overview.expiringBatches,
                          ),
                        ])
                          _AlertCount(
                            filter: pair.$1,
                            count: pair.$2,
                            onTap: () => open(context, pair.$1),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (data.overview.products > 0)
                Text(
                  'Counts can overlap. Expiring soon includes expires today.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (!data.overview.hasAlerts)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: StatusBadge(
                    label: 'No current inventory alerts',
                    icon: Icons.check_circle_outline,
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => addProduct(context, controller),
                    icon: const Icon(Icons.add),
                    label: Text(
                      data.overview.products == 0
                          ? 'Add your first item'
                          : 'Add item',
                    ),
                  ),
                  TextButton(
                    onPressed: () => open(context, InventoryFilter.all),
                    child: const Text('View inventory'),
                  ),
                ],
              ),
            ],
          ),
        ),
        ?betweenSections,
        if (data.overview.hasAlerts)
          Section(
            title: 'Needs attention',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Expiry issues and items that need replenishing.'),
                for (final alert in data.expiryAttention)
                  _AttentionRow(
                    title: alert.product.name,
                    description:
                        '${batchStatus(alert.batch, data.today, alert.product.warningDays)} · ${alert.batch.quantity} ${alert.unit}\n${alert.batch.label} · ${alert.batch.meta.id.substring(0, 8)}\n${dateLabel(alert.batch.expiry)}',
                    icon: Icons.event_outlined,
                    destination: 'Open batch ${alert.batch.label}',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BatchDetailScreen(
                          controller: controller,
                          batchId: alert.batch.meta.id,
                        ),
                      ),
                    ),
                  ),
                for (final item in data.stockAttention)
                  _AttentionRow(
                    title: item.product.name,
                    description:
                        '${item.outOfStock ? 'Out of stock' : 'Low stock'}${item.outOfStock && item.lowStock ? ' · Low stock' : ''}\n${item.usable} ${item.unit} usable · ${item.physical} physical\nMinimum: ${item.product.minimumStock} ${item.unit}',
                    icon: inventoryFilterIcon(
                      item.outOfStock
                          ? InventoryFilter.outOfStock
                          : InventoryFilter.lowStock,
                    ),
                    destination: 'Open item details',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProductDetailScreen(
                          controller: controller,
                          productId: item.product.meta.id,
                        ),
                      ),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () =>
                      open(context, InventoryFilter.needsAttention),
                  icon: const Icon(Icons.checklist_outlined),
                  label: const Text('View all items needing attention'),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _AlertCount extends StatelessWidget {
  const _AlertCount({
    required this.filter,
    required this.count,
    required this.onTap,
  });
  final InventoryFilter filter;
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final noun = filter.isExpiry
        ? (count == 1 ? 'batch' : 'batches')
        : (count == 1 ? 'product' : 'products');
    final label = '${filter.label}: $count $noun';
    return Semantics(
      label: label,
      hint: 'Open filtered inventory',
      button: true,
      onTap: onTap,
      excludeSemantics: true,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: count == 0
              ? AppColors.secondary
              : filter == InventoryFilter.expired ||
                    filter == InventoryFilter.outOfStock
              ? AppColors.danger
              : AppColors.warning,
        ),
        onPressed: onTap,
        child: Row(
          children: [
            Icon(inventoryFilterIcon(filter), size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.title,
    required this.description,
    required this.icon,
    required this.destination,
    required this.onTap,
  });
  final String title, description, destination;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$title. $description',
    hint: destination,
    button: true,
    onTap: onTap,
    excludeSemantics: true,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: MediaQuery.textScalerOf(context).scale(16) > 24
          ? null
          : Icon(icon),
      title: ContentText(title),
      subtitle: Text(description),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
