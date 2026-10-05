import 'package:flutter/material.dart';
import '../../../core/presentation/app_theme.dart';
import '../../../core/presentation/components.dart';
import '../domain/home_summary.dart';
import '../../inventory/application/inventory_controller.dart';
import '../../inventory/presentation/inventory_home.dart';
import '../../daily_records/application/daily_records_controller.dart';
import '../../daily_records/presentation/daily_record_detail.dart';
import '../../debtors/application/debt_controller.dart';
import '../../debtors/presentation/debtors_screen.dart';
import '../../debtors/presentation/customer_form.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.summary,
    required this.onNavigate,
    required this.inventory,
    required this.daily,
    required this.debt,
  });
  final HomeSummary summary;
  final ValueChanged<int> onNavigate;
  final InventoryController inventory;
  final DailyRecordsController daily;
  final DebtController debt;
  @override
  Widget build(BuildContext context) => PageContent(
    storageKey: 'home',
    children: [
      Text(
        '${summary.today.label} · Gregorian',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: Space.xl),
      if (summary.products == 0 &&
          summary.dailyRecords == 0 &&
          summary.customers == 0)
        const EmptyState(
          icon: Icons.spa_outlined,
          title: 'A clear view of your pharmacy',
          message:
              'Your inventory, daily figures, and customer debts — together in one place, kept separately.',
        ),
      InventoryHome(
        controller: inventory,
        betweenSections: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Section(
              title: "Today's daily record",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Manually recorded sales and profit',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (summary.todayRecord == null)
                    const StatusBadge(
                      label: 'Not recorded',
                      icon: Icons.edit_calendar_outlined,
                    )
                  else ...[
                    const Text('Sales'),
                    MoneyText(summary.todayRecord!.sales),
                    const SizedBox(height: 12),
                    const Text('Recorded profit'),
                    MoneyText(summary.todayRecord!.profit),
                  ],
                  TextButton(
                    onPressed: () => onNavigate(2),
                    child: const Text('View daily records'),
                  ),
                  FilledButton.icon(
                    onPressed: () => recordDay(context, daily),
                    icon: const Icon(Icons.edit_calendar_outlined),
                    label: Text(
                      summary.todayRecord == null
                          ? 'Record today'
                          : "Edit today's record",
                    ),
                  ),
                ],
              ),
            ),
            Section(
              title: 'Customer debt',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Total outstanding · Active customers',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (summary.customers == 0)
                    const Text('No customer debt recorded.')
                  else
                    MoneyText.total(
                      summary.outstanding,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  TextButton(
                    onPressed: () => openOutstandingCustomers(context, debt),
                    child: const Text('View outstanding customers'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => addCustomer(context, debt),
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Add customer'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
