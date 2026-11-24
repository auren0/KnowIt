import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:knowit/models/app_settings.dart';

/// Persisted application settings with a listenable in-memory value.
///
/// The settings box stores primitives only, so new settings can be added
/// without breaking existing installations or requiring Hive adapters.
class SettingsService {
  static const String boxName = 'settings';

  static final ValueNotifier<AppSettings> notifier = ValueNotifier(
    AppSettings.defaults,
  );

  static Box? _box;

  static AppSettings get value => notifier.value;

  static Future<void> init() async {
    _box ??= await Hive.openBox(boxName);
    notifier.value = AppSettings.fromFlatMap(_box!.toMap());
  }

  static Future<void> save(AppSettings settings) async {
    notifier.value = settings;
    final box = _box;
    if (box == null) return;
    for (final entry in settings.toFlatMap().entries) {
      await box.put(entry.key, entry.value);
    }
  }

  static Future<void> update(
    AppSettings Function(AppSettings current) transform,
  ) async {
    await save(transform(value));
  }

  static Future<void> reset() async {
    final box = _box;
    if (box != null) await box.clear();
    notifier.value = AppSettings.defaults;
  }

  @visibleForTesting
  static Future<void> replaceForTesting(AppSettings settings) async {
    await save(settings);
  }
}
