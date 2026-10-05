import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/presentation/components.dart';
import '../application/inventory_controller.dart';
import '../domain/inventory.dart';
import 'detail_screens.dart';
import 'inventory_widgets.dart';
import 'stock_adjustment.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.controller,
    this.initialFilter = InventoryFilter.all,
  });
  final InventoryController controller;
  final InventoryFilter initialFilter;
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final search = TextEditingController();
  Timer? debounce;
  late InventoryFilter filter = widget.initialFilter;
  String query = '';
  bool archived = false;
  int pages = 1;
  void updateSearch(String text) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted) {
        setState(() {
          query = text;
          pages = 1;
        });
      }
    });
  }

  void clear() {
    search.clear();
    debounce?.cancel();
    setState(() {
      query = '';
      filter = InventoryFilter.all;
      archived = false;
      pages = 1;
    });
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * .55),
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: () =>
                              addProduct(context, widget.controller),
                          icon: const Icon(Icons.add),
                          label: const Text('Add item'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: search,
                        textDirection: contentDirection(search.text),
                        onChanged: updateSearch,
                        decoration: InputDecoration(
                          labelText: 'Search items',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              search.clear();
                              updateSearch('');
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final value
                                in archived
                                    ? [InventoryFilter.all]
                                    : InventoryFilter.values)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  avatar: Icon(inventoryFilterIcon(value)),
                                  label: Text(value.label),
                                  selected: filter == value,
                                  onSelected: (_) => setState(() {
                                    filter = value;
                                    pages = 1;
                                  }),
                                ),
                              ),
                            FilterChip(
                              label: const Text('Archived items'),
                              selected: archived,
                              onSelected: (v) => setState(() {
                                archived = v;
                                filter = InventoryFilter.all;
                                pages = 1;
                              }),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: InventoryData(
            key: ValueKey('$query-${filter.name}-$archived-$pages'),
            controller: widget.controller,
            load: () => widget.controller.loadList(
              search: query,
              filter: filter,
              archived: archived,
              pages: pages,
            ),
            builder: (context, data) {
              final count = filter.isExpiry
                  ? data.alerts.length
                  : data.items.length;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView.builder(
                    key: PageStorageKey(
                      'inventory-$query-${filter.name}-$archived',
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: count + 2,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            filter.isExpiry
                                ? '${data.totalBatches} affected batches across ${data.totalProducts} products · Showing $count'
                                : '${data.totalProducts} ${archived ? 'archived' : 'active'} products',
                          ),
                        );
                      }
                      if (index == count + 1) {
                        if (count == 0) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              EmptyState(
                                icon: Icons.inventory_2_outlined,
                                title:
                                    data.overview.products == 0 &&
                                        !archived &&
                                        query.isEmpty &&
                                        filter == InventoryFilter.all
                                    ? 'No items yet'
                                    : archived && query.isEmpty
                                    ? 'No archived items'
                                    : 'No matching items',
                                message:
                                    data.overview.products == 0 && !archived
                                    ? 'Add your first item, then keep each delivery in its own batch.'
                                    : 'Try a different search or clear your filters.',
                              ),
                              if (query.isNotEmpty ||
                                  filter != InventoryFilter.all)
                                TextButton(
                                  onPressed: clear,
                                  child: const Text('Clear filters'),
                                ),
                            ],
                          );
                        }
                        return data.more
                            ? TextButton(
                                onPressed: () => setState(() => pages++),
                                child: const Text('Load more'),
                              )
                            : const SizedBox.shrink();
                      }
                      if (filter.isExpiry) {
                        final alert = data.alerts[index - 1];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            child: InkWell(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BatchDetailScreen(
                                    controller: widget.controller,
                                    batchId: alert.batch.meta.id,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    ContentText(
                                      alert.product.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    BatchSummary(
                                      batch: alert.batch,
                                      unit: alert.unit,
                                      today: data.today,
                                      warningDays: alert.product.warningDays,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      final item = data.items[index - 1];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                InkWell(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ProductDetailScreen(
                                        controller: widget.controller,
                                        productId: item.product.meta.id,
                                      ),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        ContentText(
                                          item.product.name,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleLarge,
                                        ),
                                        const SizedBox(height: 8),
                                        InventoryQuantities(item: item),
                                        if (item.lowStock)
                                          Text(
                                            'Minimum: ${item.product.minimumStock} ${item.unit}',
                                          ),
                                        if (item.product.archived)
                                          const Text(
                                            'Archived · History retained',
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (!item.product.archived)
                                  Wrap(
                                    spacing: 12,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () => adjustStock(
                                          context,
                                          widget.controller,
                                          item.product.meta.id,
                                          remove: false,
                                        ),
                                        icon: const Icon(Icons.add),
                                        label: const Text('Add stock'),
                                      ),
                                      TextButton.icon(
                                        onPressed: item.physical == 0
                                            ? null
                                            : () => adjustStock(
                                                context,
                                                widget.controller,
                                                item.product.meta.id,
                                                remove: true,
                                              ),
                                        icon: const Icon(Icons.remove),
                                        label: const Text('Remove stock'),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}
