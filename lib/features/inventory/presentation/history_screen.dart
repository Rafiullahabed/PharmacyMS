import 'package:flutter/material.dart';
import '../../../core/domain/dates.dart';
import '../../../core/presentation/components.dart';
import '../application/inventory_controller.dart';
import '../domain/inventory.dart';
import 'inventory_widgets.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.controller,
    required this.productId,
    required this.unit,
    this.batchId,
  });
  final InventoryController controller;
  final String productId, unit;
  final String? batchId;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int pages = 1;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: pageAppBar(context, title: 'Stock history'),
    body: SafeArea(
      child: InventoryData(
        key: ValueKey(pages),
        controller: widget.controller,
        load: () async {
          final repo = await widget.controller.repository;
          final batches = await repo.batches(widget.productId);
          final movements = <StockMovement>[];
          for (var page = 0; page < pages; page++) {
            movements.addAll(
              widget.batchId == null
                  ? await repo.productMovements(
                      widget.productId,
                      offset: page * 50,
                    )
                  : await repo.movements(widget.batchId!, offset: page * 50),
            );
          }
          return (
            batches: {for (final b in batches) b.meta.id: b.label},
            movements: movements,
          );
        },
        builder: (context, data) => PageWidth(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: data.movements.length + 1,
            itemBuilder: (context, index) {
              if (index == data.movements.length) {
                return data.movements.isEmpty
                    ? const Text('No stock movements yet.')
                    : data.movements.length == pages * 50
                    ? TextButton(
                        onPressed: () => setState(() => pages++),
                        child: const Text('Load older movements'),
                      )
                    : const SizedBox(height: 16);
              }
              final m = data.movements[index];
              return MovementTile(
                movement: m,
                batchLabel: data.batches[m.batchId] ?? m.batchId,
                unit: widget.unit,
              );
            },
          ),
        ),
      ),
    ),
  );
}

class MovementTile extends StatelessWidget {
  const MovementTile({
    super.key,
    required this.movement,
    required this.batchLabel,
    required this.unit,
  });
  final StockMovement movement;
  final String batchLabel, unit;
  @override
  Widget build(BuildContext context) {
    final local = movement.meta.createdAt.toLocal();
    final kind = switch (movement.kind) {
      MovementKind.opening => 'Opening stock',
      MovementKind.add => 'Stock added',
      MovementKind.remove => 'Stock removed',
      MovementKind.reversal => 'Reversal',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$kind · ${movement.delta > 0 ? '+' : ''}${movement.delta} $unit',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          ContentText(batchLabel),
          Text(
            'Batch ID: ${movement.batchId.substring(0, 8)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            '${BusinessDate.fromLocal(local).label} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} · Result ${movement.resultingQuantity} $unit',
          ),
          if (movement.note?.isNotEmpty ?? false) ContentText(movement.note!),
          if (movement.reversalOf != null)
            const Text(
              'Reverses an earlier stock change; the original is retained.',
            ),
          const Divider(),
        ],
      ),
    );
  }
}
