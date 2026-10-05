import 'package:flutter/material.dart';
import '../domain/money.dart';
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
  const ContentText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => Text(
    text,
    textDirection: contentDirection(text),
    textAlign: contentDirection(text) == TextDirection.rtl
        ? TextAlign.right
        : TextAlign.left,
    style: style,
  );
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
        key: storageKey == null ? null : PageStorageKey(storageKey),
        padding: const EdgeInsets.all(Space.lg),
        children: children,
      ),
    ),
  );
}

class Section extends StatelessWidget {
  const Section({super.key, required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: Space.md),
        child,
      ],
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
    padding: const EdgeInsets.symmetric(vertical: Space.xxl),
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
        const SizedBox(height: Space.xl),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: Space.sm),
        Text(message, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
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
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(8),
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
