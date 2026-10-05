import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/presentation/app_theme.dart';
import '../domain/daily_report.dart';

class TrendPanel extends StatefulWidget {
  const TrendPanel({super.key, required this.report});
  final DailyReport report;
  @override
  State<TrendPanel> createState() => _TrendPanelState();
}

class _TrendPanelState extends State<TrendPanel>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  bool profit = false, monthly = false;
  int page = 0, selected = -1;
  @override
  void didUpdateWidget(covariant TrendPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report.range.label != widget.report.range.label) {
      page = 0;
      selected = -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final length = monthly
        ? widget.report.months.length
        : widget.report.range.days;
    final window = monthly ? 12 : 31;
    final end = math.max(1, length - page * window);
    final start = math.max(0, end - window);
    final points = [
      for (var i = start; i < end; i++)
        monthly ? widget.report.months[i] : widget.report.dayAt(i),
    ];
    final selection = selected < 0
        ? points.length - 1
        : selected.clamp(0, points.length - 1);
    final point = points[selection];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Recorded trends', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Sales'),
              selected: !profit,
              onSelected: (_) => setState(() => profit = false),
            ),
            ChoiceChip(
              label: const Text('Profit (manual)'),
              selected: profit,
              onSelected: (_) => setState(() => profit = true),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Daily trend'),
              selected: !monthly,
              onSelected: (_) => setState(() {
                monthly = false;
                page = 0;
                selected = -1;
              }),
            ),
            ChoiceChip(
              label: const Text('Monthly totals'),
              selected: monthly,
              onSelected: (_) => setState(() {
                monthly = true;
                page = 0;
                selected = -1;
              }),
            ),
          ],
        ),
        Text(
          monthly
              ? 'Monthly sums within the selected range. Coverage excludes days outside this range.'
              : 'Missing days are gaps. A dot at zero is a recorded zero.',
        ),
        const SizedBox(height: 12),
        if (points.every((p) => !p.recorded))
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('No recorded values in this chart window.'),
          )
        else
          Semantics(
            label:
                '${monthly ? 'Monthly' : 'Daily'} ${profit ? 'manually recorded profit' : 'sales'} chart. Exact values follow. Use previous and next value buttons, or the data list below.',
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                excludeFromSemantics: true,
                onTapUp: (details) => setState(
                  () => selected =
                      ((details.localPosition.dx - 86) /
                              math.max(1, constraints.maxWidth - 102) *
                              math.max(1, points.length - 1))
                          .round()
                          .clamp(0, points.length - 1),
                ),
                child: CustomPaint(
                  key: const ValueKey('daily-trend-plot'),
                  size: Size(constraints.maxWidth, 240),
                  painter: _TrendPainter(
                    values: points
                        .map((p) => p.value(profit)?.toDouble())
                        .toList(),
                    selected: selection,
                    color: profit ? AppColors.danger : AppColors.primary,
                    textScaler: MediaQuery.textScalerOf(context),
                  ),
                ),
              ),
            ),
          ),
        Text(
          '${points.first.label} – ${points.last.label}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Text(
          'Axis values in AFN are approximate. Selected values are exact.',
        ),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Selected: ${point.label}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${profit ? 'Recorded profit' : 'Sales'}: ${point.valueLabel(profit)}',
                  textDirection: TextDirection.ltr,
                ),
                if (profit && (point.value(true)?.isNegative ?? false))
                  const Text('Loss · Below zero'),
                Text(point.totals.coverage),
              ],
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: selection == 0
                  ? null
                  : () => setState(() => selected = selection - 1),
              icon: const Icon(Icons.chevron_left),
              label: const Text('Previous value'),
            ),
            TextButton.icon(
              onPressed: selection == points.length - 1
                  ? null
                  : () => setState(() => selected = selection + 1),
              icon: const Icon(Icons.chevron_right),
              label: const Text('Next value'),
            ),
          ],
        ),
        if (length > window)
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: start == 0
                    ? null
                    : () => setState(() {
                        page++;
                        selected = -1;
                      }),
                child: const Text('Earlier chart window'),
              ),
              OutlinedButton(
                onPressed: page == 0
                    ? null
                    : () => setState(() {
                        page--;
                        selected = -1;
                      }),
                child: const Text('Later chart window'),
              ),
            ],
          ),
        if (monthly)
          ExpansionTile(
            key: const PageStorageKey('monthly-accessible-data'),
            title: const Text('Monthly data · accessible list'),
            tilePadding: EdgeInsets.zero,
            children: [
              for (final month in points)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        month.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(month.range.label),
                      Text('Sales: ${month.valueLabel(false)}'),
                      Text('Recorded profit: ${month.valueLabel(true)}'),
                      Text(month.totals.coverage),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.values,
    required this.selected,
    required this.color,
    required this.textScaler,
  });
  final List<double?> values;
  final int selected;
  final Color color;
  final TextScaler textScaler;
  @override
  void paint(Canvas canvas, Size size) {
    final filled = values.whereType<double>().toList();
    var low = math.min(0.0, filled.reduce(math.min)),
        high = math.max(0.0, filled.reduce(math.max));
    if (low == high) high = 100;
    final top = 24.0,
        bottom = size.height - 24,
        left = 86.0,
        right = size.width - 16;
    double y(double v) => bottom - (v - low) / (high - low) * (bottom - top);
    double x(int i) => values.length == 1
        ? (left + right) / 2
        : left + i * (right - left) / (values.length - 1);
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (final value in {low, 0.0, high}) {
      final yy = y(value);
      canvas.drawLine(
        Offset(left, yy),
        Offset(right, yy),
        grid..color = value == 0 ? AppColors.secondary : AppColors.border,
      );
      final label = TextPainter(
        text: TextSpan(
          text: _axis(value / 100),
          style: const TextStyle(
            fontFamily: 'Vazirmatn',
            fontSize: 11,
            color: AppColors.secondary,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout(maxWidth: 78);
      label.paint(
        canvas,
        Offset(0, (yy - label.height / 2).clamp(0, size.height - label.height)),
      );
    }
    final line = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      final here = Offset(x(i), y(v));
      if (i > 0 && values[i - 1] != null) {
        canvas.drawLine(Offset(x(i - 1), y(values[i - 1]!)), here, line);
      }
      canvas.drawCircle(here, i == selected ? 6 : 3.5, line);
      if (i == selected) {
        canvas.drawCircle(here, 2, Paint()..color = Colors.white);
      }
    }
  }

  String _axis(double value) {
    final abs = value.abs();
    if (abs >= 1e12) return '${(value / 1e12).toStringAsPrecision(3)}T';
    if (abs >= 1e9) return '${(value / 1e9).toStringAsPrecision(3)}B';
    if (abs >= 1e6) return '${(value / 1e6).toStringAsPrecision(3)}M';
    if (abs >= 1e3) return '${(value / 1e3).toStringAsPrecision(3)}k';
    return value == 0 ? '0' : value.toStringAsFixed(2);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.values != values ||
      old.selected != selected ||
      old.color != color ||
      old.textScaler != textScaler;
}
