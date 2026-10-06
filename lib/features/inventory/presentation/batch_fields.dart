import 'package:flutter/material.dart';
import '../../../core/domain/dates.dart';
import '../../../core/presentation/form_fields.dart';
import '../../../core/presentation/business_date_input.dart';
import '../../../core/domain/validation.dart';
import '../domain/inventory.dart';
import 'date_spec_field.dart';

class BatchFields extends StatefulWidget {
  const BatchFields({
    super.key,
    required this.today,
    required this.onChanged,
    this.initial,
    this.creating = true,
  });
  final BusinessDate today;
  final Batch? initial;
  final bool creating;
  final VoidCallback onChanged;
  @override
  State<BatchFields> createState() => BatchFieldsState();
}

class BatchFieldsState extends State<BatchFields> {
  final quantity = TextEditingController(),
      label = TextEditingController(),
      received = TextEditingController(),
      notes = TextEditingController();
  final production = GlobalKey<DateSpecFieldState>(),
      expiry = GlobalKey<DateSpecFieldState>();
  @override
  void initState() {
    super.initState();
    final b = widget.initial;
    label.text = b?.label ?? '';
    received.text = (b?.receivedDate ?? widget.today).iso;
    notes.text = b?.notes ?? '';
    for (final c in [quantity, label, received, notes]) {
      c.addListener(widget.onChanged);
    }
  }

  BatchDraft value() => BatchDraft(
    receivedDate: BusinessDate.parse(normalizeDigits(received.text.trim())),
    quantity: widget.creating
        ? wholeQuantity(quantity.text, positive: true)
        : 0,
    label: label.text,
    production: production.currentState!.value(),
    expiry: expiry.currentState!.value(),
    notes: notes.text,
  );
  @override
  void dispose() {
    for (final c in [quantity, label, received, notes]) {
      c.removeListener(widget.onChanged);
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.creating) ...[
        QuantityField(
          controller: quantity,
          label: 'Initial quantity',
          positive: true,
        ),
        const SizedBox(height: 16),
      ],
      AppTextField(
        controller: label,
        label: 'Batch / lot label (optional)',
        helper: 'Leave empty to create a readable batch label.',
      ),
      const SizedBox(height: 16),
      BusinessDateInput(
        controller: received,
        label: 'Received date',
        today: widget.today,
      ),
      const SizedBox(height: 24),
      DateSpecField(
        key: production,
        label: 'Production',
        today: widget.today,
        initial: widget.initial?.production,
        onChanged: widget.onChanged,
      ),
      const SizedBox(height: 16),
      DateSpecField(
        key: expiry,
        label: 'Expiry',
        today: widget.today,
        initial: widget.initial?.expiry,
        expiry: true,
        initiallyAbsent: !widget.creating && widget.initial?.expiry == null,
        onChanged: widget.onChanged,
      ),
      FormField<void>(
        validator: (_) => validationMessage(() {
          validateProductionExpiry(
            production.currentState!.value(),
            expiry.currentState!.value(),
          );
        }),
        builder: (field) => field.hasError
            ? Text(
                field.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            : const SizedBox.shrink(),
      ),
      const SizedBox(height: 16),
      AppTextField(
        controller: notes,
        label: 'Batch notes (optional)',
        maxLines: 3,
      ),
    ],
  );
}
