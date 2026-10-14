import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smartman/shared/theme.dart';

/// Opens the theme storage as the composition site does, over whatever the
/// platform holds.
Future<SharedPreferencesWithCache> _openStorage() =>
    SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: themeStorageKeys,
      ),
    );

/// A run of the app's providers over [storage].
ProviderContainer _run(SharedPreferencesWithCache storage) {
  final container = ProviderContainer(
    overrides: [themeStorageProvider.overrideWithValue(storage)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('with nothing stored the theme follows the system', () async {
    final container = _run(await _openStorage());

    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('a choice applies at once and persists across a restart', () async {
    final first = _run(await _openStorage());
    // Control: a restart before any choice still follows the system.
    expect(
      _run(await _openStorage()).read(themeModeProvider),
      ThemeMode.system,
    );

    await first.read(themeModeProvider.notifier).choose(ThemeMode.dark);
    expect(first.read(themeModeProvider), ThemeMode.dark);

    final restarted = _run(await _openStorage());
    expect(restarted.read(themeModeProvider), ThemeMode.dark);

    await restarted.read(themeModeProvider.notifier).choose(ThemeMode.light);
    expect(_run(await _openStorage()).read(themeModeProvider), ThemeMode.light);
  });

  test('an unknown stored value reads as following the system', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({'themeMode': 'sepia'});
    final storage = await _openStorage();
    expect(storage.getString('themeMode'), 'sepia');

    expect(_run(storage).read(themeModeProvider), ThemeMode.system);
  });

  test('the light and dark themes carry their own tokens and the font', () {
    expect(lightTheme.brightness, Brightness.light);
    expect(lightTheme.extension<AppColors>(), AppColors.light);
    expect(lightTheme.scaffoldBackgroundColor, const Color(0xFFEEF1F5));
    expect(darkTheme.brightness, Brightness.dark);
    expect(darkTheme.extension<AppColors>(), AppColors.dark);
    expect(darkTheme.scaffoldBackgroundColor, const Color(0xFF0F1115));
    expect(lightTheme.textTheme.bodyMedium?.fontFamily, appFontFamily);
    expect(darkTheme.textTheme.bodyMedium?.fontFamily, appFontFamily);
  });

  test('no colour is written outside the theme file', () {
    final colour = RegExp(r'Color\(0x|\bColors\.');
    final sources = {
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.endsWith('.g.dart') &&
            !entity.path.startsWith('lib/study/src/rust/'))
          entity.path: entity.readAsStringSync(),
    };
    // Control: the scan reads the theme file, where every colour is written.
    expect(colour.hasMatch(sources['lib/shared/theme.dart'] ?? ''), isTrue);

    expect([
      for (final MapEntry(key: path, value: source) in sources.entries)
        if (path != 'lib/shared/theme.dart' && colour.hasMatch(source)) path,
    ], isEmpty);
  });
}
