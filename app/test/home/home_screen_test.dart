import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/home/src/deck_screen.dart';
import 'package:smartman/home/src/home_screen.dart';
import 'package:smartman/l10n/app_localizations.dart';
import 'package:smartman/photo_import/photo_import.dart';
import 'package:smartman/study/study.dart';

import 'home_data.dart';

/// The home screen over decks named "Alpha", "Beta" and "Gamma", opening on
/// the 오늘 tab.
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

  Future<void> tap(String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  /// Shows the decks tab.
  Future<void> decks() => tap('Decks');

  /// Taps "새 덱 만들기" under the deck rows, which opens the new-deck sheet.
  Future<void> newDeck() async {
    await tester.ensureVisible(find.text('Create a deck'));
    await tap('Create a deck');
  }

  /// The row showing [deck].
  Finder row(String deck) =>
      find.ancestor(of: find.text(deck), matching: find.byType(InkWell)).first;

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
/// of [dueDays] days, in each named in [later] that many due tomorrow, and in
/// each named in [answeredToday] that many answered an hour before [homeNow]
/// and due tomorrow, and in each named in [mastered] that many reviewed after
/// a 30-day interval and due in ten days.
/// [pace] is the time the user's answers took; [unreadable] names the decks
/// whose cards cannot be read. [photoImport] stands in for the photo import
/// when given: a screen it pushes, which pops with what photo import resolves
/// to.
Future<_List> _open(
  WidgetTester tester, {
  Map<String, int> fresh = const {},
  Map<String, int> due = const {},
  int dueDays = 1,
  Map<String, int> later = const {},
  Map<String, int> answeredToday = const {},
  Map<String, int> mastered = const {},
  Duration? pace,
  Set<String> unreadable = const {},
  Widget Function(DeckId? deck)? photoImport,
}) async {
  Future<Deck?> pushed(BuildContext context, DeckId? deck) =>
      Navigator.of(context)
          .push(MaterialPageRoute<Deck>(builder: (_) => photoImport!(deck)));
  // A phone's screen, so the 오늘 tab's decks are on it.
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
    for (final MapEntry(key: name, value: count) in answeredToday.entries) {
      for (var i = 0; i < count; i++) {
        final card = await add(name, '$name answered $i');
        await storeState(db, card, due: homeNow.add(const Duration(days: 1)));
        await storeAnswerAt(
          db,
          card,
          homeNow.subtract(const Duration(hours: 1)),
        );
      }
    }
    for (final MapEntry(key: name, value: count) in mastered.entries) {
      for (var i = 0; i < count; i++) {
        final card = await add(name, '$name mastered $i');
        await storeState(
          db,
          card,
          due: homeNow.add(const Duration(days: 10)),
          days: 30,
        );
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
        if (photoImport != null) photoImportProvider.overrideWithValue(pushed),
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

  group('tabs', () {
    testWidgets(
      'opens on 오늘, the bar switches tabs, and back from another tab returns to 오늘',
      (tester) async {
        final list = await _open(tester, fresh: {'Alpha': 1});
        expect(find.text('Next 7 days'), findsOneWidget);
        expect(
          tester.getSemantics(find.text('Today').last),
          isSemantics(isSelected: true, hasSelectedState: true),
        );

        await list.decks();
        expect(find.text('My decks 3'), findsOneWidget);
        expect(find.text('Next 7 days'), findsNothing);
        await list.tap('Record');
        expect(find.text('Correct in reviews'), findsOneWidget);

        expect(await tester.binding.handlePopRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('Next 7 days'), findsOneWidget);
        // Control: back on 오늘 is left to the platform, which leaves the app.
        expect(await tester.binding.handlePopRoute(), isFalse);
        await list.close();
      },
    );
  });

  group('기록', () {
    testWidgets(
      'the tab is built once first shown, and shows study\'s record over every deck',
      (tester) async {
        final list = await _open(
          tester,
          fresh: {'Alpha': 1},
          due: {'Alpha': 1, 'Beta': 2},
        );
        expect(
          find.text('Chance you remember now', skipOffstage: false),
          findsNothing,
        );

        await list.tap('Record');
        // Every deck's stored state, each recalled at the substituted 0.9.
        expect(
          find.bySemanticsLabel(
            'Of 3 cards: solid 0, fair 3, fading soon 0, average 90%',
          ),
          findsOneWidget,
        );
        expect(homeRecall, 0.9);
        await list.close();
      },
    );
  });

  group('오늘', () {
    testWidgets(
      'the today card counts every deck with its minutes, the goal ring, the streak, and Study all studies every deck',
      (tester) async {
        final list = await _open(
          tester,
          fresh: {'Alpha': 2, 'Gamma': 1},
          due: {'Alpha': 1, 'Beta': 3},
          pace: const Duration(seconds: 25),
        );

        expect(find.bySemanticsLabel('7 cards for today'), findsOneWidget);
        // Seven cards at 25 s each take 175 s, about 3 minutes.
        expect(find.text('7 cards · about 3 min'), findsOneWidget);
        expect(find.bySemanticsLabel("0 of today's goal of 7"), findsOneWidget);
        // Nothing done yet, on a 1-day streak: the line waits, and the
        // numbers stay in the ring alone.
        expect(_shown("Waiting for today's first card"), findsOneWidget);
        expect(find.textContaining("of today's 7"), findsNothing);
        // The pace's answers were given the day before, which starts the
        // streak.
        expect(find.text('1-day streak'), findsOneWidget);

        await list.tap('Study all');

        expect(list.session, list.ids.values.toSet());
        await list.close();
      },
    );

    testWidgets(
      "the goal counts the cards answered today as done, beside those left",
      (tester) async {
        final list = await _open(
          tester,
          fresh: {'Alpha': 2},
          answeredToday: {'Beta': 1},
        );

        expect(find.bySemanticsLabel("1 of today's goal of 3"), findsOneWidget);
        // Two cards left: almost there.
        expect(_shown('Almost there'), findsOneWidget);
        // Answered today: the streak counts today.
        expect(find.text('1-day streak'), findsOneWidget);
        await list.close();
      },
    );

    testWidgets(
      'the next seven days show today\'s load and the cards due on each later day',
      (tester) async {
        final list = await _open(
          tester,
          fresh: {'Alpha': 2},
          due: {'Beta': 1},
          later: {'Gamma': 2},
        );

        // homeNow is Thursday 15 October 2026.
        expect(
          find.bySemanticsLabel(
            'Today 3, Tomorrow 2, Sat 0, Sun 0, Mon 0, Tue 0, Wed 0',
          ),
          findsOneWidget,
        );
        expect(find.text('Tomorrow 2 · This week 5'), findsOneWidget);
        await list.close();
      },
    );

    testWidgets(
      "today's decks are those with cards left, and a row studies its deck",
      (tester) async {
        final list = await _open(
          tester,
          fresh: {'Alpha': 2},
          later: {'Beta': 1},
        );

        expect(find.text("Today's decks"), findsOneWidget);
        expect(find.bySemanticsLabel('Study Alpha, 2 today'), findsOneWidget);
        // Control: a deck with nothing left today has no row.
        expect(find.bySemanticsLabel(RegExp('^Study Beta')), findsNothing);

        await tester.tap(find.bySemanticsLabel('Study Alpha, 2 today'));
        await tester.pumpAndSettle();

        expect(list.session, {list.ids['Alpha']});
        await list.close();
      },
    );

    testWidgets(
      'once today\'s cards are done the done card names the next review and the goal reached, and Study studies every deck',
      (tester) async {
        final list = await _open(tester, answeredToday: {'Alpha': 2});

        expect(find.text("You've done today's cards"), findsOneWidget);
        expect(find.text('Study all'), findsNothing);
        expect(find.bySemanticsLabel(RegExp('for today')), findsNothing);
        expect(
          find.text('Next review Tomorrow · 2, about 1 min'),
          findsOneWidget,
        );
        expect(find.text('Goal of 2 reached'), findsOneWidget);
        expect(find.text('1-day streak'), findsOneWidget);
        expect(find.text('This week 2'), findsOneWidget);

        await list.tap('Study');

        expect(list.session, list.ids.values.toSet());
        await list.close();
      },
    );

    testWidgets(
      'a done day with nothing answered and nothing due this week reaches no goal and has no next review',
      (tester) async {
        final list = await _open(tester);

        expect(find.text("You've done today's cards"), findsOneWidget);
        expect(find.text('No reviews in the next 7 days'), findsOneWidget);
        expect(find.textContaining('reached'), findsNothing);
        expect(find.textContaining('streak'), findsNothing);
        await list.close();
      },
    );

    testWidgets(
      'in a backlog the backlog card counts the overdue reviews, says new cards wait, and studies every deck, and not otherwise',
      (tester) async {
        const title = 'Pick up where you left off';
        // Seven reviews due after 30-day intervals are far more than three
        // days' load, so the new card waits.
        var list = await _open(
          tester,
          fresh: {'Gamma': 1},
          due: {'Alpha': 4, 'Beta': 3},
          dueDays: 30,
        );

        expect(find.text(title), findsOneWidget);
        expect(
          find.text(
            '7 overdue reviews, most urgent first. New cards wait for now.',
          ),
          findsOneWidget,
        );
        expect(find.text('Study all'), findsNothing);
        // Seven reviews after 30-day intervals ask for a quarter of a card
        // a day, so the catch-up runs at one a day.
        expect(find.text('At 1 a day you catch up in 7 days'), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            'Overdue reviews expected: Today 7, Tomorrow 6, Sat 5, Sun 4, '
            'Mon 3, Tue 2, Wed 1',
          ),
          findsOneWidget,
        );
        expect(
          find.text('The overdue reviews left at 1 a day'),
          findsOneWidget,
        );
        // Seven cards at 10 s each, about 2 minutes.
        await list.tap('Study 7 · about 2 min');
        expect(list.session, list.ids.values.toSet());
        await list.close();

        // Control: the same reviews after one-day intervals are within three
        // days' load, so the today card takes the new card.
        list = await _open(
          tester,
          fresh: {'Gamma': 1},
          due: {'Alpha': 4, 'Beta': 3},
        );

        expect(find.bySemanticsLabel('8 cards for today'), findsOneWidget);
        expect(find.text(title), findsNothing);
        await list.close();
      },
    );

    testWidgets('a count that cannot be read says why', (tester) async {
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
  });

  group('덱', () {
    testWidgets(
      "each row shows its deck's name, its progress and a today chip only when it has cards for today",
      (tester) async {
        const unreadable =
            "Couldn't read or write the device's storage. Please try again.";
        final list = await _open(
          tester,
          fresh: {'Alpha': 2},
          mastered: {'Alpha': 1},
          later: {'Beta': 1},
          unreadable: {'Gamma'},
        );
        await list.decks();

        Finder inRow(String deck, Finder finder) =>
            find.descendant(of: list.row(deck), matching: finder);
        expect(inRow('Alpha', find.text('1 of 3 mastered')), findsOneWidget);
        expect(inRow('Alpha', find.text('Today 2')), findsOneWidget);
        expect(
          tester.getSemantics(list.row('Alpha')),
          isSemantics(label: 'Alpha\nToday 2\n1 of 3 mastered'),
        );
        expect(inRow('Beta', find.text('0 of 1 mastered')), findsOneWidget);
        expect(inRow('Beta', find.textContaining('Today')), findsNothing);
        // A deck whose cards cannot be read shows why, and its card count.
        expect(inRow('Gamma', find.text('0 cards')), findsOneWidget);
        expect(inRow('Gamma', find.byTooltip(unreadable)), findsOneWidget);
        expect(find.text('My decks 3'), findsOneWidget);
        expect(find.textContaining('Long-press'), findsNothing);
        await list.close();
      },
    );

    testWidgets(
      'the search keeps the decks whose name holds it, ignoring case',
      (tester) async {
        final list = await _open(tester);
        await list.decks();

        await tester.enterText(find.byType(EditableText), 'ALP');
        await tester.pumpAndSettle();
        expect(find.text('Alpha'), findsOneWidget);
        expect(find.text('Beta'), findsNothing);

        await tester.enterText(find.byType(EditableText), 'zebra');
        await tester.pumpAndSettle();
        expect(find.text('No deck matches. Try other words.'), findsOneWidget);
        await list.close();
      },
    );

    testWidgets(
      'Create a deck under the rows opens the new-deck sheet, which makes one by hand, and offers no photo without photo import',
      (tester) async {
        final list = await _open(tester);
        await list.decks();

        await list.newDeck();
        // The sheet's title over the entry that opened it.
        expect(find.text('Create a deck'), findsNWidgets(2));
        expect(find.text('Create by hand'), findsOneWidget);
        expect(find.text('Create from photo'), findsNothing);
        await list.tap('Create by hand');
        await tester.enterText(find.byType(EditableText).last, 'Delta');
        await list.tap('Create');

        expect(find.text('My decks 4'), findsOneWidget);
        expect(find.text('Delta'), findsOneWidget);
        await list.close();
      },
    );

    testWidgets(
      'with photo import, Create a deck offers a photo, which opens it for a new deck',
      (tester) async {
        final opened = <DeckId?>[];
        final list = await _open(
          tester,
          photoImport: (deck) {
            opened.add(deck);
            return const Scaffold(body: Text('photo import'));
          },
        );
        await list.decks();

        await list.newDeck();
        await list.tap('Create from photo');

        expect(find.text('photo import'), findsOneWidget);
        expect(opened, [null]);
        await list.close();
      },
    );

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
      await list.decks();

      await list.newDeck();
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
      await list.decks();

      await list.newDeck();
      await list.tap('Create from photo');
      await list.tap('left');

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('My decks 3'), findsOneWidget);
      await list.close();
    });

    testWidgets(
      'the top bar holds the title alone, a long-press opens a deck as a tap does, and Create a deck sits under the rows',
      (tester) async {
        final list = await _open(tester);
        await list.decks();

        final bar = find.byType(AppBar);
        expect(
          find.descendant(of: bar, matching: find.text('My decks 3')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: bar, matching: find.byType(ButtonStyleButton)),
          findsNothing,
        );
        expect(find.text('Select'), findsNothing);
        expect(find.text('New deck'), findsNothing);

        // With no selection mode, a long-press opens the deck as a tap does.
        await tester.longPress(find.text('Beta'));
        await tester.pumpAndSettle();
        expect(find.byType(DeckScreen), findsOneWidget);
        expect(find.textContaining('selected'), findsNothing);
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Create a deck'));
        expect(
          tester.getRect(find.text('Create a deck')).top,
          greaterThan(tester.getRect(find.text('Gamma')).bottom),
        );
        // Control: without sharing there is no way to public decks beside it.
        expect(find.text('Browse public decks'), findsNothing);
        await list.close();
      },
    );
  });
}

/// The text on screen that reads [text] once its word joiners are left out.
Finder _shown(String text) => find.byWidgetPredicate(
  (widget) => widget is Text && widget.data?.replaceAll('\u2060', '') == text,
);
