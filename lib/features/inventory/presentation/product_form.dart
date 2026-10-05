import 'package:flutter/material.dart';
import '../../../core/domain/validation.dart';
import '../../../core/presentation/form_fields.dart';
import '../../../core/presentation/workflow.dart';
import '../../settings/presentation/units_screen.dart';
import '../application/inventory_controller.dart';
import '../domain/inventory.dart';
import 'batch_fields.dart';

class ProductForm extends StatefulWidget {
  const ProductForm({super.key, required this.controller, this.product});
  final InventoryController controller;
  final Product? product;
  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  final form = GlobalKey<FormState>(), batch = GlobalKey<BatchFieldsState>();
  final name = TextEditingController(),
      minimum = TextEditingController(),
      warning = TextEditingController(),
      category = TextEditingController(),
      notes = TextEditingController();
  final save = SaveController();
  List<StockUnit> units = [];
  String? unitId, loadError;
  bool dirty = false, initialStock = false, locked = false, loaded = false;
  @override
  void initState() {
    super.initState();
    final p = widget.product;
    name.text = p?.name ?? '';
    minimum.text = '${p?.minimumStock ?? 0}';
    warning.text = '${p?.warningDays ?? 30}';
    category.text = p?.category ?? '';
    notes.text = p?.notes ?? '';
    unitId = p?.unitId;
    for (final c in [name, minimum, warning, category, notes]) {
      c.addListener(changed);
    }
    load();
  }

  void changed() {
    if (!mounted) return;
    setState(() => dirty = true);
    save.newAttempt();
  }

  Future<void> load() async {
    try {
      final settings = await widget.controller.settings;
      final next = await settings.units();
      final history =
          widget.product != null &&
          await (await widget.controller.repository).hasStockHistory(
            widget.product!.meta.id,
          );
      if (mounted) {
        setState(() {
          units = next;
          locked = history;
          loaded = true;
          loadError = null;
          if (unitId != widget.product?.unitId &&
              !next.any((u) => u.meta.id == unitId && !u.inactive)) {
            unitId = null;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => loadError = 'Unable to load units. Retry to continue.');
      }
    }
  }

  Future<void> submit() async {
    if (save.saving || !loaded || !validateAndReveal(form)) return;
    ProductDraft draft;
    BatchDraft? opening;
    try {
      draft = ProductDraft(
        name: name.text,
        unitId: unitId!,
        minimumStock: wholeQuantity(minimum.text),
        warningDays: wholeQuantity(warning.text),
        category: category.text,
        notes: notes.text,
      );
      opening = initialStock ? batch.currentState!.value() : null;
    } on ValidationException catch (e) {
      save.error = e.message;
      setState(() {});
      return;
    }
    final retryingUnknownSave = save.uncertain;
    final result = await save.run<Product?>((id) async {
      final repo = await widget.controller.repository;
      // A committed but unacknowledged creation may itself match this search.
      // Reconcile its receipt before treating it as a possible new duplicate.
      if (!retryingUnknownSave) {
        final similar = await repo.similarProducts(
          draft.name,
          excludingId: widget.product?.meta.id,
        );
        if (similar.isNotEmpty &&
            mounted &&
            !await confirmAction(
              context,
              title: 'Possible duplicate item',
              message:
                  'An item with this name already exists. Include strength or brand to distinguish it, or continue with this name.',
              action: 'Continue',
            )) {
          return null;
        }
      }
      if (!mounted) return null;
      return repo.saveProduct(
        operationId: id,
        productId: widget.product?.meta.id,
        draft: draft,
        initialStock: opening,
      );
    });
    if (result != null && mounted) {
      setState(() => dirty = false);
      widget.controller.changed();
      Navigator.pop(context, result);
    }
  }

  @override
  void dispose() {
    for (final c in [name, minimum, warning, category, notes]) {
      c.removeListener(changed);
      c.dispose();
    }
    save.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: widget.product == null ? 'Add item' : 'Edit item',
    formKey: form,
    save: save,
    dirty: dirty,
    canSave: loaded,
    onSave: submit,
    children: [
      AppTextField(
        controller: name,
        label: 'Item name',
        helper: 'A recognizable name, including strength or brand when useful.',
        validator: (v) =>
            validationMessage(() => requiredText(v ?? '', 'Item name')),
      ),
      const SizedBox(height: 16),
      if (loadError != null) ...[
        ErrorNotice(loadError),
        TextButton(onPressed: load, child: const Text('Retry units')),
      ] else if (!loaded)
        const LinearProgressIndicator()
      else
        DropdownButtonFormField<String>(
          key: ValueKey(
            '$unitId-${units.map((u) => '${u.meta.id}${u.name}${u.inactive}').join()}',
          ),
          initialValue: unitId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Counting unit'),
          validator: (v) => v == null ? 'Choose a counting unit.' : null,
          items: [
            for (final u in units.where(
              (u) => !u.inactive || u.meta.id == widget.product?.unitId,
            ))
              DropdownMenuItem(
                value: u.meta.id,
                child: Text(
                  '${u.name}${u.inactive ? ' (inactive)' : ''}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: locked
              ? null
              : (v) {
                  setState(() => unitId = v);
                  changed();
                },
        ),
      if (locked)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'The counting unit is locked because this item has stock history. Create a new item for a different unit.',
          ),
        ),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: () async {
              final unit = await openUnitForm(context, widget.controller);
              await load();
              if (unit != null && mounted && !locked) {
                setState(() => unitId = unit.meta.id);
                changed();
              }
            },
            child: const Text('Add unit'),
          ),
          TextButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UnitsScreen(controller: widget.controller),
                ),
              );
              await load();
            },
            child: const Text('Manage units'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      AppTextField(
        controller: minimum,
        label: 'Minimum stock',
        forceLtr: true,
        keyboardType: TextInputType.number,
        helper: 'Warn when usable stock is below this amount.',
        validator: (v) => validationMessage(() => wholeQuantity(v ?? '')),
      ),
      const SizedBox(height: 16),
      AppTextField(
        controller: warning,
        label: 'Expiry warning days',
        forceLtr: true,
        keyboardType: TextInputType.number,
        helper:
            'Warn this many days before expiry. Zero still shows “Expires today”.',
        validator: (v) => validationMessage(() => wholeQuantity(v ?? '')),
      ),
      const SizedBox(height: 16),
      ExpansionTile(
        title: const Text('Category and notes (optional)'),
        children: [
          AppTextField(controller: category, label: 'Category'),
          const SizedBox(height: 16),
          AppTextField(controller: notes, label: 'Item notes', maxLines: 3),
        ],
      ),
      if (widget.product == null) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Add initial stock'),
          value: initialStock,
          onChanged: (value) {
            setState(() => initialStock = value);
            changed();
          },
        ),
        if (initialStock)
          BatchFields(
            key: batch,
            today: widget.controller.clock.today(),
            onChanged: changed,
          ),
      ],
    ],
  );
}
