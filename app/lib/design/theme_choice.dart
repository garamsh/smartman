import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The device storage the theme choice is kept in. The composition site
/// overrides it with the storage it opens.
final themeStorageProvider = Provider<SharedPreferencesWithCache>(
  (ref) => throw UnimplementedError(
    'themeStorageProvider is overridden at the composition site',
  ),
);

/// The keys [themeStorageProvider] must be opened to cache.
const themeStorageKeys = {_themeModeKey};

const _themeModeKey = 'themeMode';

/// The theme the user chose: following the system, light or dark.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// Reads the stored choice, [ThemeMode.system] when none or an unknown one is
/// stored, and applies and stores a new one.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final stored = ref.watch(themeStorageProvider).getString(_themeModeKey);
    return ThemeMode.values.asNameMap()[stored] ?? ThemeMode.system;
  }

  /// Applies [mode] at once, then stores it.
  Future<void> choose(ThemeMode mode) async {
    state = mode;
    await ref.read(themeStorageProvider).setString(_themeModeKey, mode.name);
  }
}
