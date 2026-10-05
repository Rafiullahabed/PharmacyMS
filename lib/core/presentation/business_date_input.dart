import 'package:flutter/material.dart';
import '../domain/dates.dart';
import '../domain/validation.dart';
import 'form_fields.dart';

/// A financial civil date; the picker and typed input preserve the same day.
class BusinessDateInput extends StatelessWidget {
  const BusinessDateInput({
    super.key,
    required this.controller,
    required this.label,
    required this.today,
    this.rejectFuture = false,
  });
  final TextEditingController controller;
  final String label;
  final BusinessDate today;
  final bool rejectFuture;
  BusinessDate parse() =>
      BusinessDate.parse(normalizeDigits(controller.text.trim()));
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppTextField(
        controller: controller,
        label: label,
        forceLtr: true,
        helper: 'Gregorian · YYYY-MM-DD',
        keyboardType: TextInputType.datetime,
        validator: (_) => validationMessage(() {
          final date = parse();
          if (rejectFuture && date.compareTo(today) > 0) {
            throw const ValidationException(
              'Future business dates are not allowed.',
            );
          }
        }),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text('Choose ${label.toLowerCase()}'),
          onPressed: () async {
            var initial = today;
            try {
              initial = parse();
            } on ValidationException {
              /* Keep today for invalid typed input. */
            }
            final last = rejectFuture ? today : BusinessDate(9999, 12, 31);
            if (initial.compareTo(last) > 0) initial = last;
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime(initial.year, initial.month, initial.day),
              firstDate: DateTime(1),
              lastDate: DateTime(last.year, last.month, last.day),
              helpText: '$label · Gregorian',
            );
            if (picked != null && context.mounted) {
              controller.text = BusinessDate.fromLocal(picked).iso;
            }
          },
        ),
      ),
    ],
  );
}
