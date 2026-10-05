import 'package:flutter/material.dart';
import '../../../core/domain/validation.dart';
import '../../../core/presentation/form_fields.dart';
import '../../../core/presentation/workflow.dart';
import '../application/debt_controller.dart';
import '../domain/debt.dart';
import 'customer_detail.dart';

Future<void> addCustomer(
  BuildContext context,
  DebtController controller,
) async {
  final navigator = Navigator.of(context);
  final customer = await navigator.push<Customer>(
    MaterialPageRoute(builder: (_) => CustomerForm(controller: controller)),
  );
  if (customer != null && navigator.mounted) {
    await navigator.push(
      MaterialPageRoute(
        builder: (_) =>
            CustomerDetail(controller: controller, id: customer.meta.id),
      ),
    );
  }
}

class CustomerForm extends StatefulWidget {
  const CustomerForm({super.key, required this.controller, this.customer});
  final DebtController controller;
  final Customer? customer;
  @override
  State<CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<CustomerForm> {
  final form = GlobalKey<FormState>(), save = SaveController();
  final name = TextEditingController(),
      phone = TextEditingController(),
      note = TextEditingController();
  bool dirty = false, checking = false;
  @override
  void initState() {
    super.initState();
    name.text = widget.customer?.name ?? '';
    phone.text = widget.customer?.phone ?? '';
    note.text = widget.customer?.note ?? '';
    for (final field in [name, phone, note]) {
      field.addListener(changed);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    });
  }

  void changed() {
    save.newAttempt();
    setState(() => dirty = true);
  }

  Future<void> submit() async {
    if (save.saving || checking || !validateAndReveal(form)) return;
    final submittedName = name.text;
    setState(() => checking = true);
    try {
      final repo = await widget.controller.repository;
      if (!save.uncertain && name.text.trim() != widget.customer?.name) {
        final similar = await repo.similarCustomers(
          name.text,
          excludingId: widget.customer?.meta.id,
        );
        if (!mounted) return;
        if (similar.isNotEmpty &&
            !await confirmAction(
              context,
              title: 'Similar customer names',
              message:
                  'These customers already exist:\n\n${similar.map((c) => '${c.name}${c.archived ? ' · Archived' : ''}${c.phone?.isNotEmpty == true ? '\nPhone: ${c.phone}' : ''}${c.note?.isNotEmpty == true ? '\n${c.note}' : ''}').join('\n\n')}\n\nYou can continue if this is a different customer.',
              action: 'Continue',
            )) {
          return;
        }
      }
      if (!mounted) return;
      // A slow duplicate lookup must not approve a different, subsequently typed name.
      if (name.text != submittedName) return;
      final result = await save.run(
        (operation) => repo.saveCustomer(
          operationId: operation,
          id: widget.customer?.meta.id,
          name: name.text,
          phone: phone.text.trim().isEmpty ? null : phone.text,
          note: note.text.isEmpty ? null : note.text,
        ),
      );
      if (result != null && mounted) {
        widget.controller.changed();
        setState(() => dirty = false);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.pop(context, result);
      }
    } catch (error) {
      if (mounted) setState(() => save.error = persistenceMessage(error));
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    note.dispose();
    save.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: widget.customer == null ? 'Add customer' : 'Edit customer',
    formKey: form,
    save: save,
    dirty: dirty,
    onSave: submit,
    canSave: !checking,
    saveLabel: save.uncertain ? 'Retry same save' : 'Save customer',
    children: [
      const Text(
        'A name is enough to start. Phone and notes help distinguish people with similar names.',
      ),
      const SizedBox(height: 16),
      AppTextField(
        controller: name,
        label: 'Customer name',
        validator: (value) =>
            validationMessage(() => requiredText(value ?? '', 'Name')),
      ),
      const SizedBox(height: 16),
      AppTextField(
        controller: phone,
        label: 'Phone (optional)',
        forceLtr: true,
        keyboardType: TextInputType.phone,
        helper: 'Kept as text, including leading zeros.',
      ),
      const SizedBox(height: 16),
      AppTextField(controller: note, label: 'Note (optional)', maxLines: 4),
    ],
  );
}
