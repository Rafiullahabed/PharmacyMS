import 'package:flutter/material.dart';
import '../../../core/presentation/components.dart';
import '../application/daily_records_controller.dart';

class DailyData<T> extends StatefulWidget {
  const DailyData({
    super.key,
    required this.controller,
    required this.load,
    required this.builder,
    this.listen = true,
    this.route = false,
  });
  final DailyRecordsController controller;
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  final bool listen;
  final bool route;
  @override
  State<DailyData<T>> createState() => _DailyDataState<T>();
}

class _DailyDataState<T> extends State<DailyData<T>> {
  late Future<T> future;
  @override
  void initState() {
    super.initState();
    future = widget.load();
    if (widget.listen) widget.controller.addListener(reload);
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
    if (widget.listen) widget.controller.removeListener(reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      Widget status(Widget child) => widget.route
          ? Scaffold(
              appBar: pageAppBar(context, title: 'Daily record'),
              body: SafeArea(child: child),
            )
          : child;
      if (snapshot.hasError) return status(AppErrorState(onRetry: reload));
      if (snapshot.connectionState != ConnectionState.done) {
        return status(const LoadingState(label: 'Loading daily records'));
      }
      return widget.builder(context, snapshot.data as T);
    },
  );
}
