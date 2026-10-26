import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/deck/src/label_presets.dart';
import 'package:smartman/deck/src/label_presets_screen.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/l10n/app_localizations.dart';

import '../study/study_storage.dart';

/// The 품사 표시 row on a settings screen of its own, over device storage in
/// memory.
Future<SharedPreferencesWithCache> _open(
  WidgetTester tester, {
  ThemeMode themeMode = ThemeMode.light,
}) async {
  final storage = await openStudyStorage(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [deckStorageProvider.overrideWithValue(storage)],
      child: MaterialApp(
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: PartOfSpeechPresetsRow()),
      ),
    ),
  );
  await tester.tap(find.text('Labels'));
  await tester.pumpAndSettle();
  return storage;
}

List<String> _shown(WidgetTester tester) => [
  for (final row in tester.widgetList<Semantics>(
    find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          (widget.properties.label?.startsWith('Edit ') ?? false),
    ),
  ))
    row.properties.label!,
];

/// How many presets the screen lists, those scrolled out of view included.
int _count(WidgetTester tester) => tester
    .widget<ReorderableListView>(find.byType(ReorderableListView))
    .itemCount;

List<String> _stored(SharedPreferencesWithCache storage) => [
  for (final preset in labelPresets(storage, const []))
    '${preset.label}:${preset.name}',
];

void main() {
  testWidgets(
    'the row opens the screen, which starts from the fourteen short forms with their names',
    (tester) async {
      await _open(tester);
      expect(find.byType(PartOfSpeechPresetsScreen), findsOneWidget);
      expect(_count(tester), 14);
      final shown = _shown(tester);
      expect(shown.first, 'Edit 명 noun');
      expect(shown[1], 'Edit 동 verb');
    },
  );

  testWidgets(
    'a preset is added, renamed and removed, each change stored on the device at once',
    (tester) async {
      final storage = await _open(tester);
      expect(_stored(storage), isEmpty, reason: 'nothing stored yet');

      await tester.scrollUntilVisible(find.text('Add label'), 200);
      await tester.tap(find.text('Add label'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Label'), '숙어');
      await tester.enterText(
        find.widgetWithText(TextField, 'Name (optional)'),
        'idiom',
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(_stored(storage).length, 15);
      expect(_stored(storage).last, '숙어:idiom');

      await tester.scrollUntilVisible(
        find.bySemanticsLabel('Edit 숙어 idiom'),
        200,
      );
      await tester.tap(find.bySemanticsLabel('Edit 숙어 idiom'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Label'), '관용');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(_stored(storage).last, '관용:idiom');

      await tester.tap(find.byTooltip('Remove 관용'));
      await tester.pumpAndSettle();
      expect(_stored(storage).length, 14);
      expect(_stored(storage), isNot(contains('관용:idiom')));
    },
  );

  testWidgets(
    'an empty label is refused with a message, and an added row left empty goes',
    (tester) async {
      final storage = await _open(tester);
      await tester.tap(find.bySemanticsLabel('Edit 명 noun'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Label'), ' ');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Write a label'), findsOneWidget);
      expect(_stored(storage), isEmpty, reason: 'nothing stored');

      await tester.enterText(find.widgetWithText(TextField, 'Label'), '명');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Write a label'), findsNothing, reason: 'control');

      await tester.scrollUntilVisible(find.text('Add label'), 200);
      await tester.tap(find.text('Add label'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Write a label'), findsNothing);
      expect(_count(tester), 14, reason: 'the empty row went');
    },
  );

  testWidgets(
    'a preset moves up or down through its handle\'s menu, without a drag, and the order is stored',
    (tester) async {
      final storage = await _open(tester);
      await tester.tap(find.byTooltip('Move 동'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move up'));
      await tester.pumpAndSettle();
      expect(_shown(tester).take(2), ['Edit 동 verb', 'Edit 명 noun']);
      expect(_stored(storage).take(2), ['동:verb', '명:noun']);

      await tester.tap(find.byTooltip('Move 동'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PopupMenuItem<dynamic>>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is PopupMenuItem &&
                    (widget.child as Text?)?.data == 'Move up',
              ),
            )
            .enabled,
        isFalse,
        reason: 'the first cannot move up',
      );
      await tester.tap(find.text('Move down'));
      await tester.pumpAndSettle();
      expect(_stored(storage).take(2), ['명:noun', '동:verb']);
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'in the ${mode.name} theme the screen meets the tap target, label and contrast guidelines, a preset being edited included',
      (tester) async {
        await _open(tester, themeMode: mode);
        await tester.tap(find.bySemanticsLabel('Edit 명 noun'));
        await tester.pumpAndSettle();
        final handle = tester.ensureSemantics();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      },
    );
  }
}
