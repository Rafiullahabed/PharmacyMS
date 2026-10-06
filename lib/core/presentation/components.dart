import 'package:flutter/material.dart';
import '../domain/money.dart';
import '../domain/dates.dart';
import 'app_theme.dart';

TextDirection contentDirection(String text) {
  final rtl = RegExp(
    r'[\u0620-\u063F\u0641-\u064A\u066E-\u066F\u0671-\u06D3\u06FA-\u06FC\u0750-\u077F]',
  );
  final ltr = RegExp(r'[A-Za-z\u00C0-\u02AF\u0370-\u052F]');
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (rtl.hasMatch(char)) return TextDirection.rtl;
    if (ltr.hasMatch(char)) return TextDirection.ltr;
  }
  return TextDirection.ltr;
}

class ContentText extends StatelessWidget {
  const ContentText(this.text, {super.key, this.style, this.maxLines});
  final String text;
  final TextStyle? style;
  final int? maxLines;
  @override
  Widget build(BuildContext context) {
    // Each paragraph has its own base direction. In particular, an English
    // paragraph after a Persian one must not move its final period to the left.
    if (maxLines == null && text.contains('\n')) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final paragraph in text.split('\n'))
            ContentText(paragraph, style: style),
        ],
      );
    }
    return Text(
      text,
      textDirection: contentDirection(text),
      textAlign: contentDirection(text) == TextDirection.rtl
          ? TextAlign.right
          : TextAlign.left,
      style: style,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}

class MoneyText extends StatelessWidget {
  const MoneyText(this.money, {super.key, this.style}) : total = null;
  const MoneyText.total(this.total, {super.key, this.style}) : money = null;
  final Money? money;
  final BigInt? total;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => Text(
    total == null ? money!.formatted : formatMinorUnits(total!),
    textDirection: TextDirection.ltr,
    style: (style ?? Theme.of(context).textTheme.titleLarge)?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

class PageContent extends StatelessWidget {
  const PageContent({super.key, required this.children, this.storageKey});
  final List<Widget> children;
  final String? storageKey;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Space.contentWidth),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        key: storageKey == null ? null : PageStorageKey(storageKey),
        padding: const EdgeInsets.all(Space.lg),
        children: children,
      ),
    ),
  );
}

class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.title,
    required this.child,
    this.icon,
  });
  final String title;
  final Widget child;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    child: Container(
      margin: const EdgeInsets.only(bottom: Space.lg),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x07172B3A),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F0ED),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                ] else ...[
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          child,
        ],
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title, message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFE3F0ED),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, size: 32, color: AppColors.primary),
        ),
        const SizedBox(height: Space.lg),
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: Space.sm),
        Text(message, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}

/// Titles grow to their measured height, including at 200% text size.
AppBar pageAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
  bool leading = true,
}) {
  final style =
      Theme.of(context).appBarTheme.titleTextStyle ??
      Theme.of(context).textTheme.titleLarge!;
  final painter =
      TextPainter(
        text: TextSpan(text: title, style: style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(
        maxWidth:
            (MediaQuery.sizeOf(context).width -
                    (leading ? 72 : 32) -
                    (actions?.length ?? 0) * 48)
                .clamp(80, double.infinity),
      );
  final height = (painter.height + 16).clamp(56.0, double.infinity);
  painter.dispose();
  return AppBar(
    toolbarHeight: height,
    // AppBar otherwise applies its own text-scale cap after measuring the title.
    title: MediaQuery(
      data: MediaQuery.of(context),
      child: Text(
        title,
        style: style,
        softWrap: true,
        maxLines: 10,
        overflow: TextOverflow.visible,
      ),
    ),
    actions: actions,
    automaticallyImplyLeading: leading,
  );
}

class PageWidth extends StatelessWidget {
  const PageWidth({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Space.contentWidth),
      child: child,
    ),
  );
}

/// A bounded, scrollable loading state also works with the keyboard visible.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label = 'Loading local data…'});
  final String label;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Semantics(
        liveRegion: true,
        label: label,
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (reduceMotion(context))
                const Icon(Icons.hourglass_empty, color: AppColors.primary)
              else
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              const SizedBox(height: 12),
              Text(label, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Consistent search; rebuilding direction never rewrites text or selection.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.label,
    required this.clearLabel,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String label, clearLabel;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(height: 8),
            Semantics(
              label: label,
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                textDirection: contentDirection(value.text),
                textAlign: contentDirection(value.text) == TextDirection.rtl
                    ? TextAlign.right
                    : TextAlign.left,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: value.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: clearLabel,
                          onPressed: () {
                            controller.clear();
                            onChanged('');
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
          ],
        ),
      );
}

class PreviewPanel extends StatelessWidget {
  const PreviewPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: .25)),
      ),
      child: child,
    ),
  );
}

/// Keep labels outside narrow input borders so large text can wrap naturally.
class LabeledControl extends StatelessWidget {
  const LabeledControl({
    super.key,
    required this.label,
    required this.child,
    this.shortLabel,
  });
  final String label;
  final String? shortLabel;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ExcludeSemantics(child: Text(shortLabel ?? label)),
      const SizedBox(height: 8),
      Semantics(label: label, child: child),
    ],
  );
}

String localEventLabel(DateTime instant) {
  final local = instant.toLocal();
  return '${BusinessDate.fromLocal(local).label} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} · Local time';
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({super.key, required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => PageContent(
    children: [
      const EmptyState(
        icon: Icons.storage_outlined,
        title: 'Unable to open local data',
        message:
            'Your information has not been replaced. Check available device storage, then try again.',
      ),
      FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
      ),
    ],
  );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.icon,
    this.color = AppColors.secondary,
  });
  final String label;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .07),
      border: Border.all(color: color.withValues(alpha: .12)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(icon, size: 20, color: color),
        Text(label, style: TextStyle(color: color)),
      ],
    ),
  );
}
