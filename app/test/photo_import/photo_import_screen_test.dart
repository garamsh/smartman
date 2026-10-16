import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/design/app_chip.dart';
import 'package:smartman/design/app_list_row.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/l10n/app_localizations.dart';
import 'package:smartman/photo_import/photo_import.dart';

import 'fakes.dart';

/// Photo import over decks "French" (holding [french]) and "Spanish", with a
/// substitute camera, library and extraction client.
class _Import {
  _Import._(
    this.tester,
    this.repository,
    this.french,
    this.spanish,
    this.preferences,
  );

  final WidgetTester tester;
  final DeckRepository repository;
  final Deck french;
  final Deck spanish;
  final SharedPreferencesWithCache preferences;
  final photos = FakePhotoSource();
  final client = FakeExtractionClient();

  /// What the screen popped with, once it has.
  Object? popped = _notPopped;
  static const _notPopped = Object();

  static Future<_Import> open(
    WidgetTester tester, {
    DeckId? Function(_Import import)? deck,
    Map<String, String> french = const {},
    ThemeMode themeMode = ThemeMode.light,
    bool disableAnimations = false,
    Map<String, Object> stored = const {},
    void Function(_Import import)? before,
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
    final (frenchDeck, spanishDeck) = (await tester.runAsync(() async {
      final frenchDeck = await repository.createDeck('French');
      final spanishDeck = await repository.createDeck('Spanish');
      for (final MapEntry(key: front, value: back) in french.entries) {
        await repository.addCard(
          frenchDeck.id,
          front: [TextContent(front)],
          back: [TextContent(back)],
        );
      }
      return (frenchDeck, spanishDeck);
    }))!;
    final preferences = await openPreferences(tester, stored);
    final import = _Import._(
      tester,
      repository,
      frenchDeck,
      spanishDeck,
      preferences,
    );
    before?.call(import);
    final target = deck == null ? frenchDeck.id : deck(import);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [deckRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeMode,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final result = await Navigator.of(context).push(
                    MaterialPageRoute<Deck>(
                      builder: (_) => PhotoImportScreen(
                        deck: target,
                        client: import.client,
                        photos: import.photos,
                        preferences: import.preferences,
                      ),
                    ),
                  );
                  import.popped = result;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return import;
  }

  bool get hasPopped => !identical(popped, _notPopped);

  /// Moves the app to [state], as the system does around a permission prompt.
  Future<void> lifecycle(AppLifecycleState state) async {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }

  /// Lets the oldest held camera open finish; the session it brings is shown
  /// a frame later.
  Future<void> finishOpen() async {
    photos.finishOpen();
    await tester.pump();
    await tester.pump();
  }

  Future<void> tap(Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Takes a photo; the extraction then waits for [client]'s answer, so this
  /// pumps frames rather than settling the progress bar.
  Future<void> shoot() async {
    await tester.tap(find.byTooltip('Take photo'));
    await tester.pump();
    await tester.pump();
  }

  /// Takes a photo and answers its extraction with [cards].
  Future<void> extract(Map<String, String> cards) async {
    await shoot();
    client.answer(cards);
    await tester.pumpAndSettle();
  }

  /// The review row showing [text].
  Finder row(String text) =>
      find.ancestor(of: find.text(text), matching: find.byType(AppRowSurface));

  Future<void> choose(String rowText, String option) async {
    await tap(
      find.descendant(of: row(rowText), matching: find.byType(AppChip)),
    );
    await tap(find.widgetWithText(MenuItemButton, option));
  }

  /// Each card of [deck], as front → back with back lines joined by " / ".
  Future<List<(String, String, CardSource)>> cards(Deck deck) async => [
    for (final card in (await tester.runAsync(
      () => repository.listCards(deck.id),
    ))!)
      (
        plainText(card.front),
        plainText(card.back).replaceAll('\n', ' / '),
        card.source,
      ),
  ];

  Future<List<String>> deckNames() async => [
    for (final deck in (await tester.runAsync(
      () => repository.watchDecks().first,
    ))!)
      deck.name,
  ];

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('capture', () {
    testWidgets(
      'shows the camera, the frame hint, the deck chip, the album and the shutter',
      (tester) async {
        final import = await _Import.open(tester);

        expect(find.byKey(const Key('camera preview')), findsOneWidget);
        expect(
          find.text(
            'Fit one page of a vocabulary book or textbook inside the frame',
          ),
          findsOneWidget,
        );
        expect(find.text('Add to · French'), findsOneWidget);
        expect(find.byTooltip('Choose from album'), findsOneWidget);
        expect(find.byTooltip('Take photo'), findsOneWidget);
        expect(
          Theme.of(tester.element(find.text('Add to · French'))).brightness,
          Brightness.dark,
        );
        await import.close();
      },
    );

    testWidgets('the chip switches the deck the cards are saved into', (
      tester,
    ) async {
      final import = await _Import.open(tester);

      await import.tap(find.text('Add to · French'));
      await import.tap(find.text('Spanish'));
      expect(find.text('Add to · Spanish'), findsOneWidget);
      expect(find.text('Add to · French'), findsNothing);

      await import.extract({'perro': 'dog'});
      expect(
        find.text('Tap to edit, and uncheck the cards to leave out · Spanish'),
        findsOneWidget,
      );
      await import.tap(find.text('Add 1 card'));

      expect(await import.cards(import.spanish), [
        ('perro', 'dog', CardSource.import),
      ]);
      expect(await import.cards(import.french), isEmpty);
      expect((import.popped! as Deck).id, import.spanish.id);
      await import.close();
    });

    testWidgets('a new deck is named when saving, and created only then', (
      tester,
    ) async {
      final import = await _Import.open(tester, deck: (_) => null);
      expect(find.text('Add to · New deck'), findsOneWidget);

      await import.extract({'chien': 'dog', 'chat': 'cat'});
      expect(await import.deckNames(), ['French', 'Spanish']);
      await import.tap(find.text('Add 2 cards'));
      await tester.enterText(find.byType(TextField), 'Page 12');
      await import.tap(find.text('Create'));

      expect(await import.deckNames(), ['French', 'Page 12', 'Spanish']);
      final saved = import.popped! as Deck;
      expect(saved.name, 'Page 12');
      expect(await import.cards(saved), [
        ('chien', 'dog', CardSource.import),
        ('chat', 'cat', CardSource.import),
      ]);
      await import.close();
    });

    testWidgets('the chip can switch from a deck to a new one', (tester) async {
      final import = await _Import.open(tester);

      await import.tap(find.text('Add to · French'));
      await import.tap(find.text('New deck'));

      expect(find.text('Add to · New deck'), findsOneWidget);
      await import.close();
    });

    testWidgets('a photo from the album is sent like one from the camera', (
      tester,
    ) async {
      final import = await _Import.open(tester);

      await tester.tap(find.byTooltip('Choose from album'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Finding cards'), findsOneWidget);
      expect(import.client.calls.single.photo, same(testPhoto));
      await import.close();
    });

    testWidgets(
      'a cancelled album pick stays on the camera and sends nothing',
      (tester) async {
        final import = await _Import.open(
          tester,
          before: (import) => import.photos.libraryPhoto = null,
        );

        await import.tap(find.byTooltip('Choose from album'));

        expect(find.byTooltip('Take photo'), findsOneWidget);
        expect(import.client.calls, isEmpty);
        await import.close();
      },
    );

    testWidgets('a refused camera says so and leaves the album', (
      tester,
    ) async {
      final import = await _Import.open(
        tester,
        before: (import) =>
            import.photos.cameraFailure = const CameraDenied('denied'),
      );

      expect(
        find.text(
          "The app isn't allowed to use the camera. Allow it in Settings, or choose a photo from your album.",
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('camera preview')), findsNothing);
      await tester.tap(find.byTooltip('Choose from album'));
      await tester.pump();
      expect(import.client.calls, hasLength(1));
      await import.close();
    });

    testWidgets('the camera is closed when the photo is taken', (tester) async {
      final import = await _Import.open(tester);
      expect((import.photos.opened, import.photos.closed), (1, 0));

      await import.shoot();

      expect((import.photos.opened, import.photos.closed), (1, 1));
      await import.close();
    });

    testWidgets(
      'a prompt answered during an open leaves that one open and its session',
      (tester) async {
        final import = await _Import.open(
          tester,
          before: (import) => import.photos.holdOpens = true,
        );
        final photos = import.photos;
        final preview = find.byKey(const Key('camera preview'));

        // Control: an open with no lifecycle change shows its session.
        expect(preview, findsNothing);
        await import.finishOpen();
        expect(preview, findsOneWidget);
        expect((photos.openCalls, photos.opened, photos.closed), (1, 1, 0));

        await import.lifecycle(AppLifecycleState.inactive);
        await import.lifecycle(AppLifecycleState.resumed);
        expect(photos.openCalls, 2);
        expect(preview, findsNothing);

        // The prompt makes the app inactive; answering it resumes the app.
        await import.lifecycle(AppLifecycleState.inactive);
        await import.lifecycle(AppLifecycleState.resumed);
        await import.finishOpen();

        expect(preview, findsOneWidget);
        expect((photos.openCalls, photos.opened, photos.closed), (2, 2, 1));
        await import.shoot();
        expect(import.client.calls.single.photo, same(testPhoto));
        await import.close();
      },
    );

    testWidgets('a refused open is tried once more when the app returns', (
      tester,
    ) async {
      final import = await _Import.open(
        tester,
        before: (import) => import.photos.holdOpens = true,
      );
      final photos = import.photos;

      await import.lifecycle(AppLifecycleState.inactive);
      photos.cameraFailure = const CameraDenied('denied');
      await import.finishOpen();
      expect(
        find.text(
          "The app isn't allowed to use the camera. Allow it in Settings, or choose a photo from your album.",
        ),
        findsOneWidget,
      );
      expect(photos.openCalls, 1);

      // Access allowed in Settings, then back to the app.
      photos.cameraFailure = null;
      await import.lifecycle(AppLifecycleState.resumed);
      expect(photos.openCalls, 2);
      await import.finishOpen();

      expect(find.byKey(const Key('camera preview')), findsOneWidget);
      expect((photos.openCalls, photos.opened, photos.closed), (2, 1, 0));
      await import.close();
    });

    testWidgets('leaving the screen during an open closes its late session', (
      tester,
    ) async {
      final import = await _Import.open(
        tester,
        before: (import) => import.photos.holdOpens = true,
      );

      await import.tap(find.byTooltip('Close'));
      expect(import.hasPopped, isTrue);
      await import.finishOpen();

      expect((import.photos.opened, import.photos.closed), (1, 1));
      await import.close();
    });
  });

  group('extracting', () {
    testWidgets(
      'shows the photo, the progress, skeleton rows and the privacy note',
      (tester) async {
        final import = await _Import.open(tester);

        await import.shoot();

        expect(find.text('Finding cards'), findsOneWidget);
        expect(find.bySemanticsLabel('Your photo'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(
          find.text(
            "Your photo is used only to make cards and isn't kept on the server",
          ),
          findsOneWidget,
        );
        await import.close();
      },
    );

    testWidgets('cancel aborts the request and returns to the camera', (
      tester,
    ) async {
      final import = await _Import.open(tester);
      await import.shoot();
      final call = import.client.calls.single;

      await import.tap(find.text('Cancel'));

      expect(call.cancelled, isTrue);
      expect(find.byTooltip('Take photo'), findsOneWidget);
      // A late answer to the cancelled request is ignored.
      call.answer.complete([const CandidateCard(front: 'a', meaning: 'b')]);
      await tester.pumpAndSettle();
      expect(find.text('Found 1 card'), findsNothing);
      expect(find.byTooltip('Take photo'), findsOneWidget);
      await import.close();
    });

    testWidgets('leaving the screen while extracting aborts the request', (
      tester,
    ) async {
      final import = await _Import.open(tester);
      await import.shoot();
      final call = import.client.calls.single;
      expect(call.cancelled, isFalse);

      await import.close();

      expect(call.cancelled, isTrue);
    });

    for (final (reduceMotion, moves) in [(true, false), (false, true)]) {
      testWidgets(
        'with reduce motion ${reduceMotion ? 'on' : 'off'}, the skeleton rows ${moves ? 'shimmer' : 'hold still'}',
        (tester) async {
          final import = await _Import.open(
            tester,
            disableAnimations: reduceMotion,
          );
          await import.shoot();
          final shimmer = find.descendant(
            of: find.byType(ListView),
            matching: find.byType(FadeTransition),
          );
          expect(shimmer, findsWidgets);
          double opacity() =>
              tester.widget<FadeTransition>(shimmer.first).opacity.value;

          final before = opacity();
          await tester.pump(const Duration(milliseconds: 600));

          expect(opacity() != before, moves);
          await import.close();
        },
      );
    }
  });

  group('review', () {
    testWidgets(
      'shows the count, the hint with the deck, and each card split front and back',
      (tester) async {
        final import = await _Import.open(tester);

        await import.extract({'chien': 'dog', 'chat': 'cat'});

        expect(find.text('Found 2 cards'), findsOneWidget);
        expect(
          find.text('Tap to edit, and uncheck the cards to leave out · French'),
          findsOneWidget,
        );
        expect(find.text('chien'), findsOneWidget);
        expect(find.text('dog'), findsOneWidget);
        expect(find.text('Retake'), findsOneWidget);
        expect(find.text('Add 2 cards'), findsOneWidget);
        await import.close();
      },
    );

    testWidgets(
      'a short side sits vertically centred beside a taller one in its row',
      (tester) async {
        final import = await _Import.open(tester);

        await import.extract({'chien': 'dog\nhound\npuppy'});

        final short = find.text('chien');
        final side = find
            .ancestor(of: short, matching: find.byType(Expanded))
            .first;
        expect(
          tester.getRect(side).height,
          greaterThan(tester.getRect(short).height * 2),
          reason: 'the taller back stretches the row',
        );
        expect(
          tester.getCenter(short).dy,
          closeTo(tester.getCenter(side).dy, 1),
        );
        await import.close();
      },
    );

    testWidgets(
      'cards with one key on the photo are combined, their backs merged',
      (tester) async {
        final import = await _Import.open(tester);

        await import.extract({
          'chat': 'cat',
          'CHAT ': 'tomcat',
          'chien': 'dog',
        });

        expect(find.text('Found 2 cards'), findsOneWidget);
        expect(find.text('cat\ntomcat'), findsOneWidget);
        await import.close();
      },
    );

    testWidgets(
      'edits, exclusions and the duplicate options decide what is saved, and nothing is written before adding',
      (tester) async {
        final import = await _Import.open(
          tester,
          french: {'chat': 'cat', 'chien': 'dog', 'lapin': 'rabbit'},
        );
        // Tall enough that every review row is built.
        await tester.binding.setSurfaceSize(const Size(800, 2000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final before = await import.cards(import.french);

        await import.extract({
          'Chat': 'talk',
          'chien': 'hound',
          'lapin': 'bunny',
          'oiseau': 'bird',
          'poisson': 'fish',
          'cheval': 'horse',
        });
        expect(find.text('3 cards already in the deck'), findsOneWidget);
        expect(find.text('Skip'), findsNWidgets(3));
        expect(find.text('Add 3 cards'), findsOneWidget);

        await import.tap(find.text('bird'));
        await tester.enterText(find.byType(TextField), 'a bird');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(find.text('a bird'), findsOneWidget);

        await import.tap(
          find.descendant(
            of: import.row('poisson'),
            matching: find.byType(Checkbox),
          ),
        );
        expect(find.text('Add 2 cards'), findsOneWidget);

        await import.choose('Chat', 'Merge back');
        await import.choose('chien', 'Add as new');
        expect(find.text('Add 4 cards'), findsOneWidget);
        expect(await import.cards(import.french), before);

        await import.tap(find.text('Add 4 cards'));

        expect(await import.cards(import.french), [
          ('chat', 'cat / talk', CardSource.manual),
          ('chien', 'dog', CardSource.manual),
          ('lapin', 'rabbit', CardSource.manual),
          ('chien', 'hound', CardSource.import),
          ('oiseau', 'a bird', CardSource.import),
          ('cheval', 'horse', CardSource.import),
        ]);
        expect((import.popped! as Deck).id, import.french.id);
        await import.close();
      },
    );

    testWidgets('an edit emptied keeps the text it had', (tester) async {
      final import = await _Import.open(tester);
      await import.extract({'chien': 'dog'});

      await import.tap(find.text('dog'));
      await tester.enterText(find.byType(TextField), '  ');
      await tester.pump();
      expect(find.text('Enter some text'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('dog'), findsOneWidget);
      await import.close();
    });

    testWidgets('the saved count equals the checked count', (tester) async {
      final import = await _Import.open(tester);
      await import.extract({'a': '1', 'b': '2', 'c': '3', 'd': '4'});

      for (final front in ['b', 'd']) {
        await import.tap(
          find.descendant(
            of: import.row(front),
            matching: find.byType(Checkbox),
          ),
        );
      }
      final checked = tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .where((box) => box.value ?? false)
          .length;
      expect(checked, 2);
      await import.tap(find.text('Add 2 cards'));

      expect(await import.cards(import.french), hasLength(checked));
      await import.close();
    });

    testWidgets('with nothing to add, the add button is disabled', (
      tester,
    ) async {
      final import = await _Import.open(tester);
      await import.extract({'a': '1'});

      await import.tap(find.byType(Checkbox));

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add 0 cards'),
      );
      expect(button.onPressed, isNull);
      await import.close();
    });

    testWidgets('retake discards the candidates and returns to the camera', (
      tester,
    ) async {
      final import = await _Import.open(tester);
      await import.extract({'a': '1'});

      await import.tap(find.text('Retake'));

      expect(find.byTooltip('Take photo'), findsOneWidget);
      expect(await import.cards(import.french), isEmpty);
      await import.close();
    });

    testWidgets('closing without adding writes nothing and pops with nothing', (
      tester,
    ) async {
      final import = await _Import.open(tester, deck: (_) => null);
      await import.extract({'a': '1'});

      await import.tap(find.byTooltip('Close'));

      expect(import.hasPopped, isTrue);
      expect(import.popped, isNull);
      expect(await import.deckNames(), ['French', 'Spanish']);
      await import.close();
    });
  });

  group('detail level', () {
    const run = CandidateCard(
      front: 'run',
      meaning: '달리다',
      partOfSpeech: '[동]',
      examples: ['I run every morning.', 'run a shop'],
    );
    const river = CandidateCard(front: 'river', meaning: '강');

    DetailLevel selected(WidgetTester tester) => tester
        .widget<SegmentedButton<DetailLevel>>(
          find.byType(SegmentedButton<DetailLevel>),
        )
        .selected
        .single;

    Future<void> extractCards(_Import import) async {
      await import.shoot();
      import.client.answerCards(const [run, river]);
      await import.tester.pumpAndSettle();
    }

    testWidgets(
      'with no choice stored, capture and review start at Basic, the part of speech before the meaning',
      (tester) async {
        final import = await _Import.open(tester);
        expect(import.preferences.getString('photoDetailLevel'), isNull);

        expect(find.text('What each card says'), findsOneWidget);
        expect(selected(tester), DetailLevel.basic);
        await extractCards(import);

        expect(selected(tester), DetailLevel.basic);
        expect(find.text('[동] 달리다'), findsOneWidget);
        expect(find.text('강'), findsOneWidget);
        await import.close();
      },
    );

    for (final (level, label, back) in [
      (DetailLevel.simple, 'Simple', '달리다'),
      (DetailLevel.basic, 'Basic', '[동] 달리다'),
      (
        DetailLevel.detailed,
        'Detailed',
        '[동] 달리다\nI run every morning.\nrun a shop',
      ),
    ]) {
      testWidgets(
        '$label, chosen on the camera, composes each answer it shows and saves, and is remembered',
        (tester) async {
          final initial = level == DetailLevel.basic
              ? DetailLevel.simple
              : DetailLevel.basic;
          final import = await _Import.open(
            tester,
            stored: {'photoDetailLevel': initial.name},
          );
          expect(selected(tester), initial, reason: 'the stored level');

          await import.tap(find.text(label));
          expect(selected(tester), level);
          expect(import.preferences.getString('photoDetailLevel'), level.name);
          await extractCards(import);

          expect(selected(tester), level);
          expect(find.text(back), findsOneWidget);
          expect(find.text('강'), findsOneWidget, reason: 'no field to add');
          await import.tap(find.text('Add 2 cards'));

          expect(await import.cards(import.french), [
            ('run', back.replaceAll('\n', ' / '), CardSource.import),
            ('river', '강', CardSource.import),
          ]);
          await import.close();
        },
      );
    }

    testWidgets(
      'switching on review recomposes every answer but one typed by hand, which is marked edited and saved as typed',
      (tester) async {
        final import = await _Import.open(tester);
        await extractCards(import);
        expect(find.text('Edited'), findsNothing);

        await import.tap(find.text('강'));
        await tester.enterText(find.byType(TextField), 'a river');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(find.text('Edited'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Answer: a river, Edited'),
          findsOneWidget,
        );

        await import.tap(find.text('Detailed'));

        expect(
          find.text('[동] 달리다\nI run every morning.\nrun a shop'),
          findsOneWidget,
        );
        expect(find.text('a river'), findsOneWidget);
        expect(find.text('Edited'), findsOneWidget);
        expect(import.preferences.getString('photoDetailLevel'), 'detailed');

        await import.tap(find.text('Simple'));
        expect(find.text('달리다'), findsOneWidget);
        expect(find.text('a river'), findsOneWidget);
        await import.tap(find.text('Add 2 cards'));

        expect(await import.cards(import.french), [
          ('run', '달리다', CardSource.import),
          ('river', 'a river', CardSource.import),
        ]);
        await import.close();
      },
    );

    testWidgets(
      'candidates combined on the photo merge their answers at the chosen level',
      (tester) async {
        final import = await _Import.open(tester);
        await import.shoot();
        import.client.answerCards(const [
          run,
          CandidateCard(front: 'Run', meaning: '운영하다', partOfSpeech: '[동]'),
        ]);
        await tester.pumpAndSettle();

        expect(find.text('[동] 달리다\n[동] 운영하다'), findsOneWidget);
        await import.tap(find.text('Simple'));
        expect(find.text('달리다\n운영하다'), findsOneWidget);
        await import.close();
      },
    );
  });

  group('failures', () {
    final cases = <(PhotoImportFailure, String, bool, bool)>[
      (
        ExtractionOffline(Exception('offline')),
        "You're offline. Check your connection and try again.",
        true,
        true,
      ),
      (
        const PhotoRefused(413),
        "This photo can't be sent. Retake it or choose another.",
        false,
        true,
      ),
      (
        const PhotoRefused(415),
        "This photo can't be sent. Retake it or choose another.",
        false,
        true,
      ),
      (
        const NoCardsFound(),
        'No cards found. Try a brighter, straighter photo.',
        false,
        true,
      ),
      (
        const DailyLimitReached(),
        "You've reached today's limit for photos. Try again tomorrow.",
        false,
        false,
      ),
      (
        const ModelFailed(),
        "Couldn't read the cards. Please try again in a moment.",
        true,
        true,
      ),
      (
        const SignInRequired(),
        'You need to sign in. Sign in again from the account screen.',
        false,
        false,
      ),
      (
        const ServiceFailed('HTTP 503'),
        "Can't make cards from photos right now. Please try again in a moment.",
        true,
        true,
      ),
    ];
    for (final (failure, message, retry, retake) in cases) {
      testWidgets(
        '$failure is shown${retry ? ' with a retry' : ''}${retake ? ' with a retake' : ''}',
        (tester) async {
          final import = await _Import.open(tester);
          await import.shoot();

          import.client.fail(failure);
          await tester.pumpAndSettle();

          expect(find.text(message), findsOneWidget);
          expect(find.text('Try again'), retry ? findsOneWidget : findsNothing);
          expect(find.text('Retake'), retake ? findsOneWidget : findsNothing);
          if (retry) {
            await tester.tap(find.text('Try again'));
            await tester.pump();
            expect(import.client.calls, hasLength(2));
            expect(import.client.calls.last.photo, same(testPhoto));
            expect(find.text('Finding cards'), findsOneWidget);
          } else if (retake) {
            await import.tap(find.text('Retake'));
            expect(find.byTooltip('Take photo'), findsOneWidget);
          } else {
            await import.tap(find.text('Close'));
            expect(import.popped, isNull);
          }
          expect(await import.cards(import.french), isEmpty);
          await import.close();
        },
      );
    }

    testWidgets('an unreadable album photo is shown with a retake', (
      tester,
    ) async {
      final import = await _Import.open(tester);
      import.photos.libraryFailure = const PhotoUnreadable('heic');

      await import.tap(find.byTooltip('Choose from album'));

      expect(
        find.text("Couldn't read this photo. Choose another one."),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNothing);
      await import.tap(find.text('Retake'));
      expect(find.byTooltip('Take photo'), findsOneWidget);
      expect(import.client.calls, isEmpty);
      await import.close();
    });
  });

  group('accessibility', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        'capture, the deck sheet, extracting, review and a failure meet the guidelines in ${mode.name}',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final import = await _Import.open(
            tester,
            themeMode: mode,
            french: {'chat': 'cat'},
          );
          Future<void> check() async {
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

          await check();
          await import.tap(find.text('Add to · French'));
          expect(find.text('Add to'), findsOneWidget);
          await check();
          await import.tap(find.text('Spanish'));
          expect(find.text('Add to · Spanish'), findsOneWidget);
          await import.shoot();
          await check();
          import.client.answer({'chat': 'talk', 'chien': 'dog'});
          await tester.pumpAndSettle();
          expect(find.text('Add 2 cards'), findsOneWidget);
          await check();
          await import.tap(find.text('Retake'));
          await import.shoot();
          import.client.fail(const ModelFailed());
          await tester.pumpAndSettle();
          expect(find.text('Try again'), findsOneWidget);
          await check();
          await import.close();
          semantics.dispose();
        },
      );
    }
  });
}
