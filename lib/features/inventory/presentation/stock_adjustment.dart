import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/domain/validation.dart';
import '../../../core/presentation/components.dart';
import '../../../core/presentation/app_theme.dart';
import '../../../core/presentation/form_fields.dart';
import '../../../core/presentation/workflow.dart';
import '../application/inventory_controller.dart';
import '../domain/inventory.dart';
import 'batch_form.dart';
import 'inventory_widgets.dart';
import 'detail_screens.dart';

Future<void> adjustStock(
  BuildContext context,
  InventoryController controller,
  String productId, {
  required bool remove,
  String? batchId,
}) async {
  if (controller.adjustmentOpen) return;
  controller.adjustmentOpen = true;
  try {
    final repo = await controller.repository;
    final product = await repo.product(productId);
    final units = await (await controller.settings).units();
    final unit = units.singleWhere((u) => u.meta.id == product.unitId).name;
    final all = await repo.batches(productId);
    if (!context.mounted) return;
    final eligible = all
        .where((b) => !b.archived && (!remove || b.quantity > 0))
        .toList();
    if (product.archived) {
      throw const ValidationException(
        'Restore this item before changing stock.',
      );
    }
    if (remove && eligible.isEmpty) {
      throw const ValidationException(
        'There is no stock to remove from this item.',
      );
    }
    if (batchId != null && !eligible.any((b) => b.meta.id == batchId)) {
      throw const ValidationException(
        'This batch is no longer available for this adjustment.',
      );
    }
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      sheetAnimationStyle: reduceMotion(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(duration: Duration(milliseconds: 200)),
      enableDrag: false,
      showDragHandle: false,
      builder: (_) => StockAdjustment(
        controller: controller,
        product: product,
        unit: unit,
        batches: eligible,
        remove: remove,
        batchId: batchId,
      ),
    );
    if (!context.mounted) return;
    if (result == 'new_batch') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              BatchForm(controller: controller, product: product, unit: unit),
        ),
      );
    } else if (result is StockMovement) {
      showStockUndo(context, controller, result, unit);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(persistenceMessage(e))));
    }
  } finally {
    controller.adjustmentOpen = false;
  }
}

void showStockUndo(
  BuildContext context,
  InventoryController controller,
  StockMovement movement,
  String unit,
) {
  final operationId = const Uuid().v4();
  var undoing = false;
  Future<void> undo() async {
    if (undoing) return;
    undoing = true;
    try {
      await (await controller.repository).reverse(
        operationId: operationId,
        movementId: movement.meta.id,
      );
      controller.changed();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Stock change undone')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 10),
            content: Text(
              e is ValidationException
                  ? 'This change can no longer be undone because stock has changed. Correct it with a new manual adjustment.'
                  : persistenceMessage(e),
            ),
            action: SnackBarAction(
              label: e is ValidationException ? 'View batch' : 'Retry',
              onPressed: () {
                if (e is ValidationException) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BatchDetailScreen(
                        controller: controller,
                        batchId: movement.batchId,
                      ),
                    ),
                  );
                } else {
                  undo();
                }
              },
            ),
          ),
        );
      }
    } finally {
      undoing = false;
    }
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(
        '${movement.delta > 0 ? 'Added' : 'Removed'} ${movement.delta.abs()} $unit',
      ),
      action: SnackBarAction(label: 'Undo', onPressed: undo),
    ),
  );
}

class StockAdjustment extends StatefulWidget {
  const StockAdjustment({
    super.key,
    required this.controller,
    required this.product,
    required this.unit,
    required this.batches,
    required this.remove,
    this.batchId,
  });
  final InventoryController controller;
  final Product product;
  final String unit;
  final List<Batch> batches;
  final bool remove;
  final String? batchId;
  @override
  State<StockAdjustment> createState() => _StockAdjustmentState();
}

class _StockAdjustmentState extends State<StockAdjustment> {
  final form = GlobalKey<FormState>(),
      quantity = TextEditingController(),
      note = TextEditingController();
  final save = SaveController();
  final quantityFocus = FocusNode();
  String? selected;
  String lastInput = '';
  String get input => '$selected\u0000${quantity.text}\u0000${note.text}';
  bool dirty = false;
  double dragDistance = 0;
  late List<Batch> batches;
  Batch? get batch => selected == null
      ? null
      : batches.where((b) => b.meta.id == selected).firstOrNull;
  int? get amount {
    try {
      return wholeQuantity(quantity.text, positive: true);
    } catch (_) {
      return null;
    }
  }

  int? get result => batch == null || amount == null
      ? null
      : batch!.quantity + (widget.remove ? -amount! : amount!);
  bool get valid => result != null && result! >= 0 && result! <= maxQuantity;
  @override
  void initState() {
    super.initState();
    batches = widget.batches;
    selected =
        widget.batchId ?? (batches.length == 1 ? batches.single.meta.id : null);
    lastInput = input;
    quantity.addListener(changed);
    note.addListener(changed);
  }

  void changed() {
    if (lastInput == input) return;
    lastInput = input;
    if (mounted) setState(() => dirty = true);
    save.newAttempt();
  }

  Future<void> submit() async {
    if (save.saving || !valid || !validateAndReveal(form)) return;
    final batchId = batch!.meta.id,
        delta = widget.remove ? -amount! : amount!,
        savedNote = note.text.isEmpty ? null : note.text;
    FocusScope.of(context).unfocus();
    final movement = await save.run(
      (id) async => (await widget.controller.repository).adjust(
        operationId: id,
        batchId: batchId,
        delta: delta,
        note: savedNote,
      ),
    );
    if (movement != null && mounted) {
      setState(() => dirty = false);
      widget.controller.changed();
      Navigator.pop(context, movement);
    } else if (mounted && !save.uncertain) {
      try {
        final fresh = await (await widget.controller.repository).batches(
          widget.product.meta.id,
        );
        if (mounted) {
          setState(() => batches = fresh.where((b) => !b.archived).toList());
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    quantity.removeListener(changed);
    note.removeListener(changed);
    quantity.dispose();
    note.dispose();
    quantityFocus.dispose();
    save.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([save, widget.controller]),
    builder: (context, _) => GuardedForm(
      dirty: dirty,
      saving: save.saving,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: math.min(
            680,
            math.max(
              0,
              MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom -
                  MediaQuery.paddingOf(context).top -
                  24,
            ),
          ),
          child: Column(
            children: [
              GestureDetector(
                key: const ValueKey('adjustment-dismiss-handle'),
                behavior: HitTestBehavior.opaque,
                // Native BottomSheet drag pops directly, bypassing PopScope.
                // Use maybePop so dirty/saving input receives the same guard as Back.
                onVerticalDragStart: (_) => dragDistance = 0,
                onVerticalDragUpdate: (details) =>
                    dragDistance += details.delta.dy,
                onVerticalDragEnd: (details) {
                  if (!save.saving &&
                      (dragDistance > 48 ||
                          (details.primaryVelocity ?? 0) > 300)) {
                    Navigator.maybePop(context);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.remove ? 'Remove stock' : 'Add stock',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close adjustment',
                        onPressed: save.saving
                            ? null
                            : () => Navigator.maybePop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: FormViewport(
                  hasError: save.error != null,
                  content: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ExcludeFocus(
                      excluding: save.saving || save.uncertain,
                      child: IgnorePointer(
                        ignoring: save.saving || save.uncertain,
                        child: Form(
                          key: form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ContentText(
                                widget.product.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              if (!widget.remove && widget.batchId == null) ...[
                                const Text('Different dates? Add a new batch.'),
                                TextButton.icon(
                                  icon: const Icon(Icons.add_box_outlined),
                                  label: const Text('New batch'),
                                  onPressed: () async {
                                    if (dirty &&
                                        !await confirmAction(
                                          context,
                                          title: 'Discard adjustment?',
                                          message:
                                              'Open a new batch form instead of this adjustment?',
                                          action: 'Open new batch',
                                        )) {
                                      return;
                                    }
                                    if (context.mounted) {
                                      Navigator.pop(context, 'new_batch');
                                    }
                                  },
                                ),
                              ],
                              if (widget.batchId == null && batches.length > 1)
                                LabeledControl(
                                  label: 'Choose a batch',
                                  child: DropdownButtonFormField<String>(
                                    initialValue: selected,
                                    isExpanded: true,
                                    itemHeight: null,
                                    selectedItemBuilder: (_) => [
                                      for (final b in batches)
                                        Text(
                                          '${b.label} · ${b.meta.id.substring(0, 8)}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                    hint: const Text('Select batch'),
                                    validator: (v) => v == null
                                        ? 'Choose the batch to change.'
                                        : null,
                                    items: [
                                      for (final b in batches)
                                        DropdownMenuItem(
                                          value: b.meta.id,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ContentText(
                                                  '${b.label} · ${b.quantity} ${widget.unit}',
                                                ),
                                                Text(dateLabel(b.expiry)),
                                                Text(
                                                  'Received ${b.receivedDate.label} · ${b.meta.id.substring(0, 8)}',
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                    onChanged: (id) {
                                      setState(() => selected = id);
                                      changed();
                                      quantityFocus.requestFocus();
                                    },
                                  ),
                                ),
                              if (batch != null) ...[
                                const SizedBox(height: 16),
                                BatchSummary(
                                  batch: batch!,
                                  unit: widget.unit,
                                  today: widget.controller.clock.today(),
                                  warningDays: widget.product.warningDays,
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (batches.isEmpty)
                                const Text(
                                  'No existing batches. Choose New batch to add a delivery.',
                                ),
                              if (batches.isNotEmpty) ...[
                                AppTextField(
                                  controller: quantity,
                                  focusNode: quantityFocus,
                                  autofocus: selected != null,
                                  label:
                                      'Quantity to ${widget.remove ? 'remove' : 'add'}',
                                  forceLtr: true,
                                  keyboardType: TextInputType.number,
                                  validator: (v) => validationMessage(() {
                                    final n = wholeQuantity(
                                      v ?? '',
                                      positive: true,
                                    );
                                    if (widget.remove &&
                                        batch != null &&
                                        n > batch!.quantity) {
                                      throw ValidationException(
                                        'Only ${batch!.quantity} ${widget.unit} are available in this batch.',
                                      );
                                    }
                                  }),
                                ),
                                if (result != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    child: PreviewPanel(
                                      child: Text(
                                        result! < 0
                                            ? 'Only ${batch!.quantity} ${widget.unit} are available in this batch.'
                                            : 'Current ${batch!.quantity} → After ${widget.remove ? 'removing' : 'adding'} $result ${widget.unit}',
                                        style: TextStyle(
                                          color: valid
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  title: const Text('Note (optional)'),
                                  children: [
                                    AppTextField(
                                      controller: note,
                                      label: 'Adjustment note',
                                      maxLines: 2,
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  footer: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (save.error != null)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 100),
                              child: SingleChildScrollView(
                                child: ErrorNotice(save.error),
                              ),
                            ),
                          FilledButton(
                            onPressed: save.saving || !valid ? null : submit,
                            child: Text(
                              save.saving
                                  ? 'Saving…'
                                  : widget.remove
                                  ? 'Remove stock'
                                  : 'Add stock',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
