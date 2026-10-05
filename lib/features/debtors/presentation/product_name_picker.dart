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
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Insert item name'),
    content: SizedBox(
      width: 480,
      height: 320,
      child: Column(
        children: [
          TextField(
            controller: search,
            onChanged: changed,
            decoration: const InputDecoration(
              labelText: 'Search item names',
              prefixIcon: Icon(Icons.search),
            ),
            textDirection: contentDirection(search.text),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<String>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ListView(
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
                  return const Center(child: CircularProgressIndicator());
                }
                final names = snapshot.data!;
                if (names.isEmpty) {
                  return const Center(
                    child: Text(
                      'No matching items. Type any description in the form.',
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: names.length,
                  itemBuilder: (context, i) => ListTile(
                    title: ContentText(names[i]),
                    onTap: () => Navigator.pop(context, names[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}
