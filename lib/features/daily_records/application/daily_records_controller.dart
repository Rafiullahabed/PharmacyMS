import 'package:flutter/foundation.dart';
import '../../../core/domain/dates.dart';
import '../domain/daily_record.dart';

/// Financial refreshes never mutate or derive values from inventory/debt.
class DailyRecordsController extends ChangeNotifier {
  DailyRecordsController({required this.resolve, required this.clock})
    : _day = clock.today();
  final Future<DailyRecordsRepository> Function() resolve;
  final AppClock clock;
  Future<DailyRecordsRepository>? _repository;
  BusinessDate _day;
  bool _disposed = false;
  Future<DailyRecordsRepository> get repository async {
    try {
      return await (_repository ??= resolve());
    } catch (_) {
      _repository = null;
      rethrow;
    }
  }

  void changed() {
    if (_disposed) return;
    _day = clock.today();
    notifyListeners();
  }

  void resetRepositories() {
    _repository = null;
    changed();
  }

  void refreshDay() {
    if (_day != clock.today()) changed();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
