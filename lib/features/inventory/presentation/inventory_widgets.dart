import 'package:flutter/material.dart';
import '../../../core/domain/dates.dart';
import '../../../core/domain/expiry.dart';
import '../../../core/presentation/app_theme.dart';
import '../../../core/presentation/components.dart';
import '../application/inventory_controller.dart';
import '../domain/inventory.dart';

class InventoryData<T> extends StatefulWidget {
  const InventoryData({
    super.key,
    required this.controller,
    required this.load,
    required this.builder,
  });
  final InventoryController controller;
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  @override
  State<InventoryData<T>> createState() => _InventoryDataState<T>();
}

class _InventoryDataState<T> extends State<InventoryData<T>> {
  late Future<T> future;
  @override
  void initState() {
    super.initState();
    future = widget.load();
    widget.controller.addListener(reload);
  }

  void reload() {
    if (mounted) {
      setState(() {
        future = widget.load();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Unable to read local inventory. Your data has not been replaced.',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const LoadingState(label: 'Loading inventory');
      }
      return widget.builder(context, snapshot.data as T);
    },
  );
}

String dateLabel(DateSpec? date, {String absent = 'No expiry date'}) =>
    date?.label ?? absent;
String dateEquivalent(DateSpec date) =>
    'Gregorian: ${date.range.start.label}${date.day == null ? ' – ${date.range.end.label}' : ''}';
String batchStatus(Batch batch, BusinessDate today, int warningDays) =>
    batchStatusLabel(
      BatchInventoryStatus(batch, today, warningDays: warningDays),
    );
String batchStatusLabel(BatchInventoryStatus status) {
  if (!status.active) return 'Archived';
  if (status.empty) return 'Empty batch · No expiry alert';
  return switch (status.dateState) {
    ExpiryState.noExpiry => 'No expiry date',
    ExpiryState.expired => 'Expired stock',
    ExpiryState.expiresToday => 'Expires today',
    ExpiryState.expiringSoon => 'Expires in ${status.daysRemaining} days',
    ExpiryState.inDate => 'In date',
  };
}

IconData inventoryFilterIcon(InventoryFilter filter) => switch (filter) {
  InventoryFilter.all => Icons.inventory_2_outlined,
  InventoryFilter.lowStock => Icons.warning_amber_rounded,
  InventoryFilter.outOfStock => Icons.remove_shopping_cart_outlined,
  InventoryFilter.expiringSoon => Icons.event_outlined,
  InventoryFilter.expired => Icons.event_busy_outlined,
  InventoryFilter.expiresToday => Icons.today_outlined,
  InventoryFilter.needsAttention => Icons.checklist_outlined,
};

class BatchSummary extends StatelessWidget {
  const BatchSummary({
    super.key,
    required this.batch,
    required this.unit,
    required this.today,
    required this.warningDays,
  });
  final Batch batch;
  final String unit;
  final BusinessDate today;
  final int warningDays;
  @override
  Widget build(BuildContext context) {
    final status = BatchInventoryStatus(batch, today, warningDays: warningDays);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ContentText(
          batch.label,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          'Batch ID: ${batch.meta.id.substring(0, 8)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text('${batch.quantity} $unit'),
        Text(dateLabel(batch.expiry)),
        const SizedBox(height: 8),
        StatusBadge(
          label: batchStatusLabel(status),
          icon: !status.active
              ? Icons.archive_outlined
              : status.empty
              ? Icons.inventory_2_outlined
              : status.expiresToday
              ? Icons.today_outlined
              : status.expired
              ? Icons.event_busy_outlined
              : Icons.event_outlined,
          color: status.expired
              ? AppColors.danger
              : status.expiringSoon
              ? AppColors.warning
              : AppColors.secondary,
        ),
      ],
    );
  }
}

class InventoryQuantities extends StatelessWidget {
  const InventoryQuantities({
    super.key,
    required this.item,
    this.compact = false,
  });
  final InventoryItem item;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final quantity = Text(
      '${item.usable} ${item.unit} usable',
      style: Theme.of(context).textTheme.titleLarge,
    );
    final statuses = <Widget>[
      if (item.lowStock)
        const StatusBadge(
          label: 'Low stock',
          icon: Icons.warning_amber_rounded,
          color: AppColors.warning,
        ),
      if (item.outOfStock)
        const StatusBadge(
          label: 'Out of stock',
          icon: Icons.inventory_2_outlined,
        ),
      if (item.expiringBatches > 0)
        StatusBadge(
          label:
              '${item.expiringBatches} expiring ${item.expiringBatches == 1 ? 'batch' : 'batches'}',
          icon: Icons.event_outlined,
          color: AppColors.warning,
        ),
      if (item.expiresTodayBatches > 0)
        StatusBadge(
          label:
              'Expires today: ${item.expiresTodayBatches} ${item.expiresTodayBatches == 1 ? 'batch' : 'batches'}',
          icon: Icons.today_outlined,
          color: AppColors.warning,
        ),
      if (item.expiredBatches > 0)
        StatusBadge(
          label:
              '${item.expiredBatches} expired ${item.expiredBatches == 1 ? 'batch' : 'batches'}',
          icon: Icons.event_busy_outlined,
          color: AppColors.danger,
        ),
    ];
    return Semantics(
      container: true,
      label: 'Stock for ${item.product.name}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact)
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [quantity, ...statuses],
            )
          else
            quantity,
          if (!compact || item.physical != item.usable)
            Text('${item.physical} ${item.unit} physical stock'),
          if (item.expiredQuantity > 0)
            Text(
              '${item.expiredQuantity} ${item.unit} expired',
              style: const TextStyle(color: AppColors.danger),
            ),
          if (!compact && statuses.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: statuses),
          ],
        ],
      ),
    );
  }
}
