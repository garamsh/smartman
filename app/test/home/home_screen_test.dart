import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/home/src/home_screen.dart';
import 'package:smartman/l10n/app_localizations.dart';
import 'package:smartman/photo_import/photo_import.dart';
import 'package:smartman/study/study.dart';

import 'home_data.dart';

/// The home screen over decks named "Alpha", "Beta" and "Gamma".
class _List {
  _List(this.tester, this.repository, this.ids)
    : _semantics = tester.ensureSemantics();

  final WidgetTester tester;
  final SemanticsHandle _semantics;
  final DeckRepository repository;

  /// Each deck's id by name.
  final Map<String, DeckId> ids;

  /// The decks of the study session open on top.
  Set<DeckId> get session =>
      tester.widget<StudyScreen>(find.byType(StudyScreen)).decks.ids;

  Future<void> longPress(String deck) async {
    await tester.longPress(find.text(deck));
    await tester.pumpAndSettle();
  }

  Future<void> tap(String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  /// The row showing [deck].
  Finder row(String deck) =>
      find.ancestor(of: find.text(deck), matching: find.byType(InkWell)).first;

  bool selected(String deck) =>
      isSemantics(isSelected: true).matches(tester.getSemantics(row(deck)), {});

  /// Unmounts the list. Unmounting cancels drift's stream query, whose
  /// cleanup timer must fire before the test body ends.
  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    _semantics.dispose();
  }
}

/// Opens the home screen, with in each deck named in [fresh] that many new
/// cards, in each named in [due] that many cards due today after an interval
/// of [dueDays] days, and in each named in [later] that many due tomorrow.
/// [pace] is the time the user's answers took; [unreadable] names the decks
/// whose cards cannot be read. [photoImport] stands in for the photo import
/// screen when given.
Future<_List> _open(
  WidgetTester tester, {
  Map<String, int> fresh = const {},
  Map<String, int> due = const {},
  int dueDays = 1,
  Map<String, int> later = const {},
  Duration? pace,
  Set<String> unreadable = const {},
  Widget Function(DeckId? deck)? photoImport,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  var ids = 0;
  final repository = UnreadableDecks(
    db,
    clock: () => DateTime.utc(2026, 10, 15),
    newId: () => 'deck${ids++}',
  );
  final created = (await tester.runAsync(() async {
    final created = {
      for (final name in ['Alpha', 'Beta', 'Gamma'])
        name: (await repository.createDeck(name)).id,
    };
    Future<CardId> add(String deck, String front) async =>
        switch (await repository.addCard(
          created[deck]!,
          front: [TextContent(front)],
          back: [TextContent(front)],
        )) {
          CardSaved(:final card) => card.id,
          DuplicateFront() => fail('the deck held no duplicate'),
        };
    for (final MapEntry(key: name, value: count) in fresh.entries) {
      for (var i = 0; i < count; i++) {
        await add(name, '$name new $i');
      }
    }
    for (final MapEntry(key: name, value: count) in due.entries) {
      for (var i = 0; i < count; i++) {
        final card = await add(name, '$name due $i');
        await storeState(db, card, due: homeNow, days: dueDays);
        if (pace != null) await storeAnswers(db, card, 20, pace);
      }
    }
    for (final MapEntry(key: name, value: count) in later.entries) {
      for (var i = 0; i < count; i++) {
        final card = await add(name, '$name later $i');
        await storeState(db, card, due: homeNow.add(const Duration(days: 1)));
      }
    }
    return created;
  }))!;
  repository.unreadable.addAll([for (final name in unreadable) created[name]!]);
  final list = _List(tester, repository, created);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deckRepositoryProvider.overrideWithValue(repository),
        ...homeOverrides(db),
        if (photoImport != null)
          photoImportProvider.overrideWithValue(photoImport),
      ],
      child: MaterialApp(
        theme: lightTheme,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomeScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return list;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
    'each row shows its deck name, card count and chevron, and a today chip only when the deck has cards for today',
    (tester) async {
      const unreadable =
          "Couldn't read or write the device's storage. Please try again.";
      final list = await _open(
        tester,
        fresh: {'Alpha': 2},
        due: {'Alpha': 1},
        later: {'Beta': 1},
        unreadable: {'Gamma'},
      );

      Finder inRow(String deck, Finder finder) =>
          find.descendant(of: list.row(deck), matching: finder);
      expect(inRow('Alpha', find.text('3 cards')), findsOneWidget);
      expect(inRow('Alpha', find.text('Today 3')), findsOneWidget);
      expect(
        inRow('Alpha', find.byIcon(LucideIcons.chevronRight)),
        findsOneWidget,
      );
      expect(inRow('Beta', find.text('1 card')), findsOneWidget);
      expect(inRow('Beta', find.textContaining('Today')), findsNothing);
      expect(inRow('Gamma', find.text('0 cards')), findsOneWidget);
      expect(inRow('Gamma', find.textContaining('Today')), findsNothing);
      expect(inRow('Gamma', find.byTooltip(unreadable)), findsOneWidget);
      expect(find.text('My decks 3'), findsOneWidget);
      expect(find.text('Long-press to select several decks'), findsOneWidget);
      await list.close();
    },
  );

  testWidgets(
    'the header counts every deck, splits due from new, and Study all studies every deck',
    (tester) async {
      final list = await _open(
        tester,
        fresh: {'Alpha': 2, 'Gamma': 1},
        due: {'Alpha': 1, 'Beta': 3},
        pace: const Duration(seconds: 25),
      );

      expect(find.bySemanticsLabel('7 cards for today'), findsOneWidget);
      // Seven cards at 25 s each take 175 s, about 3 minutes.
      expect(find.text('4 to review · 3 new · about 3 min'), findsOneWidget);

      await list.tap('Study all');

      expect(list.session, list.ids.values.toSet());
      await list.close();
    },
  );

  testWidgets(
    'in a backlog the header says new cards wait, and not otherwise',
    (tester) async {
      const paused = 'New cards wait until you catch up on your reviews.';
      // Seven reviews due after 30-day intervals are far more than three
      // days' load, so the new card waits.
      var list = await _open(
        tester,
        fresh: {'Gamma': 1},
        due: {'Alpha': 4, 'Beta': 3},
        dueDays: 30,
      );

      expect(find.bySemanticsLabel('7 cards for today'), findsOneWidget);
      // Seven cards at 10 s each, about 2 minutes.
      expect(find.text('7 to review · 0 new · about 2 min'), findsOneWidget);
      expect(find.text(paused), findsOneWidget);
      await list.close();

      // Control: the same reviews after one-day intervals are within three
      // days' load, so the header takes the new card and has no such
      // sentence.
      list = await _open(
        tester,
        fresh: {'Gamma': 1},
        due: {'Alpha': 4, 'Beta': 3},
      );

      expect(find.text('7 to review · 1 new · about 2 min'), findsOneWidget);
      expect(find.text(paused), findsNothing);
      await list.close();
    },
  );

  testWidgets(
    'with nothing to study the today card says it is done, and Keep studying opens a session over every deck',
    (tester) async {
      var list = await _open(tester, later: {'Alpha': 1});

      expect(find.text("You've done today's cards"), findsOneWidget);
      expect(find.text('Study all'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('for today')), findsNothing);
      await list.tap('Keep studying');
      expect(list.session, list.ids.values.toSet());
      await list.close();

      // Control: one card to study shows the count and Study all.
      list = await _open(tester, due: {'Alpha': 1});
      expect(find.text("You've done today's cards"), findsNothing);
      expect(find.text('Keep studying'), findsNothing);
      expect(find.text('Study all'), findsOneWidget);
      await list.close();
    },
  );

  testWidgets('a header count that cannot be read says why', (tester) async {
    final list = await _open(tester, unreadable: {'Beta'});

    expect(
      find.text(
        "Couldn't read or write the device's storage. Please try again.",
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('for today')), findsNothing);
    await list.close();
  });

  testWidgets('the photo button is absent until photo import exists', (
    tester,
  ) async {
    final list = await _open(tester);

    expect(find.text('New deck'), findsOneWidget);
    expect(find.text('Create from photo'), findsNothing);
    await list.close();
  });

  testWidgets('with photo import, the photo button opens it for a new deck', (
    tester,
  ) async {
    final opened = <DeckId?>[];
    final list = await _open(
      tester,
      photoImport: (deck) {
        opened.add(deck);
        return const Scaffold(body: Text('photo import'));
      },
    );

    await list.tap('Create from photo');

    expect(find.text('photo import'), findsOneWidget);
    expect(opened, [null]);
    await list.close();
  });

  testWidgets('a photo import that saved returns to the deck it saved into', (
    tester,
  ) async {
    final list = await _open(
      tester,
      photoImport: (_) => Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).pop(
              Deck(
                id: const DeckId('deck1'),
                name: 'Beta',
                createdAt: DateTime.utc(2026, 10, 15),
                updatedAt: DateTime.utc(2026, 10, 15),
              ),
            ),
            child: const Text('saved'),
          ),
        ),
      ),
    );
    expect(list.ids['Beta'], const DeckId('deck1'));

    await list.tap('Create from photo');
    await list.tap('saved');

    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Add card'), findsOneWidget);
    await list.close();
  });

  testWidgets('a photo import left without saving returns to the deck list', (
    tester,
  ) async {
    final list = await _open(
      tester,
      photoImport: (_) => Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('left'),
          ),
        ),
      ),
    );

    await list.tap('Create from photo');
    await list.tap('left');

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Add card'), findsNothing);
    await list.close();
  });

  testWidgets('a long-press enters selection mode with that deck selected', (
    tester,
  ) async {
    final list = await _open(tester);
    expect(find.bySemanticsLabel('smartman'), findsOneWidget);
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
      expect(find.text('No cards yet. Add a card to start.'), findsOneWidget);
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
      expect(find.text('No cards yet. Add a card to start.'), findsNothing);
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

    expect(list.session, {list.ids['Alpha'], list.ids['Gamma']});
    await list.close();
  });

  testWidgets('the clear action leaves selection mode', (tester) async {
    final list = await _open(tester);
    await list.longPress('Alpha');

    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('smartman'), findsOneWidget);
    expect(find.textContaining('selected'), findsNothing);
    await list.tap('Alpha');
    expect(find.text('No cards yet. Add a card to start.'), findsOneWidget);
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

  testWidgets(
    'a screen reader hears whether each deck is selected and how many are',
    (tester) async {
      final list = await _open(tester);
      await list.longPress('Alpha');

      expect(
        tester.getSemantics(list.row('Alpha')),
        isSemantics(
          label: 'Alpha\n0 cards',
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(list.row('Beta')),
        isSemantics(
          label: 'Beta\n0 cards',
          hasSelectedState: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
      expect(find.semantics.byLabel('1 selected'), findsOne);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await list.close();
    },
  );
}
