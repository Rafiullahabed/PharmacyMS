import 'package:flutter/material.dart';
import '../../../core/presentation/app_theme.dart';
import '../../../core/presentation/components.dart';
import '../../../core/presentation/workflow.dart';
import '../application/appearance_controller.dart';
import '../domain/settings_repository.dart';

class AppearanceScope extends InheritedNotifier<AppearanceController> {
  const AppearanceScope({
    super.key,
    required AppearanceController controller,
    required super.child,
  }) : super(notifier: controller);
  static AppearanceController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()?.notifier;
}

/// Compose the chosen app size with OS accessibility scaling, without a cap.
class AppTextScaler extends TextScaler {
  const AppTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;
  @override
  double scale(double fontSize) => system.scale(fontSize * factor);
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) =>
      other is AppTextScaler &&
      other.system == system &&
      other.factor == factor;
  @override
  int get hashCode => Object.hash(system, factor);
}

class AppearanceSettings extends StatefulWidget {
  const AppearanceSettings({super.key, required this.resolve});
  final Future<SettingsRepository> Function() resolve;
  @override
  State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  AppearanceController? model;
  bool owns = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (model != null) return;
    model = AppearanceScope.maybeOf(context);
    if (model == null) {
      owns = true;
      model = AppearanceController(widget.resolve)..load();
    }
  }

  @override
  void dispose() {
    if (owns) model?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model!,
    builder: (context, _) => Section(
      title: 'Appearance',
      icon: Icons.tune_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Text & control size'),
          const SizedBox(height: 6),
          Text(
            'Medium is the default. Large matches the previous text size.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final size in DisplaySize.values)
                ChoiceChip(
                  label: Text(size.label),
                  selected: model!.size == size,
                  onSelected: model!.loading || model!.saving
                      ? null
                      : (_) => model!.select(size),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A comfortable view',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text('Inventory, daily records and customer debt.'),
                const ContentText('داروخانه · Pharmacy'),
              ],
            ),
          ),
          if (model!.saving || model!.loading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(model!.saving ? 'Saving size…' : 'Loading size…'),
              ),
            ),
          ErrorNotice(model!.error),
          if (model!.error != null && !model!.saving)
            TextButton(
              onPressed: model!.load,
              child: const Text('Retry size settings'),
            ),
        ],
      ),
    ),
  );
}
