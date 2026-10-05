import 'package:flutter/material.dart';
import '../../../core/domain/dates.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/validation.dart';
import '../../../core/presentation/form_fields.dart';
import '../../../core/presentation/workflow.dart';
import '../application/daily_records_controller.dart';
import '../domain/daily_record.dart';
import '../../../core/presentation/business_date_input.dart';

class DailyRecordForm extends StatefulWidget {
  const DailyRecordForm({
    super.key,
    required this.controller,
    this.record,
    this.date,
  });
  final DailyRecordsController controller;
  final DailyRecord? record;
  final BusinessDate? date;
  @override
  State<DailyRecordForm> createState() => _DailyRecordFormState();
}

class _DailyRecordFormState extends State<DailyRecordForm> {
  final form = GlobalKey<FormState>(), save = SaveController();
  final date = TextEditingController(),
      sales = TextEditingController(),
      profit = TextEditingController(),
      note = TextEditingController();
  bool dirty = false;
  DailyRecord? conflict;
  @override
  void initState() {
    super.initState();
    date.text =
        (widget.record?.date ?? widget.date ?? widget.controller.clock.today())
            .iso;
    sales.text = widget.record?.sales.decimal ?? '';
    profit.text = widget.record?.profit.decimal ?? '';
    note.text = widget.record?.note ?? '';
    for (final field in [date, sales, profit, note]) {
      field.addListener(changed);
    }
  }

  void changed() {
    save.newAttempt();
    setState(() {
      dirty = true;
      conflict = null;
    });
  }

  Future<void> submit() async {
    if (save.saving || !validateAndReveal(form)) return;
    final result = await save.run((operation) async {
      final repo = await widget.controller.repository;
      final day = BusinessDate.parse(normalizeDigits(date.text.trim()));
      // Unknown outcomes must reconcile the receipt before checking conflicts.
      if (!save.uncertain) {
        final existing = await repo.onDate(day);
        if (existing != null && existing.meta.id != widget.record?.meta.id) {
          conflict = existing;
          throw const ValidationException(
            'This date already has a record. Open it to edit, or choose another date.',
          );
        }
      }
      return repo.save(
        operationId: operation,
        id: widget.record?.meta.id,
        date: day,
        sales: Money.parse(sales.text),
        profit: Money.parse(profit.text),
        note: note.text.isEmpty ? null : note.text,
      );
    });
    if (!mounted) return;
    setState(() {});
    if (result != null) {
      widget.controller.changed();
      setState(() => dirty = false);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, result);
    }
  }

  Future<void> openConflict() async {
    final record = conflict;
    if (record == null) return;
    if (!await confirmAction(
      context,
      title: 'Open existing record?',
      message:
          'Discard these unsaved inputs and edit the saved figures for ${record.date.label}?',
      action: 'Open record',
    )) {
      return;
    }
    if (!mounted) return;
    final result = await Navigator.push<DailyRecord>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            DailyRecordForm(controller: widget.controller, record: record),
      ),
    );
    if (result != null && mounted) {
      setState(() => dirty = false);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, result);
    }
  }

  @override
  void dispose() {
    for (final field in [date, sales, profit, note]) {
      field.dispose();
    }
    save.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: widget.record == null ? 'Record a day' : 'Edit daily record',
    formKey: form,
    save: save,
    onSave: submit,
    dirty: dirty,
    saveLabel: save.uncertain
        ? 'Retry same save'
        : widget.record == null
        ? 'Save record'
        : 'Save changes',
    children: [
      const Text(
        'Enter your own daily totals. Profit is calculated outside this app.',
      ),
      const SizedBox(height: 16),
      BusinessDateInput(
        controller: date,
        label: 'Business date',
        today: widget.controller.clock.today(),
        rejectFuture: true,
      ),
      if (conflict != null)
        TextButton.icon(
          onPressed: openConflict,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Open existing record'),
        ),
      const SizedBox(height: 16),
      MoneyField(controller: sales, label: 'Sales'),
      const SizedBox(height: 16),
      MoneyField(controller: profit, label: 'Profit', allowNegative: true),
      const Text(
        'Profit is entered manually. Use a negative value for a loss. Zero is a valid entry.',
      ),
      const SizedBox(height: 16),
      AppTextField(controller: note, label: 'Note (optional)', maxLines: 4),
    ],
  );
}
