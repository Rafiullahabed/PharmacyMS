import 'package:flutter/foundation.dart';
import '../domain/settings_repository.dart';

enum DisplaySize {
  small('Small', .8125),
  medium('Medium', .875),
  large('Large', 1);

  const DisplaySize(this.label, this.factor);
  final String label;
  final double factor;
}

class AppearanceController extends ChangeNotifier {
  AppearanceController(this.resolve);
  static const preferenceKey = 'appearance.display_size';
  final Future<SettingsRepository> Function() resolve;
  DisplaySize size = DisplaySize.medium;
  bool loading = true, saving = false, _disposed = false;
  bool _reloadAfterSave = false;
  String? error;
  int _generation = 0;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    if (saving) {
      _reloadAfterSave = true;
      return;
    }
    final generation = ++_generation;
    loading = true;
    error = null;
    _notify();
    try {
      final saved = await (await resolve()).preference(preferenceKey);
      if (_disposed || generation != _generation) return;
      size =
          DisplaySize.values.where((s) => s.name == saved?.value).firstOrNull ??
          DisplaySize.medium;
    } catch (_) {
      if (!_disposed && generation == _generation) {
        error =
            'Unable to read display size. Retry when local storage is available.';
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> select(DisplaySize value) async {
    if (loading || saving || value == size) return;
    ++_generation;
    saving = true;
    error = null;
    _notify();
    try {
      await (await resolve()).setPreference(preferenceKey, value.name);
      if (!_disposed) size = value;
    } catch (_) {
      error =
          'Unable to save display size. Your previous size is kept. Try again.';
    } finally {
      saving = false;
      _notify();
      if (_reloadAfterSave && !_disposed) {
        _reloadAfterSave = false;
        await load();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
