import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/design/app_button.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/home/src/deck_screen.dart';
import 'package:smartman/home/src/home_screen.dart';
import 'package:smartman/l10n/app_localizations.dart';
import 'package:smartman/photo_import/photo_import.dart';
import 'package:smartman/study/study.dart';

import 'home_data.dart';
import '../study/minutes_sheet.dart';
import '../study/study_storage.dart';

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

  /// The daily study minutes stored, null while none is.
  Future<int?> storedMinutes() async => (await tester.runAsync<int?>(
    () =>
        ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
            .read(studyRepositoryProvider)
            .dailyMinutes(),
  ));

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
/// whose cards cannot be read. The first-run daily minutes step has shown
/// unless [minutesAsked] is false. The screen is a phone's unless [screen]
/// says otherwise, in the light theme unless [theme] is another, with
/// [dailyMinutes] stored when given. [photoImport] stands in for the photo import
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
  Widget Function(DeckId? deck, PhotoOrigin origin)? photoImport,
  List<String> decks = const ['Alpha', 'Beta', 'Gamma'],
  bool minutesAsked = true,
  Locale locale = const Locale('en'),
  Size screen = const Size(390, 844),
  ThemeData? theme,
  int? dailyMinutes,
}) async {
  Future<Deck?> pushed(
    BuildContext context,
    DeckId? deck,
    PhotoOrigin origin,
  ) => Navigator.of(
    context,
  ).push(MaterialPageRoute<Deck>(builder: (_) => photoImport!(deck, origin)));
  // A phone's screen, so the 오늘 tab's decks are on it.
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  // Tear-downs run last first, so the screen is unmounted before the
  // database closes, even when a test fails before its own close(): closing
  // under a mounted screen leaves its stream queries waiting, and the run
  // hangs until the test times out.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
  var ids = 0;
  final repository = UnreadableDecks(
    db,
    clock: () => DateTime.utc(2026, 10, 15),
    newId: () => 'deck${ids++}',
  );
  final created = (await tester.runAsync(() async {
    if (dailyMinutes != null) {
      await StudyRepository(
        db,
        newId: () => 'setting',
      ).setDailyMinutes(dailyMinutes, at: homeNow);
    }
    final created = {
      for (final name in decks) name: (await repository.createDeck(name)).id,
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
  final storage = await openStudyStorage(tester, minutesAsked: minutesAsked);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deckRepositoryProvider.overrideWithValue(repository),
        ...homeOverrides(db, storage: storage),
        if (photoImport != null) photoImportProvider.overrideWithValue(pushed),
      ],
      child: MaterialApp(
        theme: theme ?? lightTheme,
        locale: locale,
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
      'with one deck and no card, it shows how to start, adding a card to the deck as its one primary, not a finished day',
      (tester) async {
        final list = await _open(tester, decks: ['Alpha']);

        expect(find.text('Make your first card?'), findsOneWidget);
        expect(find.text('Add cards to a deck to start'), findsOneWidget);
        expect(find.text("You've done today's cards"), findsNothing);
        AppButton button(String label) =>
            tester.widget<AppButton>(find.widgetWithText(AppButton, label));
        expect(button('Add card').variant, AppButtonVariant.primary);
        expect(button('Open deck').variant, AppButtonVariant.text);

        // "Add card" opens the deck and its card editor.
        await list.tap('Add card');
        expect(find.byType(CardEditorScreen), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(DeckScreen), findsOneWidget);
        await list.close();
      },
    );

    testWidgets(
      'with several decks and no card, its one primary shows the 덱 tab',
      (tester) async {
        final list = await _open(tester);

        expect(find.text('Make your first card?'), findsOneWidget);
        await list.tap('Add cards in a deck');
        expect(find.text('My decks 3'), findsOneWidget);
        await list.close();
      },
    );

    testWidgets('with a card in any deck, it shows the day, not how to start', (
      tester,
    ) async {
      final list = await _open(tester, decks: ['Alpha'], fresh: {'Alpha': 1});

      expect(find.text('Make your first card?'), findsNothing);
      expect(find.text('Study all'), findsOneWidget);
      await list.close();
    });

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
      'cards studied past the day\'s plan leave the done card and its goal as planned, and show apart as more cards today',
      (tester) async {
        // 5 minutes at the unknown pace of 10 s: 30 new cards a day, so the
        // 35 first answered today are 30 planned and 5 past the plan.
        final list = await _open(
          tester,
          decks: ['Alpha'],
          answeredToday: {'Alpha': 35},
          dailyMinutes: 5,
        );

        expect(find.text("You've done today's cards"), findsOneWidget);
        expect(find.text('Goal of 30 reached'), findsOneWidget);
        expect(find.text('5 more cards today'), findsOneWidget);
        await list.close();
      },
    );

    testWidgets(
      'control: within the day\'s plan, no card is shown as more today',
      (tester) async {
        final list = await _open(
          tester,
          decks: ['Alpha'],
          answeredToday: {'Alpha': 30},
          dailyMinutes: 5,
        );

        expect(find.text('Goal of 30 reached'), findsOneWidget);
        expect(find.textContaining('more card'), findsNothing);
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

        // Centred, so the tab bar does not cover it.
        unawaited(
          Scrollable.ensureVisible(
            tester.element(find.bySemanticsLabel('Study Alpha, 2 today')),
            alignment: 0.5,
          ),
        );
        await tester.pumpAndSettle();
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
        // A card due in ten days: nothing this week.
        final list = await _open(tester, mastered: {'Alpha': 1});

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
      final list = await _open(
        tester,
        mastered: {'Alpha': 1},
        unreadable: {'Beta'},
      );

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

  group('daily study minutes', () {
    testWidgets(
      'the today card shows them as a control read as the time and a change, which opens the sheet',
      (tester) async {
        final list = await _open(tester, fresh: {'Alpha': 3});

        expect(find.text('20 min a day'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Daily study time 20 minutes, change'),
          findsOneWidget,
        );
        await tester.tap(
          find.bySemanticsLabel('Daily study time 20 minutes, change'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.text('Daily study time'), findsOneWidget);
        await list.close();
      },
    );

    testWidgets('in Korean the control reads 하루 20분, as 하루 공부 시간 20분, 바꾸기', (
      tester,
    ) async {
      final list = await _open(
        tester,
        fresh: {'Alpha': 3},
        locale: const Locale('ko'),
      );

      expect(find.text('하루 20분'), findsOneWidget);
      expect(find.bySemanticsLabel('하루 공부 시간 20분, 바꾸기'), findsOneWidget);
      await list.close();
    });

    testWidgets(
      'the sheet previews today\'s new cards and reviews and the day the last new card starts, following the choice, and saving updates today\'s count at once',
      (tester) async {
        final list = await _open(
          tester,
          decks: ['Alpha'],
          fresh: {'Alpha': 150},
          // Wide enough for the forecast's three-figure week in the test font.
          screen: const Size(800, 844),
        );
        // 20 minutes at the unknown pace of 10 s: 120 new cards.
        expect(find.bySemanticsLabel('120 cards for today'), findsOneWidget);
        await tester.tap(find.text('20 min a day'));
        await waitForChoices(tester);

        expect(
          tester.getSemantics(find.text('20 min').last),
          isSemantics(isSelected: true, hasSelectedState: true),
        );
        expect(
          find.text('About 120 new cards today · 0 reviews'),
          findsOneWidget,
        );
        // 120 today, the other 30 tomorrow.
        expect(
          find.text(
            'At this pace you start the 150 new cards left by about Oct 16',
          ),
          findsOneWidget,
        );

        await tester.tap(find.text('10 min'));
        await tester.pumpAndSettle();
        expect(
          find.text('About 60 new cards today · 0 reviews'),
          findsOneWidget,
        );
        // 60 today, 60 tomorrow and 30 the day after.
        expect(
          find.text(
            'At this pace you start the 150 new cards left by about Oct 17',
          ),
          findsOneWidget,
        );
        // Nothing is stored until Save.
        expect(await list.storedMinutes(), isNull);

        await tester.tap(find.text('Custom'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('5 minutes less'));
        await tester.pumpAndSettle();
        expect(find.text('Custom · 5 min'), findsOneWidget);
        expect(
          find.text('About 30 new cards today · 0 reviews'),
          findsOneWidget,
        );
        // Five is the floor.
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, LucideIcons.minus),
              )
              .onPressed,
          isNull,
        );

        await list.tap('Save');

        expect(find.byType(BottomSheet), findsNothing);
        expect(await list.storedMinutes(), 5);
        expect(find.bySemanticsLabel('30 cards for today'), findsOneWidget);
        expect(find.text('5 min a day'), findsOneWidget);
        await list.close();
      },
    );

    testWidgets(
      'once a deck has cards, the sheet shows once as a first-run step whose Skip keeps the default',
      (tester) async {
        final list = await _open(
          tester,
          decks: ['Alpha'],
          fresh: {'Alpha': 3},
          minutesAsked: false,
        );

        expect(
          find.text('How many minutes a day will you study?'),
          findsOneWidget,
        );
        await waitForChoices(tester);
        await list.tap('Skip');
        expect(find.byType(BottomSheet), findsNothing);
        expect(await list.storedMinutes(), isNull);
        expect(find.text('20 min a day'), findsOneWidget);

        // Shown once: back on the tab, it does not show again.
        await list.decks();
        await list.tap('Today');
        expect(find.byType(BottomSheet), findsNothing);
        await list.close();
      },
    );

    for (final (name, theme) in [('light', lightTheme), ('dark', darkTheme)]) {
      testWidgets(
        'in the $name theme the control, the sheet and its custom steps meet the tap target and contrast guidelines',
        (tester) async {
          Future<void> meetsGuidelines() async {
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(tester, meetsGuideline(textContrastGuideline));
          }

          final list = await _open(tester, fresh: {'Alpha': 3}, theme: theme);
          await meetsGuidelines();
          await tester.tap(find.text('20 min a day'));
          await waitForChoices(tester);
          await meetsGuidelines();
          await list.tap('Custom');
          await meetsGuidelines();
          await list.close();
        },
      );
    }

    testWidgets('without a card the first-run step waits', (tester) async {
      final list = await _open(tester, decks: ['Alpha'], minutesAsked: false);

      expect(find.text('Make your first card?'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      await list.close();
    });

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
        expect(find.text('Take photo'), findsNothing);
        expect(find.text('Choose from album'), findsNothing);
        await list.tap('Create by hand');
        // The name sheet is "New deck", as photo import's is.
        expect(find.text('New deck'), findsOneWidget);
        await tester.enterText(find.byType(EditableText).last, 'Delta');
        await list.tap('Create');

        // The new deck opens, as a photo import's deck does.
        expect(find.byType(DeckScreen), findsOneWidget);
        expect(find.text('Delta'), findsOneWidget);
        expect(find.text('No cards yet. Add a card to start.'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('My decks 4'), findsOneWidget);
        expect(find.text('Delta'), findsOneWidget);
        await list.close();
      },
    );

    testWidgets(
      'with photo import, Create a deck offers the camera and the album in the same sheet, each opening photo import for a new deck from its source',
      (tester) async {
        final opened = <(DeckId?, PhotoOrigin)>[];
        final list = await _open(
          tester,
          photoImport: (deck, origin) {
            opened.add((deck, origin));
            return Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('photo import'),
                ),
              ),
            );
          },
        );
        await list.decks();

        for (final row in ['Take photo', 'Choose from album']) {
          await list.newDeck();
          expect(find.text('Create by hand'), findsOneWidget);
          await list.tap(row);
          expect(find.text('photo import'), findsOneWidget);
          await list.tap('photo import');
        }
        expect(opened, [(null, PhotoOrigin.camera), (null, PhotoOrigin.album)]);
        await list.close();
      },
    );

    testWidgets('a photo import that saved returns to the deck it saved into', (
      tester,
    ) async {
      final list = await _open(
        tester,
        photoImport: (_, _) => Builder(
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
      await list.tap('Take photo');
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
        photoImport: (_, _) => Builder(
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
      await list.tap('Take photo');
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
