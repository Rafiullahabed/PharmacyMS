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
import '../../features/backup/application/backup_controller.dart';
import '../../features/settings/application/appearance_controller.dart';
import '../../features/settings/presentation/appearance_settings.dart';

class PharmacyApp extends StatefulWidget {
  const PharmacyApp({
    super.key,
    required this.controller,
    required this.inventory,
    required this.daily,
    required this.debt,
    this.backups,
  });
  final AppController controller;
  final InventoryController inventory;
  final DailyRecordsController daily;
  final DebtController debt;
  final BackupController? backups;
  @override
  State<PharmacyApp> createState() => _PharmacyAppState();
}

class _PharmacyAppState extends State<PharmacyApp> with WidgetsBindingObserver {
  late final appearance = AppearanceController(() => widget.inventory.settings);
  int restoreRevision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appearance.load();
    widget.backups?.addListener(restored);
  }

  void restored() {
    final backup = widget.backups!;
    if (backup.busy || restoreRevision == backup.restoreRevision) return;
    restoreRevision = backup.restoreRevision;
    appearance.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) appearance.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.backups?.removeListener(restored);
    appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppearanceScope(
    controller: appearance,
    child: ListenableBuilder(
      listenable: appearance,
      builder: (context, _) => MaterialApp(
        title: 'Pharmacy Companion',
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: AppTextScaler(
              MediaQuery.textScalerOf(context),
              appearance.size.factor,
            ),
          ),
          child: child!,
        ),
        locale: const Locale('en'),
        home: NavigationShell(
          controller: widget.controller,
          inventory: widget.inventory,
          daily: widget.daily,
          debt: widget.debt,
          backups: widget.backups,
        ),
      ),
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
    this.backups,
  });
  final AppController controller;
  final InventoryController inventory;
  final DailyRecordsController daily;
  final DebtController debt;
  final BackupController? backups;
  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell>
    with WidgetsBindingObserver {
  int restoreRevision = 0;
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
    widget.backups?.addListener(backupChanged);
  }

  void backupChanged() {
    final backup = widget.backups!;
    if (backup.busy || restoreRevision == backup.restoreRevision) return;
    setState(() => restoreRevision = backup.restoreRevision);
    widget.controller.selectTab(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(backup.message ?? 'Backup restored.')),
      );
    });
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
    widget.backups?.removeListener(backupChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final model = widget.controller;
      final summary = model.summary;
      return Scaffold(
        appBar: pageAppBar(
          context,
          title:
              model.tab == 0 && MediaQuery.textScalerOf(context).scale(16) < 24
              ? 'Pharmacy Companion'
              : labels[model.tab],
          leading: false,
          actions: [
            if (model.tab == 0 && summary != null)
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(
                      controller: widget.inventory,
                      backups: widget.backups,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: summary == null
              ? model.failed
                    ? AppErrorState(onRetry: model.refresh)
                    : const LoadingState(label: 'Opening local data')
              : IndexedStack(
                  key: ValueKey(restoreRevision),
                  index: model.tab,
                  children: [
                    if (model.failed)
                      AppErrorState(onRetry: model.refresh)
                    else
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
          child: _Tabs(
            selected: model.tab,
            labels: labels,
            icons: icons,
            onSelected: (index) {
              FocusScope.of(context).unfocus();
              model.selectTab(index);
            },
          ),
        ),
      );
    },
  );
}

/// At large text sizes, two rows keep all four tab names readable without
/// shrinking the user's text or splitting words in the middle.
class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.selected,
    required this.labels,
    required this.icons,
    required this.onSelected,
  });
  final int selected;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        text: const TextSpan(
          text: 'Inventory',
          style: TextStyle(
            fontFamily: 'Vazirmatn',
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final expanded = painter.width + 12 > constraints.maxWidth / 4;
      painter.dispose();
      return Material(
        color: Colors.white,
        child: Wrap(
          children: [
            for (var i = 0; i < labels.length; i++)
              SizedBox(
                width: constraints.maxWidth / (expanded ? 2 : 4),
                child: Semantics(
                  label: labels[i],
                  hint: 'Tab ${i + 1} of 4',
                  selected: selected == i,
                  button: true,
                  excludeSemantics: true,
                  onTap: () => onSelected(i),
                  child: InkWell(
                    onTap: () => onSelected(i),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 64),
                      padding: EdgeInsets.symmetric(
                        horizontal: expanded ? 12 : 4,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected == i && expanded
                            ? const Color(0xFFE3F0ED)
                            : null,
                      ),
                      child: expanded
                          ? Row(
                              children: [
                                Icon(
                                  icons[i],
                                  size: 24,
                                  color: selected == i
                                      ? AppColors.primary
                                      : AppColors.secondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: _label(i)),
                              ],
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected == i
                                        ? const Color(0xFFE3F0ED)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(
                                    icons[i],
                                    color: selected == i
                                        ? AppColors.primary
                                        : AppColors.secondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                _label(i),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
  Widget _label(int i) => Text(
    labels[i],
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: 12,
      fontWeight: selected == i ? FontWeight.w700 : FontWeight.w500,
      color: selected == i ? AppColors.primary : AppColors.secondary,
    ),
  );
}
