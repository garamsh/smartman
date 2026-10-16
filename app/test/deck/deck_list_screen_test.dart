import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/l10n/app_localizations.dart';

/// A deck list over decks named "Alpha", "Beta" and "Gamma", whose study
/// screen and today counts record the decks they were given.
class _List {
  _List(this.tester, this.repository, this.ids)
    : _semantics = tester.ensureSemantics();

  final WidgetTester tester;
  final SemanticsHandle _semantics;
  final DeckRepository repository;

  /// Each deck's id by name.
  final Map<String, DeckId> ids;

  /// The decks of every study session opened.
  final sessions = <Set<DeckId>>[];

  /// Every selection a today count was built for.
  final counted = <Set<DeckId>>[];

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

/// Opens the deck list. [today] gives the count of a selection by the names
/// of its decks, joined by "+"; a selection it leaves out counts nothing.
/// [photoImport] stands in for the photo import screen when given.
Future<_List> _open(
  WidgetTester tester, {
  Map<String, TodayCount> today = const {},
  Widget Function(DeckId? deck)? photoImport,
  Map<String, int> cards = const {},
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  var ids = 0;
  final repository = DeckRepository(
    db,
    clock: () => DateTime.utc(2026, 10, 15),
    newId: () => 'deck${ids++}',
  );
  final created = (await tester.runAsync(() async {
    final created = {
      for (final name in ['Alpha', 'Beta', 'Gamma'])
        name: (await repository.createDeck(name)).id,
    };
    for (final MapEntry(key: name, value: count) in cards.entries) {
      for (var i = 0; i < count; i++) {
        await repository.addCard(
          created[name]!,
          front: [TextContent('$name $i')],
          back: [TextContent('$i')],
        );
      }
    }
    return created;
  }))!;
  final list = _List(tester, repository, created);
  final names = {
    for (final MapEntry(:key, :value) in created.entries) value: key,
  };
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deckRepositoryProvider.overrideWithValue(repository),
        studyScreenProvider.overrideWithValue((decks) {
          list.sessions.add(decks.ids);
          return const Scaffold(body: Text('session'));
        }),
        todayProvider.overrideWithValue((decks, builder) {
          list.counted.add(decks.ids);
          final key = ([
            for (final id in decks.ids) names[id]!,
          ]..sort()).join('+');
          return Builder(
            builder: (context) => builder(
              context,
              today[key] ?? const TodayCounted(review: 0, fresh: 0),
            ),
          );
        }),
        accountScreenProvider.overrideWithValue(Scaffold.new),
        accountAvatarProvider.overrideWithValue(
          () => const SizedBox.square(dimension: 32),
        ),
        if (photoImport != null)
          photoImportProvider.overrideWithValue(photoImport),
      ],
      child: MaterialApp(
        theme: lightTheme,
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

  testWidgets(
    'each row shows its deck name, card count and chevron, and a today chip only when the deck has cards for today',
    (tester) async {
      final list = await _open(
        tester,
        cards: {'Alpha': 2, 'Beta': 1},
        today: {
          'Alpha': const TodayCounted(review: 1, fresh: 2),
          'Beta': const TodayCounted(review: 0, fresh: 0),
          'Gamma': const TodayUnavailable('Could not count'),
        },
      );

      Finder inRow(String deck, Finder finder) =>
          find.descendant(of: list.row(deck), matching: finder);
      expect(inRow('Alpha', find.text('2 cards')), findsOneWidget);
      expect(inRow('Alpha', find.text('Today 3')), findsOneWidget);
      expect(
        inRow('Alpha', find.byIcon(LucideIcons.chevronRight)),
        findsOneWidget,
      );
      expect(inRow('Beta', find.text('1 card')), findsOneWidget);
      expect(inRow('Beta', find.textContaining('Today')), findsNothing);
      expect(inRow('Gamma', find.text('0 cards')), findsOneWidget);
      expect(inRow('Gamma', find.textContaining('Today')), findsNothing);
      expect(inRow('Gamma', find.byTooltip('Could not count')), findsOneWidget);
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
        today: {
          'Alpha+Beta+Gamma': const TodayCounted(
            review: 4,
            fresh: 3,
            perCard: Duration(seconds: 25),
          ),
        },
      );

      expect(list.counted, contains(equals(list.ids.values.toSet())));
      expect(find.bySemanticsLabel('7 cards for today'), findsOneWidget);
      // Seven cards at 25 s each take 175 s, about 3 minutes.
      expect(find.text('4 to review · 3 new · about 3 min'), findsOneWidget);

      await list.tap('Study all');

      expect(list.sessions, [list.ids.values.toSet()]);
      await list.close();
    },
  );

  testWidgets(
    'in a backlog the header says new cards wait, and not otherwise',
    (tester) async {
      const paused = 'New cards wait until you catch up on your reviews.';
      var list = await _open(
        tester,
        today: {'Alpha+Beta+Gamma': const TodayCounted.backlog(review: 40)},
      );

      expect(find.bySemanticsLabel('40 cards for today'), findsOneWidget);
      // 40 cards at 10 s each, about 7 minutes.
      expect(find.text('40 to review · 0 new · about 7 min'), findsOneWidget);
      expect(find.text(paused), findsOneWidget);
      await list.close();

      // Control: the same header with new cards taken has no such sentence.
      list = await _open(
        tester,
        today: {'Alpha+Beta+Gamma': const TodayCounted(review: 40, fresh: 0)},
      );

      expect(find.text('40 to review · 0 new · about 7 min'), findsOneWidget);
      expect(find.text(paused), findsNothing);
      await list.close();
    },
  );

  testWidgets(
    'with nothing to study the today card says it is done and offers no session',
    (tester) async {
      var list = await _open(
        tester,
        today: {'Alpha+Beta+Gamma': const TodayCounted(review: 0, fresh: 0)},
      );

      expect(find.text("You've done today's cards"), findsOneWidget);
      expect(find.text('Study all'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('for today')), findsNothing);
      await list.close();

      // Control: one card to study shows the count and the button.
      list = await _open(
        tester,
        today: {'Alpha+Beta+Gamma': const TodayCounted(review: 1, fresh: 0)},
      );
      expect(find.text("You've done today's cards"), findsNothing);
      expect(find.text('Study all'), findsOneWidget);
      await list.close();
    },
  );

  testWidgets('a header count that cannot be read says why', (tester) async {
    final list = await _open(
      tester,
      today: {'Alpha+Beta+Gamma': const TodayUnavailable('Storage failed')},
    );

    expect(find.text('Storage failed'), findsOneWidget);
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

    expect(find.byType(DeckListScreen), findsNothing);
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

    expect(find.byType(DeckListScreen), findsOneWidget);
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
