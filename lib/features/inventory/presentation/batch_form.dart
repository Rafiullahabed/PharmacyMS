import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/domain/validation.dart';
import '../../../core/presentation/components.dart';
import '../../../core/presentation/workflow.dart';
import '../application/inventory_controller.dart';
import '../domain/inventory.dart';
import 'batch_fields.dart';
import 'inventory_widgets.dart';

class BatchForm extends StatefulWidget {
  const BatchForm({
    super.key,
    required this.controller,
    required this.product,
    required this.unit,
    this.batch,
  });
  final InventoryController controller;
  final Product product;
  final String unit;
  final Batch? batch;
  @override
  State<BatchForm> createState() => _BatchFormState();
}

class _BatchFormState extends State<BatchForm> {
  final form = GlobalKey<FormState>(), fields = GlobalKey<BatchFieldsState>();
  final save = SaveController();
  bool dirty = false, reviewing = false;
  void changed() {
    if (mounted) setState(() => dirty = true);
    save.newAttempt();
  }

  Future<void> submit() async {
    if (save.saving || reviewing || !validateAndReveal(form)) return;
    BatchDraft draft;
    try {
      draft = fields.currentState!.value();
      draft.validate(creating: widget.batch == null);
    } on ValidationException catch (e) {
      setState(() => save.error = e.message);
      return;
    }
    final old = widget.batch;
    reviewing = true;
    if (old != null &&
        (jsonEncode(old.production?.toMap()) !=
                jsonEncode(draft.production?.toMap()) ||
            jsonEncode(old.expiry?.toMap()) !=
                jsonEncode(draft.expiry?.toMap()) ||
            old.receivedDate != draft.receivedDate)) {
      final confirmed = await confirmAction(
        context,
        title: 'Review date correction',
        message:
            'Received: ${old.receivedDate.label} → ${draft.receivedDate.label}\n\nProduction:\n${dateLabel(old.production, absent: 'Not entered')}\n→ ${dateLabel(draft.production, absent: 'Not entered')}\n\nExpiry:\n${dateLabel(old.expiry)}\n→ ${dateLabel(draft.expiry)}\n\nQuantity stays ${old.quantity} ${widget.unit}.',
        action: 'Save correction',
      );
      if (!confirmed) {
        reviewing = false;
        return;
      }
    }
    final result = await save.run(
      (id) async => (await widget.controller.repository).saveBatch(
        operationId: id,
        productId: widget.product.meta.id,
        batchId: old?.meta.id,
        draft: draft,
      ),
    );
    reviewing = false;
    if (result != null && mounted) {
      setState(() => dirty = false);
      widget.controller.changed();
      Navigator.pop(context, result);
    }
  }

  @override
  void dispose() {
    save.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: widget.batch == null ? 'Add new batch' : 'Edit batch details',
    formKey: form,
    save: save,
    dirty: dirty,
    onSave: submit,
    children: [
      ContentText(
        widget.product.name,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Text('Counting unit: ${widget.unit}'),
      const SizedBox(height: 16),
      if (widget.batch != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Quantity: ${widget.batch!.quantity} ${widget.unit}. Use Add stock or Remove stock to change it.',
          ),
        ),
      BatchFields(
        key: fields,
        today: widget.controller.clock.today(),
        initial: widget.batch,
        creating: widget.batch == null,
        onChanged: changed,
      ),
    ],
  );
}
