import 'package:flutter/material.dart';
import '../../../core/domain/dates.dart';
import '../../../core/domain/validation.dart';
import '../../../core/presentation/form_fields.dart';
import '../../../core/presentation/workflow.dart';

enum DateInputMode { full, month, none }

class DateSpecField extends StatefulWidget {
  const DateSpecField({
    super.key,
    required this.label,
    required this.today,
    required this.onChanged,
    this.initial,
    this.expiry = false,
    this.initiallyAbsent = false,
  });
  final String label;
  final BusinessDate today;
  final DateSpec? initial;
  final bool expiry;
  final bool initiallyAbsent;
  final VoidCallback onChanged;
  @override
  State<DateSpecField> createState() => DateSpecFieldState();
}

class DateSpecFieldState extends State<DateSpecField> {
  late DateInputMode mode;
  late DateCalendar calendar;
  final year = TextEditingController(),
      month = TextEditingController(),
      day = TextEditingController();
  DateSpec? _source;
  String? _error;
  int _calendarRevision = 0;
  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    calendar = initial?.calendar ?? DateCalendar.gregorian;
    mode = initial == null
        ? (widget.expiry && !widget.initiallyAbsent
              ? DateInputMode.full
              : DateInputMode.none)
        : initial.day == null
        ? DateInputMode.month
        : DateInputMode.full;
    _source = initial;
    if (initial != null) _write(initial);
  }

  void _write(DateSpec spec) {
    year.text = '${spec.year}';
    month.text = '${spec.month}';
    day.text = spec.day?.toString() ?? '';
  }

  DateSpec? value() {
    if (mode == DateInputMode.none) return null;
    int component(TextEditingController c, String name) {
      final value = int.tryParse(normalizeDigits(c.text.trim()));
      if (value == null) {
        throw ValidationException('Enter ${widget.label.toLowerCase()} $name.');
      }
      return value;
    }

    final entered = DateSpec(
      calendar: calendar,
      year: component(year, 'year'),
      month: component(month, 'month'),
      day: mode == DateInputMode.month ? null : component(day, 'day'),
    );
    return _source ?? entered;
  }

  void _edited() {
    setState(() {
      _source = null;
      _error = null;
    });
    widget.onChanged();
  }

  Future<void> _calendar(DateCalendar next) async {
    if (next == calendar) return;
    if (mode == DateInputMode.month &&
        (year.text.isNotEmpty || month.text.isNotEmpty)) {
      if (!await confirmAction(
        context,
        title: 'Re-enter the month?',
        message:
            'A month covers different dates in each calendar. Changing its source calendar clears these fields so you can enter the intended month again.',
        action: 'Re-enter month',
      )) {
        return;
      }
      year.clear();
      month.clear();
      day.clear();
      _source = null;
    } else if (mode == DateInputMode.full &&
        (year.text.isNotEmpty ||
            month.text.isNotEmpty ||
            day.text.isNotEmpty)) {
      try {
        final original = value()!;
        final shown = original.representationIn(next);
        _source = original;
        _write(shown);
      } on ValidationException catch (e) {
        setState(
          () => _error =
              '${e.message} Complete this date before switching calendars.',
        );
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      calendar = next;
      _error = null;
    });
    widget.onChanged();
  }

  @override
  void dispose() {
    year.dispose();
    month.dispose();
    day.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    DateSpec? preview;
    try {
      preview = value();
    } catch (_) {}
    return FormField<DateSpec>(
      validator: (_) => validationMessage(value),
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<DateInputMode>(
            initialValue: mode,
            isExpanded: true,
            decoration: InputDecoration(labelText: '${widget.label} precision'),
            items: [
              const DropdownMenuItem(
                value: DateInputMode.full,
                child: Text('Full date'),
              ),
              const DropdownMenuItem(
                value: DateInputMode.month,
                child: Text('Month & year'),
              ),
              DropdownMenuItem(
                value: DateInputMode.none,
                child: Text(widget.expiry ? 'No expiry date' : 'Not entered'),
              ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                mode = v;
                _source = null;
                _error = null;
              });
              widget.onChanged();
              field.didChange(null);
            },
          ),
          if (mode != DateInputMode.none) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<DateCalendar>(
              key: ValueKey(
                '${widget.label}-${calendar.name}-$_calendarRevision',
              ),
              initialValue: calendar,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: '${widget.label} calendar',
              ),
              items: const [
                DropdownMenuItem(
                  value: DateCalendar.gregorian,
                  child: Text('Gregorian'),
                ),
                DropdownMenuItem(
                  value: DateCalendar.solarHijri,
                  child: Text('Solar Hijri'),
                ),
              ],
              onChanged: (v) async {
                if (v != null) {
                  await _calendar(v);
                  if (mounted) {
                    setState(() {
                      _calendarRevision++;
                    });
                  }
                }
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in [
                  (year, 'Year'),
                  (month, 'Month'),
                  if (mode == DateInputMode.full) (day, 'Day'),
                ])
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: entry.$1,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: '${widget.label} ${entry.$2.toLowerCase()}',
                      ),
                      onChanged: (_) {
                        _edited();
                        field.didChange(null);
                      },
                    ),
                  ),
              ],
            ),
            if (mode == DateInputMode.full)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text('Choose ${widget.label.toLowerCase()} date'),
                  onPressed: () async {
                    DateSpec initial;
                    try {
                      initial = value()!.representationIn(calendar);
                    } catch (_) {
                      initial = DateSpec(
                        calendar: DateCalendar.gregorian,
                        year: widget.today.year,
                        month: widget.today.month,
                        day: widget.today.day,
                      ).representationIn(calendar);
                    }
                    final selected = await showDialog<DateSpec>(
                      context: context,
                      builder: (_) => _DatePicker(initial),
                    );
                    if (selected != null && mounted) {
                      setState(() {
                        _source = null;
                        _write(selected);
                        _error = null;
                      });
                      widget.onChanged();
                      field.didChange(selected);
                    }
                  },
                ),
              ),
            if (mode == DateInputMode.month && widget.expiry)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'For alerts, a month-only expiry is treated as the end of that month.',
                ),
              ),
            if (preview != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${preview.label}\nGregorian equivalent: ${preview.range.start.label}${preview.day == null ? ' – ${preview.range.end.label}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
          ErrorNotice(_error ?? field.errorText),
        ],
      ),
    );
  }
}

/// Accessible component picker: typed year navigation, month stepping, actual valid days.
/// No day is requested for a month-only specification.
class _DatePicker extends StatefulWidget {
  const _DatePicker(this.initial);
  final DateSpec initial;
  @override
  State<_DatePicker> createState() => _DatePickerState();
}

class _DatePickerState extends State<_DatePicker> {
  late final year = TextEditingController(text: '${widget.initial.year}');
  late int month = widget.initial.month, day = widget.initial.day!;
  String? error;
  int get selectedYear => int.tryParse(normalizeDigits(year.text)) ?? 0;
  int get days {
    try {
      return DateSpec(
        calendar: widget.initial.calendar,
        year: selectedYear,
        month: month,
        day: 1,
      ).daysInMonth;
    } catch (_) {
      return 31;
    }
  }

  void step(int delta) {
    var y = selectedYear, m = month + delta;
    if (m == 0) {
      m = 12;
      y--;
    }
    if (m == 13) {
      m = 1;
      y++;
    }
    try {
      DateSpec(calendar: widget.initial.calendar, year: y, month: m, day: 1);
      setState(() {
        year.text = '$y';
        month = m;
        error = null;
      });
    } on ValidationException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  void dispose() {
    year.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(
      widget.initial.calendar == DateCalendar.gregorian
          ? 'Gregorian date'
          : 'Solar Hijri date',
    ),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: year,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Year'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey('month-$month'),
              initialValue: month,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Month'),
              items: [
                for (var i = 1; i <= 12; i++)
                  DropdownMenuItem(value: i, child: Text('$i')),
              ],
              onChanged: (v) => setState(() {
                month = v!;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey('day-$month-$day-$days'),
              initialValue: day,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Day'),
              items: [
                for (var i = 1; i <= days; i++)
                  DropdownMenuItem(value: i, child: Text('$i')),
                if (day > days)
                  DropdownMenuItem(value: day, child: Text('$day (invalid)')),
              ],
              onChanged: (v) => setState(() => day = v!),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () => step(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: () => step(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            ErrorNotice(error),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () {
          try {
            Navigator.pop(
              context,
              DateSpec(
                calendar: widget.initial.calendar,
                year: selectedYear,
                month: month,
                day: day,
              ),
            );
          } on ValidationException catch (e) {
            setState(() => error = e.message);
          }
        },
        child: const Text('Use date'),
      ),
    ],
  );
}
