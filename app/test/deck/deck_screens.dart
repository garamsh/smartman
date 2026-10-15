import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/shared/database.dart';
import 'package:smartman/shared/l10n/app_localizations.dart';
import 'package:smartman/shared/theme.dart';
import 'package:smartman/shared/ui/app_text_field.dart';

/// A deck named "French" in an in-memory database, shown by the deck screens
/// with stand-ins for what the composition site provides.
class DeckScreens {
  DeckScreens._(this.tester, this.repository, this.deck, this.navigator);

  final WidgetTester tester;
  final DeckRepository repository;
  final Deck deck;
  final GlobalKey<NavigatorState> navigator;

  /// The decks of every study session opened.
  final sessions = <Set<DeckId>>[];

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
  /// front to back. [today] is every today count; [photoImport] enables the
  /// photo buttons.
  static Future<DeckScreens> open(
    WidgetTester tester, {
    Map<String, String> cards = const {},
    TodayCount today = const TodayCounted(review: 0, fresh: 0),
    bool photoImport = false,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var ids = 0;
    var tick = 0;
    final repository = DeckRepository(
      db,
      clock: () => DateTime.utc(2026, 10, 15).add(Duration(seconds: tick++)),
      newId: () => 'id${ids++}',
    );
    final deck = (await tester.runAsync(() async {
      final deck = await repository.createDeck('French');
      for (final MapEntry(key: front, value: back) in cards.entries) {
        await repository.addCard(
          deck.id,
          front: [TextContent(front)],
          back: [TextContent(back)],
        );
      }
      return deck;
    }))!;
    final screens = DeckScreens._(
      tester,
      repository,
      deck,
      GlobalKey<NavigatorState>(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deckRepositoryProvider.overrideWithValue(repository),
          studyScreenProvider.overrideWithValue((decks) {
            screens.sessions.add(decks.ids);
            return const Scaffold(body: Text('session'));
          }),
          todayProvider.overrideWithValue(
            (decks, builder) =>
                Builder(builder: (context) => builder(context, today)),
          ),
          if (photoImport)
            photoImportProvider.overrideWithValue((deck) {
              screens.photoImports.add(deck);
              return const Scaffold(body: Text('photo import'));
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
