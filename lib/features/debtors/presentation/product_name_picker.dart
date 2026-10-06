import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/presentation/components.dart';
import '../application/debt_controller.dart';

/// Only a string crosses this boundary: no product link, quantity or price.
Future<String?> pickProductName(
  BuildContext context,
  DebtController controller,
) => showDialog<String>(
  context: context,
  builder: (_) => _NamesDialog(controller: controller),
);

class _NamesDialog extends StatefulWidget {
  const _NamesDialog({required this.controller});
  final DebtController controller;
  @override
  State<_NamesDialog> createState() => _NamesDialogState();
}

class _NamesDialogState extends State<_NamesDialog> {
  final search = TextEditingController();
  Timer? timer;
  late Future<List<String>> future;
  @override
  void initState() {
    super.initState();
    future = load();
  }

  Future<List<String>> load() async =>
      (await widget.controller.repository).productNames(search.text);
  void changed(String value) {
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          future = load();
        });
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480, maxHeight: 480),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Semantics(
                  namesRoute: true,
                  header: true,
                  child: Text(
                    'Insert item name',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 16),
                SearchField(
                  controller: search,
                  onChanged: changed,
                  label: 'Search item names',
                  clearLabel: 'Clear item search',
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<String>>(
                  future: future,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Column(
                        children: [
                          const Text(
                            'Unable to read item names. You can still type your description.',
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              future = load();
                            }),
                            child: const Text('Retry'),
                          ),
                        ],
                      );
                    }
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const LoadingState(label: 'Loading item names');
                    }
                    final names = snapshot.data!;
                    if (names.isEmpty) {
                      return const Text(
                        'No matching items. Type any description in the form.',
                      );
                    }
                    // Suggestions are bounded to 20; title, search and results
                    // scroll together when the keyboard or large text reduces space.
                    return Column(
                      children: [
                        for (final name in names)
                          ListTile(
                            title: ContentText(name),
                            onTap: () => Navigator.pop(context, name),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
