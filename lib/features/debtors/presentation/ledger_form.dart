import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/domain/dates.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/validation.dart';
import '../../../core/presentation/business_date_input.dart';
import '../../../core/presentation/components.dart';
import '../../../core/presentation/form_fields.dart';
import '../../../core/presentation/workflow.dart';
import '../application/debt_controller.dart';
import '../domain/debt.dart';
import 'product_name_picker.dart';

class LedgerForm extends StatefulWidget {
  const LedgerForm({
    super.key,
    required this.controller,
    required this.customer,
    required this.balance,
    required this.kind,
    this.entry,
  });
  final DebtController controller;
  final Customer customer;
  final Money balance;
  final LedgerKind kind;
  final LedgerEntry? entry;
  @override
  State<LedgerForm> createState() => _LedgerFormState();
}

class _LedgerFormState extends State<LedgerForm> {
  final form = GlobalKey<FormState>(), save = SaveController();
  final date = TextEditingController(),
      amount = TextEditingController(),
      description = TextEditingController(),
      reason = TextEditingController();
  final descriptionFocus = FocusNode();
  late LedgerKind kind = widget.entry?.kind ?? widget.kind;
  bool dirty = false, previewing = false;
  String? previewError;
  LedgerPreview? preview;
  Timer? debounce;
  int generation = 0;
  String lastInput = '';
  @override
  void initState() {
    super.initState();
    date.text = (widget.entry?.date ?? widget.controller.clock.today()).iso;
    amount.text = widget.entry?.amount.decimal ?? '';
    description.text = widget.entry?.description ?? '';
    lastInput = input;
    for (final field in [date, amount, description, reason]) {
      field.addListener(changed);
    }
    widget.controller.addListener(refresh);
    schedulePreview();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    });
  }

  String get input =>
      '${date.text}\u0000${amount.text}\u0000${description.text}\u0000${reason.text}\u0000${kind.name}';
  LedgerDraft draft() => LedgerDraft(
    date: BusinessDate.parse(normalizeDigits(date.text.trim())),
    kind: kind,
    amount: Money.parse(amount.text),
    description: description.text,
  );
  void changed() {
    if (input == lastInput) return;
    lastInput = input;
    save.newAttempt();
    setState(() => dirty = true);
    schedulePreview();
  }

  void refresh() {
    if (!save.uncertain) schedulePreview();
  }

  void schedulePreview() {
    debounce?.cancel();
    final ticket = ++generation;
    setState(() {
      preview = null;
      previewError = null;
      previewing = true;
    });
    if (amount.text.trim().isEmpty || date.text.trim().isEmpty) {
      setState(() => previewing = false);
      return;
    }
    debounce = Timer(const Duration(milliseconds: 180), () async {
      try {
        final value = draft();
        value.validate(widget.controller.clock);
        final result = await (await widget.controller.repository).preview(
          widget.customer.meta.id,
          entryId: widget.entry?.meta.id,
          draft: value,
        );
        if (mounted && ticket == generation) {
          setState(() {
            preview = result;
            previewing = false;
          });
        }
      } catch (error) {
        if (mounted && ticket == generation) {
          setState(() {
            previewing = false;
            previewError = error is ValidationException
                ? error.message
                : 'Unable to preview this ledger. Your input is kept. Retry the preview.';
          });
        }
      }
    });
  }

  Future<void> insertName() async {
    final selection = description.selection;
    final value = await pickProductName(context, widget.controller);
    if (value == null || !mounted) return;
    final start = selection.isValid
        ? selection.start.clamp(0, description.text.length)
        : description.text.length;
    final end = selection.isValid
        ? selection.end.clamp(start, description.text.length)
        : start;
    description.value = TextEditingValue(
      text: description.text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    descriptionFocus.requestFocus();
  }

  Future<void> submit() async {
    if (save.saving || !validateAndReveal(form)) return;
    if (!save.uncertain && (preview == null || previewing)) return;
    final result = await save.run((operation) async {
      final repo = await widget.controller.repository, value = draft();
      return widget.entry == null
          ? repo.addEntry(
              operationId: operation,
              customerId: widget.customer.meta.id,
              date: value.date,
              kind: value.kind,
              amount: value.amount,
              description: value.description,
            )
          : repo.editEntry(
              operationId: operation,
              id: widget.entry!.meta.id,
              date: value.date,
              kind: value.kind,
              amount: value.amount,
              description: value.description,
              reason: reason.text.trim().isEmpty
                  ? 'Corrected in app'
                  : reason.text,
            );
    });
    if (!mounted) return;
    setState(() {});
    if (result != null) {
      widget.controller.changed();
      setState(() => dirty = false);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.entry != null
                  ? 'Ledger entry corrected'
                  : kind == LedgerKind.payment
                  ? 'Payment recorded'
                  : 'Debt recorded',
            ),
          ),
        );
        Navigator.pop(context, result);
      }
    }
  }

  @override
  void dispose() {
    generation++;
    debounce?.cancel();
    widget.controller.removeListener(refresh);
    for (final c in [date, amount, description, reason]) {
      c.dispose();
    }
    descriptionFocus.dispose();
    save.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: widget.entry == null ? kind.action : 'Edit ledger entry',
    formKey: form,
    save: save,
    onSave: submit,
    dirty: dirty,
    canSave: save.uncertain || (!previewing && preview != null),
    saveLabel: save.uncertain
        ? 'Retry same save'
        : widget.entry == null
        ? kind.action
        : 'Save correction',
    children: [
      ContentText(
        widget.customer.name,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Text(
        'Current outstanding: ${(preview?.before ?? widget.balance).formatted}',
      ),
      const SizedBox(height: 16),
      if (widget.entry != null) ...[
        Text(
          'Original: ${widget.entry!.kind.label} · ${widget.entry!.amount.formatted}\n${widget.entry!.date.label}',
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Original description'),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ContentText(
                widget.entry!.description.isEmpty
                    ? 'No description entered.'
                    : widget.entry!.description,
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final type in LedgerKind.values)
              ChoiceChip(
                label: Text(type == LedgerKind.debt ? 'Debt' : 'Payment'),
                selected: kind == type,
                onSelected: (_) {
                  kind = type;
                  changed();
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
      BusinessDateInput(
        controller: date,
        label: 'Business date',
        today: widget.controller.clock.today(),
        rejectFuture: true,
      ),
      const SizedBox(height: 16),
      AppTextField(
        controller: amount,
        label: kind == LedgerKind.debt
            ? 'Debt amount (AFN)'
            : 'Payment amount (AFN)',
        forceLtr: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (value) => validationMessage(() {
          if (Money.parse(value ?? '').minor <= 0) {
            throw const ValidationException('Enter a positive amount.');
          }
        }),
      ),
      if (kind == LedgerKind.payment && widget.entry == null)
        TextButton.icon(
          icon: const Icon(Icons.done_all),
          label: const Text('Pay full balance'),
          onPressed: () =>
              amount.text = (preview?.before ?? widget.balance).decimal,
        ),
      const SizedBox(height: 16),
      AppTextField(
        controller: description,
        focusNode: descriptionFocus,
        label: 'Description',
        maxLines: 5,
        hint: 'Write what the customer received or why this amount is owed.',
      ),
      TextButton.icon(
        onPressed: insertName,
        icon: const Icon(Icons.text_fields),
        label: const Text('Insert item name'),
      ),
      const Text(
        'Suggestions insert text only. Amounts, inventory and daily records stay separate.',
      ),
      if (widget.entry != null) ...[
        const SizedBox(height: 16),
        AppTextField(
          controller: reason,
          label: 'Correction reason (optional)',
          maxLines: 2,
        ),
      ],
      const SizedBox(height: 16),
      if (previewing)
        const Text('Checking chronological balances…')
      else if (preview != null)
        PreviewPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Outstanding before: ${preview!.before.formatted}'),
              Text(
                'Outstanding after saving: ${preview!.after.formatted}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'Balance immediately after this entry: ${preview!.atEntry!.formatted}',
              ),
            ],
          ),
        )
      else if (previewError != null) ...[
        ErrorNotice(previewError),
        TextButton(
          onPressed: schedulePreview,
          child: const Text('Retry preview'),
        ),
      ] else
        const Text('Enter a date and amount to preview the resulting balance.'),
    ],
  );
}
