import 'package:flutter/material.dart';
import '../../../core/presentation/components.dart';
import '../../../core/presentation/form_fields.dart';
import '../../../core/presentation/workflow.dart';
import '../../../core/domain/validation.dart';
import '../../inventory/application/inventory_controller.dart';
import '../../inventory/domain/inventory.dart';
import '../../inventory/presentation/inventory_widgets.dart';

Future<StockUnit?> openUnitForm(
  BuildContext context,
  InventoryController controller, {
  StockUnit? unit,
}) => Navigator.push<StockUnit>(
  context,
  MaterialPageRoute(
    builder: (_) => UnitForm(controller: controller, unit: unit),
  ),
);

class UnitsScreen extends StatefulWidget {
  const UnitsScreen({super.key, required this.controller});
  final InventoryController controller;
  @override
  State<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends State<UnitsScreen> {
  final save = SaveController();
  @override
  void dispose() {
    save.dispose();
    super.dispose();
  }

  Future<void> action(StockUnit unit, String action) async {
    if (save.saving) return;
    if (action == 'rename') {
      await openUnitForm(context, widget.controller, unit: unit);
      return;
    }
    if (!await confirmAction(
      context,
      title: action == 'delete'
          ? 'Delete unused unit?'
          : action == 'deactivate'
          ? 'Deactivate unit?'
          : 'Reactivate unit?',
      message: action == 'deactivate'
          ? 'Existing items will keep this unit. It will be hidden when choosing a unit for new items.'
          : action == 'delete'
          ? 'Delete ${unit.name}? This unused unit will be removed.'
          : 'Make ${unit.name} available for new items again?',
      action: action == 'delete'
          ? 'Delete'
          : action == 'deactivate'
          ? 'Deactivate'
          : 'Reactivate',
      destructive: action == 'delete',
    )) {
      return;
    }
    save.newAttempt();
    final done = await save.run((id) async {
      final settings = await widget.controller.settings;
      if (action == 'delete') {
        await settings.deleteUnusedUnit(unit.meta.id, operationId: id);
      } else {
        await settings.saveUnit(
          id: unit.meta.id,
          name: unit.name,
          inactive: action == 'deactivate',
          operationId: id,
        );
      }
      return true;
    });
    if (done == true) {
      widget.controller.changed();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Unit updated')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Units'),
      actions: [
        IconButton(
          tooltip: 'Add unit',
          onPressed: () => openUnitForm(context, widget.controller),
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: save,
        builder: (context, _) => InventoryData(
          controller: widget.controller,
          load: () async {
            final s = await widget.controller.settings;
            return (units: await s.units(), usage: await s.unitUsage());
          },
          builder: (context, data) => PageContent(
            children: [
              const Text(
                'One counting unit per item. Renaming a unit updates its label everywhere.',
              ),
              ErrorNotice(save.error),
              for (final inactive in [false, true])
                Section(
                  title: inactive ? 'Inactive units' : 'Active units',
                  child: Column(
                    children: [
                      if (!data.units.any((u) => u.inactive == inactive))
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            inactive
                                ? 'No inactive units'
                                : 'No active units. Add a unit to begin.',
                          ),
                        ),
                      for (final unit in data.units.where(
                        (u) => u.inactive == inactive,
                      ))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: ContentText(unit.name),
                          subtitle: Text(
                            (data.usage[unit.meta.id] ?? 0) == 0
                                ? 'Unused'
                                : 'Used by ${data.usage[unit.meta.id]} items',
                          ),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Manage ${unit.name}',
                            enabled: !save.saving,
                            onSelected: (a) => action(unit, a),
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'rename',
                                child: Text('Rename'),
                              ),
                              if (!inactive)
                                const PopupMenuItem(
                                  value: 'deactivate',
                                  child: Text('Deactivate'),
                                ),
                              if (inactive)
                                const PopupMenuItem(
                                  value: 'reactivate',
                                  child: Text('Reactivate'),
                                ),
                              if ((data.usage[unit.meta.id] ?? 0) == 0)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete unused unit'),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class UnitForm extends StatefulWidget {
  const UnitForm({super.key, required this.controller, this.unit});
  final InventoryController controller;
  final StockUnit? unit;
  @override
  State<UnitForm> createState() => _UnitFormState();
}

class _UnitFormState extends State<UnitForm> {
  final form = GlobalKey<FormState>(), name = TextEditingController();
  final save = SaveController();
  bool dirty = false;
  @override
  void initState() {
    super.initState();
    name.text = widget.unit?.name ?? '';
    name.addListener(changed);
  }

  void changed() {
    if (!mounted) return;
    setState(() => dirty = true);
    save.newAttempt();
  }

  Future<void> submit() async {
    if (save.saving || !validateAndReveal(form)) return;
    final unit = await save.run(
      (id) async => (await widget.controller.settings).saveUnit(
        operationId: id,
        id: widget.unit?.meta.id,
        name: name.text,
        inactive: widget.unit?.inactive ?? false,
      ),
    );
    if (unit != null && mounted) {
      setState(() => dirty = false);
      widget.controller.changed();
      Navigator.pop(context, unit);
    }
  }

  @override
  void dispose() {
    name.removeListener(changed);
    name.dispose();
    save.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: widget.unit == null ? 'Add unit' : 'Rename unit',
    formKey: form,
    save: save,
    dirty: dirty,
    onSave: submit,
    children: [
      AppTextField(
        controller: name,
        label: 'Unit name',
        validator: (v) =>
            validationMessage(() => requiredText(v ?? '', 'Unit name')),
      ),
      const SizedBox(height: 16),
      const Text(
        'Use the unit you count this item in, such as Strip, Bottle, or Piece. No automatic conversion is applied.',
      ),
    ],
  );
}
