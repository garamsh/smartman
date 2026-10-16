import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The top-level entries `docs/architecture/structure.md` allows under
/// `app/lib/`: the composition site, the shell, the domains and the
/// foundations.
const allowedEntries = {
  'main.dart',
  'home',
  'account',
  'deck',
  'study',
  'sync',
  'sharing',
  'photo_import',
  'design',
  'database',
  'l10n',
};

/// The folders below every domain.
const foundations = {'design', 'database', 'l10n'};

/// The entries under `app/lib/` outside [allowedEntries], given every path
/// under it.
List<String> unlistedEntries(Iterable<String> paths) => [
  for (final entry in {for (final path in paths) path.split('/').first})
    if (!allowedEntries.contains(entry)) entry,
];

/// The import rules of `docs/architecture/structure.md`, checked over Dart
/// sources keyed by their path under `app/lib/`.
///
/// - Nothing in a foundation imports a domain or `home/`.
/// - Nothing but `main.dart` imports `home/`.
/// - Nothing outside a domain's folder imports that domain's `src/`.
List<String> importViolations(Map<String, String> sources) => [
  for (final MapEntry(key: file, value: source) in sources.entries)
    for (final target in importedPaths(file, source)) ?_violation(file, target),
];

/// The foundation files whose importers outside their folder all sit in one
/// domain, or all in `home/`: each serves that one alone, so it belongs there.
List<String> singleUnitFoundations(Map<String, String> sources) {
  final importers = <String, Set<String>>{};
  for (final MapEntry(key: file, value: source) in sources.entries) {
    for (final target in importedPaths(file, source)) {
      if (_unitOf(target) != _unitOf(file)) {
        importers.putIfAbsent(target, () => {}).add(_unitOf(file));
      }
    }
  }
  return [
    for (final MapEntry(key: target, value: units) in importers.entries)
      if (foundations.contains(_unitOf(target)) &&
          units.length == 1 &&
          (units.single == 'home' || _isDomain(units.single)))
        '$target serves ${units.single} alone',
  ];
}

final _directive = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// The paths under `app/lib/` that [file] imports or exports; imports of
/// other packages and of the SDK are left out.
List<String> importedPaths(String file, String source) => [
  for (final match in _directive.allMatches(source))
    ?_resolve(file, match.group(1)!),
];

String? _resolve(String file, String uri) {
  const package = 'package:smartman/';
  if (uri.startsWith(package)) return uri.substring(package.length);
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return null;
  final resolved = Uri.parse('file:///lib/$file').resolve(uri).path;
  return resolved.startsWith('/lib/')
      ? resolved.substring('/lib/'.length)
      : null;
}

/// The top-level entry [path] sits in: a folder, or a file at the top of
/// `lib/`, such as the composition site.
String _unitOf(String path) => path.split('/').first;

bool _isDomain(String unit) =>
    allowedEntries.contains(unit) &&
    unit != 'main.dart' &&
    unit != 'home' &&
    !foundations.contains(unit);

/// The domain folder [path] sits in; null for a foundation, `home/` and the
/// files at the top of `lib/`.
String? _domainOf(String path) {
  final unit = _unitOf(path);
  return path.contains('/') && _isDomain(unit) ? unit : null;
}

String? _violation(String file, String target) {
  final fileUnit = _unitOf(file);
  final targetUnit = _unitOf(target);
  final targetDomain = _domainOf(target);
  if (foundations.contains(fileUnit) &&
      (targetDomain != null || targetUnit == 'home')) {
    return '$file imports ${targetDomain ?? 'home'} ($target), from a foundation';
  }
  if (targetUnit == 'home' && fileUnit != 'home' && file != 'main.dart') {
    return '$file imports home ($target), which only main.dart may';
  }
  final segments = target.split('/');
  if (targetDomain != null &&
      segments.length > 2 &&
      segments[1] == 'src' &&
      _domainOf(file) != targetDomain) {
    return '$file imports $target, inside $targetDomain/src/';
  }
  return null;
}

void main() {
  final lib = Directory('lib');
  final sources = {
    for (final entity in lib.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart'))
        entity.path.substring('lib/'.length): entity.readAsStringSync(),
  };

  test('the app sources break no structural rule', () {
    // The scan reaches the files and resolves both import forms, so an empty
    // result below is not the result of reading nothing.
    expect(
      importedPaths('main.dart', sources['main.dart']!),
      contains('deck/deck.dart'),
    );
    expect(
      importedPaths(
        'deck/src/deck_repository.dart',
        sources['deck/src/deck_repository.dart']!,
      ),
      contains('database/database.dart'),
    );
    final paths = [
      for (final entity in lib.listSync(recursive: true))
        if (entity is File) entity.path.substring('lib/'.length),
    ];
    expect(paths, contains('design/theme.dart'));

    expect(unlistedEntries(paths), isEmpty);
    expect(importViolations(sources), isEmpty);
    expect(singleUnitFoundations(sources), isEmpty);
  });

  test(
    'an entry outside the closed list is refused, and a listed one is not',
    () {
      expect(unlistedEntries(['shared/theme.dart', 'utils.dart']), [
        'shared',
        'utils.dart',
      ]);
      expect(
        unlistedEntries([
          'main.dart',
          'home/home_screen.dart',
          'deck/deck.dart',
          'design/theme.dart',
          'database/database.dart',
          'l10n/app_localizations.dart',
        ]),
        isEmpty,
      );
    },
  );

  test('a foundation importing a domain or home is refused, and importing a foundation is not', () {
    expect(
      importViolations({
        'design/app_button.dart': "import '../deck/deck.dart';",
        'database/database.dart': "import 'package:smartman/home/shell.dart';",
      }),
      [
        'design/app_button.dart imports deck (deck/deck.dart), from a foundation',
        'database/database.dart imports home (home/shell.dart), from a foundation',
      ],
    );
    expect(
      importViolations({
        'design/app_button.dart': "import '../l10n/app_localizations.dart';",
        'design/theme_choice.dart': "import 'theme.dart';",
      }),
      isEmpty,
    );
  });

  test('importing home from anywhere but main.dart is refused, and from main.dart it is not', () {
    expect(
      importViolations({'deck/deck.dart': "import '../home/shell.dart';"}),
      [
        'deck/deck.dart imports home (home/shell.dart), which only main.dart may',
      ],
    );
    expect(
      importViolations({
        'main.dart': "import 'home/shell.dart';",
        'home/shell.dart': "import 'tabs.dart';",
      }),
      isEmpty,
    );
  });

  test("reaching into a domain's src from outside is refused, and its surface or its own src is not", () {
    expect(
      importViolations({
        'study/study.dart': "import 'package:smartman/deck/src/model.dart';",
        'main.dart': "import 'deck/src/deck_repository.dart';",
        'home/shell.dart': "import '../deck/src/model.dart';",
      }),
      [
        'study/study.dart imports deck/src/model.dart, inside deck/src/',
        'main.dart imports deck/src/deck_repository.dart, inside deck/src/',
        'home/shell.dart imports deck/src/model.dart, inside deck/src/',
      ],
    );
    expect(
      importViolations({
        'study/study.dart': "import 'package:smartman/deck/deck.dart';",
        'main.dart': "import 'deck/deck.dart';",
        'deck/deck.dart': "export 'src/model.dart';",
        'deck/src/card_list_screen.dart': "import 'model.dart';",
      }),
      isEmpty,
    );
  });

  test('a foundation file serving one domain alone, or home alone, is refused, and one serving two is not', () {
    expect(
      singleUnitFoundations({
        'design/card_text.dart': '',
        'deck/src/content_view.dart': "import '../../design/card_text.dart';",
        'deck/src/card_preview.dart': "import '../../design/card_text.dart';",
        'design/tabs.dart': '',
        'home/shell.dart': "import '../design/tabs.dart';",
      }),
      [
        'design/card_text.dart serves deck alone',
        'design/tabs.dart serves home alone',
      ],
    );
    expect(
      singleUnitFoundations({
        'design/mascot.dart': '',
        'deck/src/first_run.dart': "import '../../design/mascot.dart';",
        'study/src/completion_card.dart': "import '../../design/mascot.dart';",
        // Imported by its own folder and main.dart alone: no domain to move to.
        'design/theme_choice.dart': '',
        'design/theme.dart': "import 'theme_choice.dart';",
        'main.dart': "import 'design/theme_choice.dart';",
      }),
      isEmpty,
    );
  });
}
