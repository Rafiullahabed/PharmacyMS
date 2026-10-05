import 'package:flutter/material.dart';
import '../../core/presentation/app_theme.dart';
import '../../core/presentation/components.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/inventory/presentation/inventory_screen.dart';
import '../../features/daily_records/presentation/daily_records_screen.dart';
import '../../features/debtors/presentation/debtors_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../application/app_controller.dart';
import '../../features/inventory/application/inventory_controller.dart';
import '../../features/daily_records/application/daily_records_controller.dart';
import '../../features/debtors/application/debt_controller.dart';

class PharmacyApp extends StatelessWidget {
  const PharmacyApp({
    super.key,
    required this.controller,
    required this.inventory,
    required this.daily,
    required this.debt,
  });
  final AppController controller;
  final InventoryController inventory;
  final DailyRecordsController daily;
  final DebtController debt;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pharmacy Companion',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    locale: const Locale('en'),
    home: NavigationShell(
      controller: controller,
      inventory: inventory,
      daily: daily,
      debt: debt,
    ),
  );
}

class NavigationShell extends StatefulWidget {
  const NavigationShell({
    super.key,
    required this.controller,
    required this.inventory,
    required this.daily,
    required this.debt,
  });
  final AppController controller;
  final InventoryController inventory;
  final DailyRecordsController daily;
  final DebtController debt;
  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell>
    with WidgetsBindingObserver {
  static const labels = ['Home', 'Inventory', 'Daily Records', 'Debtors'];
  static const icons = [
    Icons.home_outlined,
    Icons.inventory_2_outlined,
    Icons.bar_chart_outlined,
    Icons.people_outline,
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.inventory.startDayWatch();
    widget.controller.refresh();
    widget.inventory.addListener(inventoryChanged);
    widget.daily.addListener(dailyChanged);
    widget.debt.addListener(debtChanged);
  }

  void inventoryChanged() {
    widget.daily.refreshDay();
    widget.debt.refreshDay();
    widget.controller.refresh();
  }

  void dailyChanged() {
    widget.controller.refresh();
  }

  void debtChanged() {
    widget.controller.refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.inventory.changed();
      widget.daily.changed();
      widget.debt.changed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.inventory.stopDayWatch();
    widget.inventory.removeListener(inventoryChanged);
    widget.daily.removeListener(dailyChanged);
    widget.debt.removeListener(debtChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final model = widget.controller;
      final summary = model.summary;
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: MediaQuery.textScalerOf(context).scale(24) * 2 + 16,
          title: Text(
            model.tab == 0 ? 'Pharmacy Companion' : labels[model.tab],
            maxLines: 2,
          ),
          actions: [
            if (model.tab == 0 && summary != null)
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        SettingsScreen(controller: widget.inventory),
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: model.failed
              ? AppErrorState(onRetry: model.refresh)
              : summary == null
              ? const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Opening local data',
                  ),
                )
              : IndexedStack(
                  index: model.tab,
                  children: [
                    HomeScreen(
                      summary: summary,
                      onNavigate: model.selectTab,
                      inventory: widget.inventory,
                      daily: widget.daily,
                      debt: widget.debt,
                    ),
                    InventoryScreen(controller: widget.inventory),
                    DailyRecordsScreen(controller: widget.daily),
                    DebtorsScreen(controller: widget.debt),
                  ],
                ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Material(
            color: Colors.white,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: Semantics(
                      selected: model.tab == i,
                      button: true,
                      child: InkWell(
                        onTap: () => model.selectTab(i),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 64),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 12,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  icons[i],
                                  color: model.tab == i
                                      ? AppColors.primary
                                      : AppColors.secondary,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  labels[i],
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: model.tab == i
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: model.tab == i
                                        ? AppColors.primary
                                        : AppColors.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
