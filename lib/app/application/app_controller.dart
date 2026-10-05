import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/domain/dates.dart';
import '../../features/home/domain/home_summary.dart';

/// All application state uses ChangeNotifier. Widgets own only transient input.
class AppController extends ChangeNotifier {
  AppController({required this.load, required this.clock});
  final Future<HomeSummary> Function(BusinessDate today) load;
  final AppClock clock;
  HomeSummary? summary;
  bool loading = false, failed = false;
  int tab = 0;
  bool _disposed = false;
  bool _refreshPending = false;
  Timer? _dayTimer;
  void selectTab(int index) {
    if (index < 0 || index > 3 || index == tab) return;
    tab = index;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (loading) {
      _refreshPending = true;
      return;
    }
    loading = true;
    failed = false;
    notifyListeners();
    try {
      do {
        _refreshPending = false;
        final day = clock.today();
        try {
          final result = await load(day);
          if (day != clock.today()) _refreshPending = true;
          if (!_disposed && !_refreshPending) {
            summary = result;
            failed = false;
          }
        } catch (_) {
          if (!_disposed && !_refreshPending) failed = true;
        }
      } while (_refreshPending && !_disposed);
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void startDayWatch() {
    _dayTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => refreshIfDayChanged(),
    );
  }

  Future<void> refreshIfDayChanged() async {
    if (summary?.today != clock.today()) await refresh();
  }

  void stopDayWatch() {
    _dayTimer?.cancel();
    _dayTimer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    stopDayWatch();
    super.dispose();
  }
}
