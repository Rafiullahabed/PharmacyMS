import 'package:flutter/material.dart';
import '../domain/dates.dart';
import '../domain/money.dart';
import '../domain/validation.dart';
import 'components.dart';

String? validationMessage(void Function() validate) {
  try {
    validate();
    return null;
  } on ValidationException catch (e) {
    return e.message;
  }
}

TextDirection inputDirection(
  TextEditingValue value, {
  required bool multiline,
}) {
  if (multiline && value.selection.isValid) {
    final offset = value.selection.extentOffset.clamp(0, value.text.length);
    final start = offset == 0
        ? 0
        : value.text.lastIndexOf('\n', offset - 1) + 1;
    final end = value.text.indexOf('\n', offset);
    final paragraph = value.text.substring(
      start,
      end < 0 ? value.text.length : end,
    );
    if (paragraph.trim().isNotEmpty) return contentDirection(paragraph);
  }
  return contentDirection(value.text);
}

/// Labels stay LTR; only editable content follows its first strong character.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.helper,
    this.maxLines = 1,
    this.keyboardType,
    this.forceLtr = false,
    this.focusNode,
    this.hint,
    this.autofocus = false,
    this.onChanged,
    this.shortLabel,
  });
  final TextEditingController controller;
  final String label;
  final String? helper;
  final FormFieldValidator<String>? validator;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool forceLtr;
  final FocusNode? focusNode;
  final String? hint;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final String? shortLabel;
  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Text(
                widget.shortLabel ?? widget.label,
                textDirection: TextDirection.ltr,
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              label: widget.label,
              child: TextFormField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                autofocus: widget.autofocus,
                onChanged: widget.onChanged,
                textInputAction: widget.maxLines > 1
                    ? TextInputAction.newline
                    : TextInputAction.next,
                validator: widget.validator,
                maxLines: widget.maxLines,
                keyboardType: widget.keyboardType,
                textDirection: widget.forceLtr
                    ? TextDirection.ltr
                    : inputDirection(value, multiline: widget.maxLines > 1),
                textAlign:
                    !widget.forceLtr &&
                        inputDirection(value, multiline: widget.maxLines > 1) ==
                            TextDirection.rtl
                    ? TextAlign.right
                    : TextAlign.left,
                decoration: InputDecoration(hintText: widget.hint),
                errorBuilder: (context, error) => Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
            ),
            if (widget.helper != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  widget.helper!,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      );
}

class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.allowNegative = false,
  });
  final TextEditingController controller;
  final String label;
  final bool allowNegative;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppTextField(
        controller: controller,
        label: '$label (AFN)',
        forceLtr: true,
        keyboardType: TextInputType.numberWithOptions(
          decimal: true,
          signed: allowNegative,
        ),
        validator: (value) => validationMessage(() {
          final money = Money.parse(value ?? '');
          if (!allowNegative && money.minor < 0) {
            throw const ValidationException('Enter a nonnegative amount.');
          }
        }),
      ),
      if (allowNegative)
        TextButton.icon(
          icon: const Icon(Icons.exposure),
          label: const Text('Switch profit / loss sign'),
          onPressed: () {
            final value = controller.text.trim().replaceAll('−', '-');
            controller.text = value.startsWith('-')
                ? value.substring(1)
                : '-${value.replaceFirst(RegExp(r'^\+'), '')}';
            controller.selection = TextSelection.collapsed(
              offset: controller.text.length,
            );
          },
        ),
    ],
  );
}

class QuantityField extends StatelessWidget {
  const QuantityField({
    super.key,
    required this.controller,
    required this.label,
    this.positive = false,
  });
  final TextEditingController controller;
  final String label;
  final bool positive;
  @override
  Widget build(BuildContext context) => AppTextField(
    controller: controller,
    label: label,
    forceLtr: true,
    keyboardType: TextInputType.number,
    validator: (value) =>
        validationMessage(() => wholeQuantity(value ?? '', positive: positive)),
  );
}

class BusinessDateField extends StatelessWidget {
  const BusinessDateField({
    super.key,
    required this.controller,
    required this.label,
  });
  final TextEditingController controller;
  final String label;
  @override
  Widget build(BuildContext context) => AppTextField(
    controller: controller,
    label: label,
    forceLtr: true,
    helper: 'Gregorian · YYYY-MM-DD',
    keyboardType: TextInputType.datetime,
    validator: (value) => validationMessage(
      () => BusinessDate.parse(normalizeDigits(value ?? '')),
    ),
  );
}

class SaveFooter extends StatelessWidget {
  const SaveFooter({
    super.key,
    required this.onSave,
    required this.saving,
    this.label = 'Save',
  });
  final VoidCallback onSave;
  final bool saving;
  final String label;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: FilledButton(
        onPressed: saving ? null : onSave,
        child: Semantics(
          liveRegion: true,
          child: Text(saving ? 'Saving…' : label),
        ),
      ),
    ),
  );
}
