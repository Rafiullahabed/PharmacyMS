import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/presentation/components.dart';
import '../../../core/presentation/repository_view.dart';
import '../application/debt_controller.dart';
import '../domain/debt.dart';
import 'customer_form.dart';
import 'customer_detail.dart';

void openOutstandingCustomers(
  BuildContext context,
  DebtController controller,
) => Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Outstanding customers')),
      body: SafeArea(
        child: DebtorsScreen(
          controller: controller,
          initialFilter: CustomerFilter.outstanding,
        ),
      ),
    ),
  ),
);

class DebtorsScreen extends StatefulWidget {
  const DebtorsScreen({
    super.key,
    required this.controller,
    this.initialFilter = CustomerFilter.all,
  });
  final DebtController controller;
  final CustomerFilter initialFilter;
  @override
  State<DebtorsScreen> createState() => _DebtorsScreenState();
}

class _DebtorsScreenState extends State<DebtorsScreen> {
  final search = TextEditingController();
  Timer? debounce;
  String query = '';
  late CustomerFilter filter = widget.initialFilter;
  bool archived = false;
  int pages = 1;
  void changed(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          query = value;
          pages = 1;
        });
      }
    });
  }

  void clear() {
    debounce?.cancel();
    search.clear();
    setState(() {
      query = '';
      filter = CustomerFilter.all;
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
                              addCustomer(context, widget.controller),
                          icon: const Icon(Icons.person_add_alt),
                          label: const Text('Add customer'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: search,
                        onChanged: changed,
                        textDirection: contentDirection(search.text),
                        decoration: InputDecoration(
                          labelText: 'Search name or phone',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            tooltip: 'Clear customer search',
                            onPressed: () {
                              search.clear();
                              changed('');
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
                            for (final value in CustomerFilter.values)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(value.label),
                                  selected: filter == value,
                                  onSelected: (_) => setState(() {
                                    filter = value;
                                    pages = 1;
                                  }),
                                ),
                              ),
                            FilterChip(
                              label: const Text('Archived'),
                              selected: archived,
                              onSelected: (value) => setState(() {
                                archived = value;
                                filter = CustomerFilter.all;
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
          child: RepositoryView<CustomerPage>(
            key: ValueKey('$query-${filter.name}-$archived-$pages'),
            changes: widget.controller,
            load: () => widget.controller.customers(
              search: query,
              filter: filter,
              archived: archived,
              pages: pages,
            ),
            builder: (context, data) => Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView.builder(
                  key: PageStorageKey(
                    'customers-$query-${filter.name}-$archived',
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: data.items.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Total outstanding · All active customers',
                            ),
                            MoneyText.total(
                              data.outstanding,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${data.total} ${archived ? 'archived' : 'active'} matching customers',
                            ),
                          ],
                        ),
                      );
                    }
                    if (index == data.items.length + 1) {
                      if (data.items.isEmpty) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            EmptyState(
                              icon: Icons.people_outline,
                              title:
                                  data.activeCount == 0 &&
                                      !archived &&
                                      query.isEmpty &&
                                      filter == CustomerFilter.all
                                  ? 'No customers yet'
                                  : 'No matching customers',
                              message:
                                  'Names and descriptions can be in English or Persian. Phone numbers are optional.',
                            ),
                            if (query.isNotEmpty ||
                                filter != CustomerFilter.all ||
                                archived)
                              TextButton(
                                onPressed: clear,
                                child: const Text('Clear customer filters'),
                              ),
                          ],
                        );
                      }
                      return data.items.length < data.total
                          ? TextButton(
                              onPressed: () => setState(() => pages++),
                              child: const Text('Load more customers'),
                            )
                          : const SizedBox(height: 16);
                    }
                    final item = data.items[index - 1],
                        customer = item.customer;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          title: ContentText(
                            customer.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (customer.phone?.isNotEmpty ?? false)
                                Text(
                                  customer.phone!,
                                  textDirection: TextDirection.ltr,
                                ),
                              Text('Outstanding: ${item.balance.formatted}'),
                              Text(
                                item.balance.minor == 0
                                    ? 'Settled'
                                    : 'Outstanding',
                              ),
                              Text(
                                item.latest == null
                                    ? 'No transactions yet'
                                    : 'Latest activity: ${item.latest!.label}',
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CustomerDetail(
                                controller: widget.controller,
                                id: customer.meta.id,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
