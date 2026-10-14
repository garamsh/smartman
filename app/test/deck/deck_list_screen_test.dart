import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/shared/database.dart';
import 'package:smartman/shared/l10n/app_localizations.dart';

/// A deck list over decks named "Alpha", "Beta" and "Gamma", whose study
/// screen and header card record the decks they were given.
class _List {
  _List(this.tester, this.repository, this.ids);

  final WidgetTester tester;
  final DeckRepository repository;

  /// Each deck's id by name.
  final Map<String, DeckId> ids;

  /// The decks of every study session opened.
  final sessions = <Set<DeckId>>[];

  /// The decks the header card was last given.
  Set<DeckId>? header;

  Future<void> longPress(String deck) async {
    await tester.longPress(find.text(deck));
    await tester.pumpAndSettle();
  }

  Future<void> tap(String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  /// The deck tile showing [deck].
  Finder tile(String deck) =>
      find.ancestor(of: find.text(deck), matching: find.byType(ListTile));

  bool selected(String deck) => tester.widget<ListTile>(tile(deck)).selected;

  /// Unmounts the list. Unmounting cancels drift's stream query, whose
  /// cleanup timer must fire before the test body ends.
  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<_List> _open(WidgetTester tester) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  var ids = 0;
  final repository = DeckRepository(
    db,
    clock: () => DateTime.utc(2026, 10, 15),
    newId: () => 'deck${ids++}',
  );
  final created = (await tester.runAsync(
    () async => {
      for (final name in ['Alpha', 'Beta', 'Gamma'])
        name: (await repository.createDeck(name)).id,
    },
  ))!;
  final list = _List(tester, repository, created);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deckRepositoryProvider.overrideWithValue(repository),
        studyScreenProvider.overrideWithValue((decks) {
          list.sessions.add(decks.ids);
          return const Scaffold(body: Text('session'));
        }),
        todayCardProvider.overrideWithValue((decks) {
          list.header = decks.ids;
          return const SizedBox();
        }),
        accountScreenProvider.overrideWithValue(Scaffold.new),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DeckListScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return list;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('a long-press enters selection mode with that deck selected', (
    tester,
  ) async {
    final list = await _open(tester);
    expect(find.text('Decks'), findsOneWidget);
    expect(list.selected('Alpha'), isFalse);

    await list.longPress('Beta');

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Study (1)'), findsOneWidget);
    expect(list.selected('Beta'), isTrue);
    expect(list.selected('Alpha'), isFalse);
    await list.close();
  });

  testWidgets(
    'in selection mode a tap adds or removes a deck instead of opening it',
    (tester) async {
      final list = await _open(tester);
      // Control: outside selection mode a tap opens the deck.
      await list.tap('Alpha');
      expect(find.text('No cards yet'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await list.longPress('Alpha');
      await list.tap('Gamma');
      expect(find.text('2 selected'), findsOneWidget);
      expect(list.selected('Gamma'), isTrue);

      await list.tap('Alpha');
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Study (1)'), findsOneWidget);
      expect(list.selected('Alpha'), isFalse);
      expect(find.text('No cards yet'), findsNothing);
      await list.close();
    },
  );

  testWidgets('Study (n) starts one session over exactly the selected decks', (
    tester,
  ) async {
    final list = await _open(tester);
    await list.longPress('Alpha');
    await list.tap('Gamma');

    await list.tap('Study (2)');

    expect(find.text('session'), findsOneWidget);
    expect(list.sessions, [
      {list.ids['Alpha'], list.ids['Gamma']},
    ]);
    await list.close();
  });

  testWidgets('the clear action leaves selection mode', (tester) async {
    final list = await _open(tester);
    await list.longPress('Alpha');

    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pumpAndSettle();

    expect(find.text('Decks'), findsOneWidget);
    expect(find.textContaining('selected'), findsNothing);
    await list.tap('Alpha');
    expect(find.text('No cards yet'), findsOneWidget);
    await list.close();
  });

  testWidgets(
    'a deck deleted while selected leaves the selection, and an empty selection cannot start',
    (tester) async {
      final list = await _open(tester);
      await list.longPress('Alpha');
      TextButton start() => tester.widget<TextButton>(
        find.ancestor(
          of: find.textContaining('Study ('),
          matching: find.byType(TextButton),
        ),
      );
      // Control: while the deck remains, the selection can start.
      expect(start().onPressed, isNotNull);

      await tester.runAsync(
        () => list.repository.deleteDeck(list.ids['Alpha']!),
      );
      await tester.pumpAndSettle();

      expect(find.text('0 selected'), findsOneWidget);
      expect(find.text('Study (0)'), findsOneWidget);
      expect(start().onPressed, isNull);
      await list.close();
    },
  );

  testWidgets('the header card is given every deck', (tester) async {
    final list = await _open(tester);

    expect(list.header, list.ids.values.toSet());
    await list.close();
  });

  testWidgets(
    'a screen reader hears whether each deck is selected and how many are',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final list = await _open(tester);
      await list.longPress('Alpha');

      expect(
        tester.getSemantics(list.tile('Alpha')),
        isSemantics(
          label: 'Alpha',
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(list.tile('Beta')),
        isSemantics(
          label: 'Beta',
          hasSelectedState: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
      expect(find.semantics.byLabel('1 selected'), findsOne);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
      await list.close();
    },
  );
}
