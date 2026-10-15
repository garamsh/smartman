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

  test('a spacing or font-size literal is found, and a token is not', () {
    expect(styleLiterals('EdgeInsets.all(16)'), ['EdgeInsets.all(16)']);
    expect(styleLiterals('EdgeInsets.fromLTRB(4, 0, 4, 8)'), [
      'EdgeInsets.fromLTRB(4, 0, 4, 8)',
    ]);
    expect(styleLiterals('Column(spacing: 12, children: [])'), ['spacing: 12']);
    expect(styleLiterals('const SizedBox(height: 4)'), ['SizedBox(height: 4)']);
    expect(styleLiterals('TextStyle(fontSize: 13)'), ['fontSize: 13']);
    // Controls: tokens, zero, a sum of tokens, a sized child and a computed
    // inset are not spacing literals.
    expect(
      styleLiterals('''
        EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter, AppSpace.s16)
        Row(spacing: AppSpace.s12)
        SizedBox(height: AppSpace.s32 + AppSpace.s20)
        SizedBox(width: 64, child: Text('x'))
        EdgeInsets.only(top: max(0, viewport - total))
      '''),
      isEmpty,
    );
  });

  test('no spacing or font-size literal is written outside the theme and its components', () {
    final sources = _appSources();
    // Control: the scan reads the screens, which build their insets.
    expect(
      sources['lib/deck/src/deck_list_screen.dart'],
      contains('EdgeInsets'),
    );

    expect([
      for (final MapEntry(key: path, value: source) in sources.entries)
        if (path != 'lib/shared/theme.dart' &&
            !path.startsWith('lib/shared/ui/'))
          for (final literal in styleLiterals(source))
            if (!_studyGeometry.contains((path, literal))) '$path: $literal',
    ], isEmpty);
  });

  test('no screen opens a dialog, or a sheet other than the app sheet', () {
    final modal = RegExp(r'\b(AlertDialog|showDialog|showModalBottomSheet)\b');
    final sources = _appSources();
    // Control: the app sheet opens the platform's sheet, so the expression
    // finds what it is meant to.
    expect(
      modal.hasMatch(sources['lib/shared/ui/app_sheet.dart'] ?? ''),
      isTrue,
    );

    expect([
      for (final MapEntry(key: path, value: source) in sources.entries)
        if (path != 'lib/shared/ui/app_sheet.dart' && modal.hasMatch(source))
          path,
    ], isEmpty);
  });

  /// The WCAG 2.1 contrast ratio of two opaque colours.
  double contrast(Color a, Color b) {
    final (lighter, darker) = a.computeLuminance() > b.computeLuminance()
        ? (a, b)
        : (b, a);
    return (lighter.computeLuminance() + 0.05) /
        (darker.computeLuminance() + 0.05);
  }

  for (final (name, colors) in [
    ('light', AppColors.light),
    ('dark', AppColors.dark),
  ]) {
    test('$name text tokens meet WCAG AA, and dots and tints 3:1', () {
      // Text, at 4.5:1: the pairs the screens draw text in, including the
      // answer chips over a dragged card, which no semantics node reaches.
      for (final (text, ground) in [
        (colors.ink, colors.surface),
        (colors.ink, colors.ground),
        (colors.muted, colors.surface),
        (colors.muted, colors.ground),
        (colors.muted, colors.depth),
        (colors.onKnow, colors.know),
        (colors.onDontKnowText, colors.dontKnowText),
        (colors.dontKnowText, colors.surface),
        (colors.surface, colors.ink),
      ]) {
        expect(
          contrast(text, ground),
          greaterThanOrEqualTo(4.5),
          reason: '$text on $ground',
        );
      }
      // Non-text, at 3:1: the answer dots on a previous card.
      for (final dot in [colors.knowDot, colors.dontKnow]) {
        expect(
          contrast(dot, colors.surface),
          greaterThanOrEqualTo(3),
          reason: '$dot on ${colors.surface}',
        );
      }
    });
  }
}

/// Every Dart source under `lib/` keyed by its path under `app/`, leaving out
/// generated code.
Map<String, String> _appSources() => {
  for (final entity in Directory('lib').listSync(recursive: true))
    if (entity is File &&
        entity.path.endsWith('.dart') &&
        !entity.path.endsWith('.g.dart') &&
        !entity.path.startsWith('lib/study/src/rust/') &&
        !entity.path.startsWith('lib/shared/l10n/'))
      entity.path: entity.readAsStringSync(),
};

/// The study screen's computed geometry, the one place a number stands in an
/// inset outside the theme: a previous card's text starts below its dot.
const _studyGeometry = {
  (
    'lib/study/src/previous_cards.dart',
    'EdgeInsets.fromLTRB(\n'
        '      StudyStyle.cardPadding + StudyStyle.dotSize,\n'
        '      StudyStyle.cardPadding * 1.5,\n'
        '      StudyStyle.cardPadding,\n'
        '      StudyStyle.cardPadding,\n'
        '    )',
  ),
};

final _number = RegExp(r'(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])');

bool _hasNonZeroNumber(String text) =>
    _number.allMatches(text).any((match) => double.parse(match[1]!) != 0);

/// The text of [source] from the parenthesis at [open] to the one closing it.
String _balanced(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    switch (source[i]) {
      case '(':
        depth++;
      case ')':
        if (--depth == 0) return source.substring(open, i + 1);
    }
  }
  return source.substring(open);
}

/// The spacing and font-size literals in [source]: an `EdgeInsets` or a
/// childless `SizedBox` built from a number, a `spacing:` given a number, and
/// every `fontSize:`. Zero is no spacing value, so it is allowed.
List<String> styleLiterals(String source) => [
  for (final match in RegExp(
    r'EdgeInsets(?:Directional)?\.\w+(?=\()',
  ).allMatches(source))
    if (_balanced(source, match.end) case final args
        when _hasNonZeroNumber(args))
      '${match[0]}$args',
  for (final match in RegExp(r'\bSizedBox(?=\()').allMatches(source))
    if (_balanced(source, match.end) case final args
        when !args.contains('child:') && _hasNonZeroNumber(args))
      'SizedBox$args',
  for (final match in RegExp(r'spacing:\s*([^,)\n]+)').allMatches(source))
    if (_hasNonZeroNumber(match[1]!)) match[0]!,
  for (final match in RegExp(r'fontSize:\s*[^,)\n]+').allMatches(source))
    match[0]!,
];
