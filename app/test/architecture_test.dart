import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The import rules of `docs/architecture/structure.md`, checked over Dart
/// sources keyed by their path under `app/lib/`.
///
/// - Nothing under `shared/` imports a domain.
/// - Nothing outside a domain's folder imports that domain's `src/`.
List<String> importViolations(Map<String, String> sources) => [
  for (final MapEntry(key: file, value: source) in sources.entries)
    for (final target in importedPaths(file, source)) ?_violation(file, target),
];

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

/// The domain folder [path] sits in; null for `shared/` and for files at the
/// top of `lib/`, such as the composition site.
String? _domainOf(String path) {
  final segments = path.split('/');
  if (segments.length < 2 || segments.first == 'shared') return null;
  return segments.first;
}

String? _violation(String file, String target) {
  final targetDomain = _domainOf(target);
  if (file.startsWith('shared/') && targetDomain != null) {
    return '$file imports the domain $targetDomain ($target)';
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
  test('the app sources break no import rule', () {
    final lib = Directory('lib');
    final sources = {
      for (final entity in lib.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          entity.path.substring('lib/'.length): entity.readAsStringSync(),
    };
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
      contains('shared/database.dart'),
    );

    expect(importViolations(sources), isEmpty);
  });

  test('shared code importing a domain is refused, and importing shared code is not', () {
    expect(
      importViolations({'shared/database.dart': "import '../deck/deck.dart';"}),
      ['shared/database.dart imports the domain deck (deck/deck.dart)'],
    );
    expect(
      importViolations({
        'shared/database.dart': "import 'l10n/app_localizations.dart';",
      }),
      isEmpty,
    );
  });

  test("reaching into a domain's src from outside is refused, and its surface or its own src is not", () {
    expect(
      importViolations({
        'study/study.dart': "import 'package:smartman/deck/src/model.dart';",
        'main.dart': "import 'deck/src/deck_repository.dart';",
      }),
      [
        'study/study.dart imports deck/src/model.dart, inside deck/src/',
        'main.dart imports deck/src/deck_repository.dart, inside deck/src/',
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
}
