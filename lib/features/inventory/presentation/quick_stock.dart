import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/domain/validation.dart';
import '../../../core/presentation/app_theme.dart';
import '../../../core/presentation/components.dart';
import '../../../core/presentation/workflow.dart';
import '../application/inventory_controller.dart';
import '../domain/inventory.dart';
import 'batch_form.dart';
import 'inventory_widgets.dart';
import 'stock_adjustment.dart';

/// Single-unit shortcuts still write normal immutable stock movements.
Future<void> quickAdjustStock(
  BuildContext context,
  InventoryController controller,
  String productId, {
  required bool remove,
}) async {
  if (controller.adjustmentOpen) return;
  controller.adjustmentOpen = true;
  ScaffoldMessenger.of(context).clearSnackBars();
  try {
    final repo = await controller.repository;
    final product = await repo.product(productId);
    if (product.archived) {
      throw const ValidationException(
        'Restore this item before changing stock.',
      );
    }
    final units = await (await controller.settings).units();
    final unit = units.singleWhere((u) => u.meta.id == product.unitId).name;
    final batches = (await repo.batches(
      productId,
    )).where((b) => !b.archived && (!remove || b.quantity > 0)).toList();
    if (!context.mounted) return;
    if (batches.isEmpty) {
      if (remove) {
        throw const ValidationException('There is no stock to remove.');
      }
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              BatchForm(controller: controller, product: product, unit: unit),
        ),
      );
      return;
    }
    final delta = remove ? -1 : 1;
    var batchChosen = false;
    final batch = batches.length == 1
        ? batches.single
        : await showModalBottomSheet<Batch>(
            context: context,
            useSafeArea: true,
            isScrollControlled: true,
            sheetAnimationStyle: reduceMotion(context)
                ? AnimationStyle.noAnimation
                : null,
            builder: (sheetContext) => SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * .72,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              remove ? 'Remove 1' : 'Add 1',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cancel stock adjustment',
                            onPressed: () {
                              if (batchChosen) return;
                              batchChosen = true;
                              Navigator.pop(sheetContext);
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          ContentText(
                            product.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Choose a batch. Tap it to apply the one-unit change.',
                          ),
                          const SizedBox(height: 12),
                          for (final batch in batches)
                            Card(
                              child: InkWell(
                                key: ValueKey('quick-batch-${batch.meta.id}'),
                                onTap: () {
                                  if (batchChosen) return;
                                  batchChosen = true;
                                  Navigator.pop(sheetContext, batch);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      BatchSummary(
                                        batch: batch,
                                        unit: unit,
                                        today: controller.clock.today(),
                                        warningDays: product.warningDays,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '${batch.quantity} → ${batch.quantity + delta} $unit',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: AppColors.primary,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
    if (batch == null || !context.mounted) return;
    controller.adjustmentOpen = false;
    await _commit(
      context,
      controller,
      batch.meta.id,
      delta,
      unit,
      const Uuid().v4(),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(persistenceMessage(error))));
    }
  } finally {
    controller.adjustmentOpen = false;
  }
}

Future<void> _commit(
  BuildContext context,
  InventoryController controller,
  String batchId,
  int delta,
  String unit,
  String operationId,
) async {
  if (controller.adjustmentOpen) return;
  controller.adjustmentOpen = true;
  try {
    final movement = await (await controller.repository).adjust(
      operationId: operationId,
      batchId: batchId,
      delta: delta,
    );
    controller.changed();
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      showStockUndo(context, controller, movement, unit);
    }
  } catch (error) {
    // Refresh even after an uncertain acknowledgment; Retry keeps the same ID.
    controller.changed();
    if (context.mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 12),
          content: Text(persistenceMessage(error)),
          action: error is ValidationException
              ? null
              : SnackBarAction(
                  label: 'Retry',
                  onPressed: () => _commit(
                    context,
                    controller,
                    batchId,
                    delta,
                    unit,
                    operationId,
                  ),
                ),
        ),
      );
    }
  } finally {
    controller.adjustmentOpen = false;
  }
}

class QuickStockActions extends StatefulWidget {
  const QuickStockActions({
    super.key,
    required this.controller,
    required this.item,
  });
  final InventoryController controller;
  final InventoryItem item;
  @override
  State<QuickStockActions> createState() => _QuickStockActionsState();
}

class _QuickStockActionsState extends State<QuickStockActions> {
  bool busy = false;
  Future<void> change(bool remove) async {
    if (busy || widget.controller.adjustmentOpen) return;
    setState(() => busy = true);
    await quickAdjustStock(
      context,
      widget.controller,
      widget.item.product.meta.id,
      remove: remove,
    );
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton.outlined(
        tooltip:
            'Remove 1 ${widget.item.unit} from ${widget.item.product.name}',
        onPressed: busy || widget.item.physical == 0
            ? null
            : () => change(true),
        icon: const Icon(Icons.remove),
      ),
      const SizedBox(width: 8),
      IconButton.filled(
        tooltip: 'Add 1 ${widget.item.unit} to ${widget.item.product.name}',
        onPressed: busy ? null : () => change(false),
        icon: const Icon(Icons.add),
      ),
      if (busy)
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Semantics(
            liveRegion: true,
            label: 'Updating stock',
            child: const Icon(Icons.hourglass_empty, size: 18),
          ),
        ),
    ],
  );
}
