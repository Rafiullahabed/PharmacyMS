import 'package:flutter/material.dart';
import 'components.dart';

/// Refreshable repository read with stale-future suppression and safe retry.
class RepositoryView<T> extends StatefulWidget {
  const RepositoryView({
    super.key,
    required this.changes,
    required this.load,
    required this.builder,
    this.routeTitle,
  });
  final Listenable changes;
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  final String? routeTitle;
  @override
  State<RepositoryView<T>> createState() => _RepositoryViewState<T>();
}

class _RepositoryViewState<T> extends State<RepositoryView<T>> {
  late Future<T> future;
  @override
  void initState() {
    super.initState();
    future = widget.load();
    widget.changes.addListener(reload);
  }

  void reload() {
    if (mounted) {
      setState(() {
        future = widget.load();
      });
    }
  }

  @override
  void dispose() {
    widget.changes.removeListener(reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      Widget status(Widget child) => widget.routeTitle == null
          ? child
          : Scaffold(
              appBar: AppBar(title: Text(widget.routeTitle!)),
              body: SafeArea(child: child),
            );
      if (snapshot.hasError) return status(AppErrorState(onRetry: reload));
      if (snapshot.connectionState != ConnectionState.done) {
        return status(
          const Center(
            child: CircularProgressIndicator(
              semanticsLabel: 'Loading local data',
            ),
          ),
        );
      }
      return widget.builder(context, snapshot.data as T);
    },
  );
}
