import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/design/app_text_field.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/l10n/app_localizations.dart';
import 'package:smartman/photo_import/photo_import.dart';
import 'package:smartman/study/study.dart';

import 'home_data.dart';
import '../study/study_storage.dart';

/// A deck named "French" in an in-memory database, shown by the deck screens
/// with study over the same database and a stand-in for photo import.
class DeckScreens {
  DeckScreens._(this.tester, this.repository, this.deck, this.navigator);

  final WidgetTester tester;
  final DeckRepository repository;
  final Deck deck;
  final GlobalKey<NavigatorState> navigator;

  /// The decks of the study session open on top.
  Set<DeckId> get session =>
      tester.widget<StudyScreen>(find.byType(StudyScreen)).decks.ids;

  /// The deck of every photo import opened.
  final photoImports = <DeckId?>[];

  /// The deck's cards as stored.
  Future<List<Card>> cards() async =>
      (await tester.runAsync(() => repository.listCards(deck.id)))!;

  /// Pushes the screen [build] makes over the empty home route.
  Future<void> push(Widget Function(Deck deck) build) async {
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => build(deck)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Types [text] into the field labelled [label].
  Future<void> enter(String label, String text) async {
    await tester.enterText(find.widgetWithText(AppTextField, label), text);
    await tester.pump();
  }

  /// Unmounts the screens. Unmounting cancels drift's stream queries, whose
  /// cleanup timer must fire before the test body ends.
  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  /// Opens the screens over the deck holding a card for each of [cards],
  /// front to back. The cards whose fronts are in [due] fall due today after
  /// an interval of [dueDays] days, those in [later] tomorrow, and the rest
  /// are new. [unreadable] makes the deck's cards unreadable to the count, and
  /// [stalled] holds the count unread; [photoImport] enables the photo
  /// buttons.
  static Future<DeckScreens> open(
    WidgetTester tester, {
    Map<String, String> cards = const {},
    Set<String> due = const {},
    int dueDays = 1,
    Set<String> later = const {},
    bool unreadable = false,
    bool stalled = false,
    bool photoImport = false,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    // A phone's screen, so every card of a short deck is on it under the
    // pinned row.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var ids = 0;
    var tick = 0;
    final repository = UnreadableDecks(
      db,
      clock: () => DateTime.utc(2026, 10, 15).add(Duration(seconds: tick++)),
      newId: () => 'id${ids++}',
    );
    final deck = (await tester.runAsync(() async {
      final deck = await repository.createDeck('French');
      for (final MapEntry(key: front, value: back) in cards.entries) {
        final saved = await repository.addCard(
          deck.id,
          front: [TextContent(front)],
          back: [TextContent(back)],
        );
        final card = switch (saved) {
          CardSaved(:final card) => card.id,
          DuplicateFront() => fail('the deck held no duplicate'),
        };
        if (due.contains(front)) {
          await storeState(db, card, due: homeNow, days: dueDays);
        } else if (later.contains(front)) {
          await storeState(db, card, due: homeNow.add(const Duration(days: 1)));
        }
      }
      return deck;
    }))!;
    if (unreadable) repository.unreadable.add(deck.id);
    final screens = DeckScreens._(
      tester,
      repository,
      deck,
      GlobalKey<NavigatorState>(),
    );
    final storage = await openStudyStorage(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deckRepositoryProvider.overrideWithValue(repository),
          ...homeOverrides(db, storage: storage, stalled: stalled),
          if (photoImport)
            photoImportProvider.overrideWithValue((context, deck) {
              screens.photoImports.add(deck);
              return Navigator.of(context).push(
                MaterialPageRoute<Deck>(
                  builder: (_) => const Scaffold(body: Text('photo import')),
                ),
              );
            }),
        ],
        child: MaterialApp(
          navigatorKey: screens.navigator,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeMode,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return screens;
  }
}
