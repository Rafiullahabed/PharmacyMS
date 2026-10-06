import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/presentation/components.dart';
import '../application/inventory_controller.dart';
import '../domain/inventory.dart';
import 'detail_screens.dart';
import 'inventory_widgets.dart';
import 'quick_stock.dart';
import '../../../core/presentation/app_theme.dart';

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
  Widget build(BuildContext context) => NestedScrollView(
    headerSliverBuilder: (context, innerBoxIsScrolled) => [
      SliverToBoxAdapter(
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
                      onPressed: () => addProduct(context, widget.controller),
                      icon: const Icon(Icons.add),
                      label: const Text('Add item'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SearchField(
                    controller: search,
                    onChanged: updateSearch,
                    label: 'Search items',
                    clearLabel: 'Clear search',
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
                              showCheckmark: false,
                              avatar: Icon(inventoryFilterIcon(value)),
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(value.label),
                                  if (filter == value) ...[
                                    const SizedBox(width: 8),
                                    const Icon(Icons.check, size: 18),
                                  ],
                                ],
                              ),
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
    ],
    body: InventoryData(
      key: ValueKey('$query-${filter.name}-$archived-$pages'),
      controller: widget.controller,
      load: () => widget.controller.loadList(
        search: query,
        filter: filter,
        archived: archived,
        pages: pages,
      ),
      builder: (context, data) {
        final count = filter.isExpiry ? data.alerts.length : data.items.length;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView.builder(
              key: PageStorageKey('inventory-$query-${filter.name}-$archived'),
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
                          message: data.overview.products == 0 && !archived
                              ? 'Add your first item, then keep each delivery in its own batch.'
                              : 'Try a different search or clear your filters.',
                        ),
                        if (query.isNotEmpty || filter != InventoryFilter.all)
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
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ContentText(
                                alert.product.name,
                                style: Theme.of(context).textTheme.titleLarge,
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
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
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE3F0ED),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.medication_outlined,
                                          color: AppColors.primary,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ContentText(
                                          item.product.name,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleLarge,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.chevron_right,
                                        size: 20,
                                        color: AppColors.secondary,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  InventoryQuantities(
                                    item: item,
                                    compact: true,
                                  ),
                                  if (item.lowStock)
                                    Text(
                                      'Minimum: ${item.product.minimumStock} ${item.unit}',
                                    ),
                                  if (item.product.archived)
                                    const Text('Archived · History retained'),
                                ],
                              ),
                            ),
                          ),
                          if (!item.product.archived) ...[
                            const Divider(height: 16),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                Text(
                                  'One unit per tap',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                QuickStockActions(
                                  key: ValueKey(
                                    'quick-${item.product.meta.id}',
                                  ),
                                  controller: widget.controller,
                                  item: item,
                                ),
                              ],
                            ),
                          ],
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
  );
}
