import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/design/app_chip.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/l10n/app_localizations.dart';
import 'package:smartman/photo_import/photo_import.dart';

import 'fakes.dart';

/// Photo import over decks "French" (holding [french]) and "Spanish", with a
/// substitute camera, library and extraction client, started from a button
/// as the home and deck screens start it.
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

  /// What photo import resolved to, once it has.
  Object? popped = _notPopped;
  static const _notPopped = Object();

  static Future<_Import> open(
    WidgetTester tester, {
    DeckId? Function(_Import import)? deck,
    Map<String, String> french = const {},
    ThemeMode themeMode = ThemeMode.light,
    bool disableAnimations = false,
    bool coach = false,
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
    final preferences = await openPreferences(tester, {
      if (!coach) 'photoReviewCoachShown': true,
    });
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
                  import.popped = await importFromPhoto(
                    context,
                    deck: target,
                    client: import.client,
                    photos: import.photos,
                    preferences: import.preferences,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(_shown('open'));
    await tester.pumpAndSettle();
    return import;
  }

  bool get hasPopped => !identical(popped, _notPopped);

  Future<void> tap(Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Takes a photo from the source sheet; the extraction then waits for
  /// [client]'s answer, so this pumps frames rather than settling the
  /// progress bar.
  Future<void> shoot() => _choose('Take photo');

  /// Picks a photo from the source sheet, as [shoot] takes one.
  Future<void> pick() => _choose('Choose from album');

  Future<void> _choose(String source) async {
    await tester.tap(_shown(source));
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Takes a photo and answers its extraction with [cards].
  Future<void> extract(Map<String, String> cards) async {
    await shoot();
    client.answer(cards);
    await tester.pumpAndSettle();
    await next();
    await tester.pumpAndSettle();
  }

  /// Goes on from the choice screen to Review; frames are pumped, not
  /// settled, since Review's coach may be animating.
  Future<void> next() async {
    await tester.tap(_shown('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// The review card showing [text], which a drag moves.
  Finder row(String text) => find
      .ancestor(of: _shown(text), matching: find.byType(GestureDetector))
      .first;

  /// Drags the card showing [text] by [dx], left when negative.
  Future<void> swipe(String text, double dx) async {
    await tester.drag(row(text), Offset(dx, 0));
    await tester.pumpAndSettle();
  }

  /// Whether [text] is drawn struck through, as a removed card's side is.
  bool struck(String text) =>
      tester.widget<Text>(_shown(text)).style?.decoration ==
      TextDecoration.lineThrough;

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

  group('photo source', () {
    testWidgets(
      'the photo button offers the camera and the album in a sheet, and nothing opens before a photo',
      (tester) async {
        final import = await _Import.open(tester);

        expect(_shown('Add a photo'), findsOneWidget);
        expect(_shown('Take photo'), findsOneWidget);
        expect(_shown('Choose from album'), findsOneWidget);
        expect(_shown('Finding cards'), findsNothing);
        expect((import.photos.cameraCalls, import.photos.libraryCalls), (0, 0));
        await import.close();
      },
    );

    for (final (source, calls) in [
      ('Take photo', (1, 0)),
      ('Choose from album', (0, 1)),
    ]) {
      testWidgets('"$source" sends its photo, then reviews the cards', (
        tester,
      ) async {
        final import = await _Import.open(tester);

        await (source == 'Take photo' ? import.shoot() : import.pick());

        expect((import.photos.cameraCalls, import.photos.libraryCalls), calls);
        expect(_shown('Finding cards'), findsOneWidget);
        expect(import.client.calls.single.photo, same(testPhoto));
        import.client.answer({'chien': 'dog'});
        await tester.pumpAndSettle();
        await import.next();
        await tester.pumpAndSettle();
        expect(_shown('Made 1 card'), findsOneWidget);
        await import.close();
      });
    }

    for (final cancel in ['the sheet', 'the camera', 'the album']) {
      testWidgets(
        'cancelling $cancel returns to where the user was, with nothing opened or sent',
        (tester) async {
          final import = await _Import.open(
            tester,
            before: (import) => import.photos
              ..cameraPhoto = null
              ..libraryPhoto = null,
          );

          switch (cancel) {
            case 'the sheet':
              await import.tap(find.byType(ModalBarrier).last);
            case 'the camera':
              await import.tap(_shown('Take photo'));
              expect(import.photos.cameraCalls, 1);
            case _:
              await import.tap(_shown('Choose from album'));
              expect(import.photos.libraryCalls, 1);
          }

          expect(import.hasPopped, isTrue);
          expect(import.popped, isNull);
          expect(_shown('Take photo'), findsNothing);
          expect(_shown('open'), findsOneWidget);
          expect(find.byType(FilledButton), findsNothing, reason: 'no failure');
          expect(import.client.calls, isEmpty);
          await import.close();
        },
      );
    }

    for (final source in ['Take photo', 'Choose from album']) {
      testWidgets(
        'a refused permission behind "$source" says so with a way to Settings, where an unreadable photo has none',
        (tester) async {
          final import = await _Import.open(
            tester,
            before: (import) => import.photos
              ..cameraFailure = const PhotoAccessDenied('denied')
              ..libraryFailure = const PhotoAccessDenied('denied'),
          );

          await import.tap(_shown(source));

          expect(
            _shown(
              "The app isn't allowed to use the camera or your photos. Allow it in Settings.",
            ),
            findsOneWidget,
          );
          expect(_shown('Try again'), findsNothing);
          await import.tap(_shown('Open Settings'));
          expect(import.photos.settingsCalls, 1);
          expect(
            _shown("Couldn't open Settings. Allow it in the Settings app."),
            findsNothing,
          );

          // Control: a failure other than a refusal, through the same retake.
          import.photos
            ..cameraFailure = const PhotoUnreadable('heic')
            ..libraryFailure = const PhotoUnreadable('heic');
          await import.tap(_shown('Retake'));
          await import.tap(_shown(source));
          expect(
            _shown("Couldn't read this photo. Choose another one."),
            findsOneWidget,
          );
          expect(_shown('Open Settings'), findsNothing);
          expect(_shown('Retake'), findsOneWidget);
          expect(import.client.calls, isEmpty);
          await import.close();
        },
      );
    }

    testWidgets('Settings that do not open say so in a snack bar', (
      tester,
    ) async {
      final import = await _Import.open(
        tester,
        before: (import) => import.photos
          ..cameraFailure = const PhotoAccessDenied('denied')
          ..settingsOpen = false,
      );
      await import.tap(_shown('Take photo'));

      await import.tap(_shown('Open Settings'));

      expect(
        _shown("Couldn't open Settings. Allow it in the Settings app."),
        findsOneWidget,
      );
      await import.close();
    });

    testWidgets('a device without a camera says so and offers the album', (
      tester,
    ) async {
      final import = await _Import.open(
        tester,
        before: (import) =>
            import.photos.cameraFailure = const CameraUnavailable('none'),
      );

      await import.tap(_shown('Take photo'));
      expect(
        _shown("Couldn't open the camera. Choose a photo from your album."),
        findsOneWidget,
      );
      expect(_shown('Open Settings'), findsNothing);
      await import.tap(_shown('Retake'));
      await import.pick();

      expect(import.client.calls.single.photo, same(testPhoto));
      await import.close();
    });
  });

  group('extracting', () {
    testWidgets(
      'shows the photo, the progress, skeleton rows and the privacy note',
      (tester) async {
        final import = await _Import.open(tester);

        await import.shoot();

        expect(_shown('Finding cards'), findsOneWidget);
        expect(find.bySemanticsLabel('Your photo'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(
          _shown(
            "Your photo is used only to make cards and isn't kept on the server",
          ),
          findsOneWidget,
        );
        await import.close();
      },
    );

    testWidgets('cancel aborts the request and returns to where the user was', (
      tester,
    ) async {
      final import = await _Import.open(tester);
      await import.shoot();
      final call = import.client.calls.single;

      await import.tap(_shown('Cancel'));

      expect(call.cancelled, isTrue);
      expect(import.hasPopped, isTrue);
      expect(import.popped, isNull);
      expect(_shown('open'), findsOneWidget);
      // A late answer to the cancelled request is ignored.
      call.answer.complete([const CandidateCard(front: 'a', answer: 'b')]);
      await tester.pumpAndSettle();
      expect(_shown('Made 1 card'), findsNothing);
      expect(_shown('open'), findsOneWidget);
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

  group('choice', () {
    /// A page of two topics: two notes, one with printed examples, and a
    /// vocabulary card with its part of speech.
    const page = [
      CandidateCard(
        front: '양성모음',
        answer: 'ㅏ ㅗ ㅑ ㅛ',
        examples: ['졸졸', '찰랑찰랑'],
        topic: '모음조화',
      ),
      CandidateCard(front: '음성모음', answer: 'ㅓ ㅜ ㅡ', topic: '모음조화'),
      CandidateCard(
        front: 'run',
        answer: '달리다',
        partOfSpeech: '[동]',
        topic: '단어',
      ),
    ];

    Future<void> answerPage(
      _Import import, [
      List<CandidateCard> cards = page,
    ]) async {
      await import.shoot();
      import.client.answerCards(cards);
      await import.tester.pumpAndSettle();
    }

    /// The pill or option chip reading [label].
    Finder chip(String label) =>
        find.ancestor(of: _shown(label), matching: find.byType(AppChip)).first;

    testWidgets(
      'shows how many cards were made, each topic as a pill, on at first, and each topic sample in its default shape',
      (tester) async {
        final import = await _Import.open(tester);
        await answerPage(import);

        expect(
          _shown('Made 3 cards.\nWhat will you memorise?'),
          findsOneWidget,
        );
        for (final topic in ['모음조화', '단어']) {
          expect(
            tester.widget<AppChip>(chip(topic)).tone,
            AppChipTone.brand,
            reason: '$topic on',
          );
        }
        expect(_shown('양성모음'), findsOneWidget);
        expect(_shown('ㅏ ㅗ ㅑ ㅛ'), findsOneWidget, reason: '핵심만');
        expect(_shown('run'), findsOneWidget);
        expect(_shown('[동] 달리다'), findsOneWidget);
        expect(_shown('음성모음'), findsNothing, reason: 'one sample a topic');
        await import.close();
      },
    );

    testWidgets(
      'a pill switched off leaves its sample and its cards out of Review, and on again brings them back',
      (tester) async {
        final import = await _Import.open(tester);
        await answerPage(import);

        await import.tap(chip('단어'));
        expect(tester.widget<AppChip>(chip('단어')).tone, AppChipTone.neutral);
        expect(_shown('run'), findsNothing);
        await import.next();
        await tester.pumpAndSettle();
        expect(_shown('Made 2 cards'), findsOneWidget);
        expect(_shown('run'), findsNothing);
        expect(_shown('음성모음'), findsOneWidget);
        await import.close();

        // Control: switched off and on again, the topic goes to Review.
        final again = await _Import.open(tester);
        await answerPage(again);
        await again.tap(chip('단어'));
        await again.tap(chip('단어'));
        await again.next();
        await tester.pumpAndSettle();
        expect(_shown('Made 3 cards'), findsOneWidget);
        expect(_shown('run'), findsOneWidget);
        await again.close();
      },
    );

    testWidgets('Next is disabled with no topic on', (tester) async {
      final import = await _Import.open(tester);
      await answerPage(import);
      FilledButton next() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Next'),
      );

      await import.tap(chip('모음조화'));
      expect(next().onPressed, isNotNull, reason: 'control: one topic on');
      await import.tap(chip('단어'));
      expect(next().onPressed, isNull);
      await import.close();
    });

    testWidgets(
      'content first swaps front and answer for every card of the topic, on the sample and on Review',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final import = await _Import.open(tester);
        await answerPage(import);

        await import.tap(_shown('양성모음'));
        expect(chip('Concept name'), findsOneWidget);
        await import.tap(chip('Content first'));
        expect(_shown('ㅏ ㅗ ㅑ ㅛ'), findsOneWidget);
        expect(
          find.bySemanticsLabel('모음조화 front: ㅏ ㅗ ㅑ ㅛ. Tap to change'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('모음조화 back: 양성모음. Tap to change'),
          findsOneWidget,
        );
        await import.next();
        await tester.pumpAndSettle();

        for (final (front, back) in [('ㅏ ㅗ ㅑ ㅛ', '양성모음'), ('ㅓ ㅜ ㅡ', '음성모음')]) {
          expect(
            find.bySemanticsLabel(
              '$front, $back. Tap to edit, swipe left to remove',
            ),
            findsOneWidget,
            reason: front,
          );
        }
        // Control: the other topic keeps the concept's name in front.
        expect(
          find.bySemanticsLabel(
            'run, [동] 달리다. Tap to edit, swipe left to remove',
          ),
          findsOneWidget,
        );
        await import.close();
        semantics.dispose();
      },
    );

    testWidgets(
      'with examples puts the printed examples after the answer, on the sample and on Review',
      (tester) async {
        final import = await _Import.open(tester);
        await answerPage(import);

        await import.tap(_shown('ㅏ ㅗ ㅑ ㅛ'));
        await import.tap(chip('With examples'));
        expect(_shown('ㅏ ㅗ ㅑ ㅛ\n졸졸\n찰랑찰랑'), findsOneWidget);
        await import.next();
        await tester.pumpAndSettle();

        expect(_shown('ㅏ ㅗ ㅑ ㅛ\n졸졸\n찰랑찰랑'), findsOneWidget);
        expect(_shown('ㅓ ㅜ ㅡ'), findsOneWidget, reason: 'prints none');
        await import.tap(_shown('Add 3 cards to the deck'));
        expect(await import.cards(import.french), [
          ('양성모음', 'ㅏ ㅗ ㅑ ㅛ / 졸졸 / 찰랑찰랑', CardSource.import),
          ('음성모음', 'ㅓ ㅜ ㅡ', CardSource.import),
          ('run', '[동] 달리다', CardSource.import),
        ]);
        await import.close();
      },
    );

    testWidgets('cards with no topic go under one pill, This page', (
      tester,
    ) async {
      final import = await _Import.open(tester);
      await import.shoot();
      import.client.answer({'chien': 'dog', 'chat': 'cat'});
      await tester.pumpAndSettle();

      expect(chip('This page'), findsOneWidget);
      expect(find.byType(AppChip), findsOneWidget);
      expect(_shown('chien'), findsOneWidget, reason: 'its sample');
      await import.next();
      await tester.pumpAndSettle();
      expect(_shown('Made 2 cards'), findsOneWidget);
      await import.close();
    });
  });

  group('review', () {
    /// A page of two topics, two cards and one, a vocabulary card with its
    /// part of speech among them.
    const page = [
      CandidateCard(front: '양성모음', answer: 'ㅏ ㅗ ㅑ ㅛ', topic: '모음조화'),
      CandidateCard(front: '음성모음', answer: 'ㅓ ㅜ ㅡ', topic: '모음조화'),
      CandidateCard(
        front: 'run',
        answer: '달리다',
        partOfSpeech: '[동]',
        topic: '단어',
      ),
    ];

    Future<void> extractPage(
      _Import import, [
      List<CandidateCard> cards = page,
    ]) async {
      await import.shoot();
      import.client.answerCards(cards);
      await import.tester.pumpAndSettle();
      await import.next();
      await import.tester.pumpAndSettle();
    }

    testWidgets(
      'shows the cards made, the deck chip, each topic with its count and switch, and each card front and answer',
      (tester) async {
        final import = await _Import.open(tester);
        await extractPage(import);

        expect(_shown('Made 3 cards'), findsOneWidget);
        expect(_shown('Add to · French'), findsOneWidget);
        expect(_shown('모음조화 · 2'), findsOneWidget);
        expect(_shown('단어 · 1'), findsOneWidget);
        expect(find.byType(Switch), findsNWidgets(2));
        expect(_shown('양성모음'), findsOneWidget);
        expect(_shown('ㅏ ㅗ ㅑ ㅛ'), findsOneWidget);
        expect(_shown('[동] 달리다'), findsOneWidget, reason: '기본');
        expect(_shown('Retake'), findsOneWidget);
        expect(_shown('Add 3 cards to the deck'), findsOneWidget);
        expect(find.byType(Checkbox), findsNothing);
        expect(find.byType(Slider), findsNothing);
        await import.close();
      },
    );

    testWidgets(
      'cards without a topic go into one section with no heading and no switch',
      (tester) async {
        final import = await _Import.open(tester);
        await import.extract({'chien': 'dog', 'chat': 'cat'});

        expect(_shown('Made 2 cards'), findsOneWidget);
        expect(find.byType(Switch), findsNothing);
        expect(_shown('chien'), findsOneWidget);
        await import.close();
      },
    );

    testWidgets(
      'a swipe left removes a card, struck through and still listed, a swipe right puts it back, and the count follows',
      (tester) async {
        final import = await _Import.open(tester);
        await extractPage(import);

        // Control: a drag short of the threshold changes nothing.
        await import.swipe('양성모음', -30);
        expect(import.struck('양성모음'), isFalse);
        expect(_shown('Add 3 cards to the deck'), findsOneWidget);

        await import.swipe('양성모음', -120);
        expect(import.struck('양성모음'), isTrue);
        expect(import.struck('ㅏ ㅗ ㅑ ㅛ'), isTrue);
        expect(import.struck('음성모음'), isFalse);
        expect(_shown('Made 3 cards'), findsOneWidget, reason: 'every card');
        expect(_shown('Add 2 cards to the deck'), findsOneWidget);

        await import.swipe('양성모음', 120);
        expect(import.struck('양성모음'), isFalse);
        expect(_shown('Add 3 cards to the deck'), findsOneWidget);
        await import.close();
      },
    );

    testWidgets(
      "a topic's switch drops every card of it, closed to editing, and switching it back keeps a card removed on its own",
      (tester) async {
        final import = await _Import.open(tester);
        await extractPage(import);
        await import.swipe('양성모음', -120);

        await import.tap(find.byType(Switch).first);
        expect(import.struck('음성모음'), isTrue);
        expect(import.struck('run'), isFalse);
        expect(_shown('Add 1 card to the deck'), findsOneWidget);
        await import.tap(_shown('음성모음'));
        expect(find.byType(TextField), findsNothing, reason: 'not editable');

        await import.tap(find.byType(Switch).first);
        expect(import.struck('음성모음'), isFalse);
        expect(import.struck('양성모음'), isTrue);
        expect(_shown('Add 2 cards to the deck'), findsOneWidget);
        await import.close();
      },
    );

    testWidgets(
      'a tap edits a card in place, its button removes it or puts it back, and Done keeps what was typed but an emptied side',
      (tester) async {
        final import = await _Import.open(tester);
        await extractPage(import);

        await import.tap(_shown('음성모음'));
        expect(find.byType(TextField), findsNWidgets(2));
        await tester.enterText(find.byType(TextField).first, ' ');
        await tester.enterText(find.byType(TextField).last, 'ㅓ ㅜ ㅡ ㅕ ㅠ');
        await import.tap(_shown('Done'));
        expect(find.byType(TextField), findsNothing);
        expect(_shown('음성모음'), findsOneWidget, reason: 'emptied: kept');
        expect(_shown('ㅓ ㅜ ㅡ ㅕ ㅠ'), findsOneWidget);

        await import.tap(_shown('음성모음'));
        await import.tap(_shown('Remove this card'));
        expect(import.struck('음성모음'), isTrue);
        await import.tap(_shown('음성모음'));
        await import.tap(_shown('Put back'));
        expect(import.struck('음성모음'), isFalse);
        await import.close();
      },
    );

    testWidgets(
      'only the cards kept are saved, each answer as shown, and nothing is written before adding',
      (tester) async {
        // Tall enough that every card is on screen.
        await tester.binding.setSurfaceSize(const Size(800, 2000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final import = await _Import.open(tester);
        await extractPage(import, [
          ...page,
          const CandidateCard(front: 'walk', answer: '걷다', topic: '단어'),
        ]);
        await import.swipe('walk', -120);
        await import.tap(find.byType(Switch).first);
        await import.tap(_shown('run'));
        await tester.enterText(find.byType(TextField).last, '[동] 뛰다');
        await import.tap(_shown('Done'));
        expect(await import.cards(import.french), isEmpty);

        await import.tap(_shown('Add 1 card to the deck'));

        expect(await import.cards(import.french), [
          ('run', '[동] 뛰다', CardSource.import),
        ]);
        expect((import.popped! as Deck).id, import.french.id);
        await import.close();
      },
    );

    testWidgets(
      "a card the deck already holds starts removed and marked, and put back it merges its answer into the deck's card",
      (tester) async {
        final import = await _Import.open(tester, french: {'chat': 'cat'});
        await import.extract({'Chat': 'talk', 'chien': 'dog'});

        expect(import.struck('Chat'), isTrue);
        expect(_shown('Already in the deck'), findsOneWidget);
        expect(import.struck('chien'), isFalse, reason: 'control');
        expect(_shown('Add 1 card to the deck'), findsOneWidget);

        await import.swipe('Chat', 120);
        await import.tap(_shown('Add 2 cards to the deck'));

        expect(await import.cards(import.french), [
          ('chat', 'cat / talk', CardSource.manual),
          ('chien', 'dog', CardSource.import),
        ]);
        await import.close();
      },
    );

    testWidgets(
      'cards with one key on the photo are combined, their answers merged',
      (tester) async {
        final import = await _Import.open(tester);

        await import.extract({
          'chat': 'cat',
          'CHAT ': 'tomcat',
          'chien': 'dog',
        });

        expect(_shown('Made 2 cards'), findsOneWidget);
        expect(_shown('cat\ntomcat'), findsOneWidget);
        await import.close();
      },
    );

    testWidgets(
      'each side breaks lines only between words, and a screen reader hears the card as written',
      (tester) async {
        const front = '연역 논증과 귀납 논증의 차이는?';
        const back = '연역은 전제에 담긴 내용만 말하고, 귀납은 전제를 넘어서는 새로운 정보를 준다';
        // A narrow phone, so both sides wrap.
        await tester.binding.setSurfaceSize(const Size(320, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final semantics = tester.ensureSemantics();
        final import = await _Import.open(tester);
        await import.extract({front: back});

        for (final text in [front, back]) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: _shown(text), matching: find.byType(RichText)),
          );
          final drawn = paragraph.text.toPlainText();
          // The paragraph's text laid out again at its width, to read where
          // its lines start.
          final painter = TextPainter(
            text: paragraph.text,
            textDirection: paragraph.textDirection,
            textScaler: paragraph.textScaler,
          )..layout(maxWidth: paragraph.size.width);
          addTearDown(painter.dispose);
          final starts = {
            for (var offset = 0; offset < drawn.length; offset++)
              painter.getLineBoundary(TextPosition(offset: offset)).start,
          };
          expect(starts.length, greaterThan(1), reason: '$text wraps');
          for (final start in starts.where((start) => start > 0)) {
            expect(
              drawn[start - 1],
              ' ',
              reason: 'a line starts at "${drawn.substring(start)}"',
            );
          }
        }
        expect(
          find.bySemanticsLabel(
            '$front, $back. Tap to edit, swipe left to remove',
          ),
          findsOneWidget,
        );
        await import.close();
        semantics.dispose();
      },
    );

    testWidgets('with nothing to add, the add button is disabled', (
      tester,
    ) async {
      final import = await _Import.open(tester);
      await import.extract({'a': '1'});

      await import.swipe('a', -120);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add 0 cards to the deck'),
      );
      expect(button.onPressed, isNull);
      await import.close();
    });

    testWidgets(
      'retake offers the camera and the album again; a cancel keeps the review, a photo replaces it',
      (tester) async {
        final import = await _Import.open(tester);
        await import.extract({'a': '1'});
        await import.tap(_shown('1'));
        await tester.enterText(find.byType(TextField).last, 'one');
        await import.tap(_shown('Done'));

        await import.tap(_shown('Retake'));
        expect(_shown('Take photo'), findsOneWidget);
        import.photos.cameraPhoto = null;
        await import.tap(_shown('Take photo'));
        expect(_shown('Made 1 card'), findsOneWidget);
        expect(_shown('one'), findsOneWidget);
        expect(import.client.calls, hasLength(1));

        import.photos.cameraPhoto = testPhoto;
        await import.tap(_shown('Retake'));
        await import.extract({'b': '2', 'c': '3'});
        expect(import.client.calls, hasLength(2));
        expect(_shown('Made 2 cards'), findsOneWidget);
        expect(_shown('one'), findsNothing);
        expect(await import.cards(import.french), isEmpty);
        await import.close();
      },
    );

    testWidgets('the chip switches the deck the cards are saved into', (
      tester,
    ) async {
      final import = await _Import.open(tester);
      await import.extract({'perro': 'dog'});

      await import.tap(_shown('Add to · French'));
      await import.tap(_shown('Spanish'));
      expect(_shown('Add to · Spanish'), findsOneWidget);
      expect(_shown('Add to · French'), findsNothing);
      await import.tap(_shown('Add 1 card to the deck'));

      expect(await import.cards(import.spanish), [
        ('perro', 'dog', CardSource.import),
      ]);
      expect(await import.cards(import.french), isEmpty);
      expect((import.popped! as Deck).id, import.spanish.id);
      await import.close();
    });

    testWidgets(
      'switching the deck decides again which cards start removed, against the deck chosen',
      (tester) async {
        final import = await _Import.open(tester, french: {'chat': 'cat'});
        await import.extract({'chat': 'talk', 'chien': 'dog'});
        expect(import.struck('chat'), isTrue);
        expect(_shown('Add 1 card to the deck'), findsOneWidget);

        await import.tap(_shown('Add to · French'));
        await import.tap(_shown('Spanish'));
        expect(import.struck('chat'), isFalse);
        expect(_shown('Already in the deck'), findsNothing);
        expect(_shown('Add 2 cards to the deck'), findsOneWidget);

        await import.tap(_shown('Add to · Spanish'));
        await import.tap(_shown('French'));
        expect(import.struck('chat'), isTrue);
        expect(_shown('Add 1 card to the deck'), findsOneWidget);
        await import.close();
      },
    );

    testWidgets('a new deck is named when saving, and created only then', (
      tester,
    ) async {
      final import = await _Import.open(tester, deck: (_) => null);

      await import.extract({'chien': 'dog', 'chat': 'cat'});
      expect(_shown('Add to · New deck'), findsOneWidget);
      expect(await import.deckNames(), ['French', 'Spanish']);
      await import.tap(_shown('Add 2 cards to the deck'));
      await tester.enterText(find.byType(TextField), 'Page 12');
      await import.tap(_shown('Create'));

      expect(await import.deckNames(), ['French', 'Page 12', 'Spanish']);
      final saved = import.popped! as Deck;
      expect(saved.name, 'Page 12');
      expect(await import.cards(saved), [
        ('chien', 'dog', CardSource.import),
        ('chat', 'cat', CardSource.import),
      ]);
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
    testWidgets(
      'a screen reader opens a card with a tap and removes or restores it with a custom action, and a card whose topic is off has neither',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final import = await _Import.open(tester);
        await import.shoot();
        import.client.answerCards(const [
          CandidateCard(front: 'chien', answer: 'dog', topic: 'Animals'),
        ]);
        await tester.pumpAndSettle();
        await import.next();
        await tester.pumpAndSettle();
        void perform(String label, String action) =>
            tester.semantics.customAction(
              find.semantics.byLabel(label),
              CustomSemanticsAction(label: action),
            );

        const kept = 'chien, dog. Tap to edit, swipe left to remove';
        expect(
          tester.getSemantics(find.bySemanticsLabel(kept)),
          matchesSemantics(
            label: kept,
            isButton: true,
            hasTapAction: true,
            customActions: [const CustomSemanticsAction(label: 'Remove')],
          ),
        );
        perform(kept, 'Remove');
        await tester.pumpAndSettle();
        expect(import.struck('chien'), isTrue);

        const removed = 'chien, dog. Removed. Swipe right to put it back';
        perform(removed, 'Put back');
        await tester.pumpAndSettle();
        expect(import.struck('chien'), isFalse);

        tester.semantics.tap(find.semantics.byLabel(kept));
        await tester.pumpAndSettle();
        expect(_shown('Remove this card'), findsOneWidget);
        await import.tap(_shown('Done'));

        await import.tap(find.byType(Switch));
        expect(
          tester.getSemantics(
            find.bySemanticsLabel('chien, dog. Left out with its topic'),
          ),
          matchesSemantics(label: 'chien, dog. Left out with its topic'),
        );
        await import.close();
        semantics.dispose();
      },
    );

    testWidgets(
      'a card whose topic is off takes no swipe, so switching the topic back keeps a duplicate removed',
      (tester) async {
        final import = await _Import.open(tester, french: {'chat': 'cat'});
        await import.shoot();
        import.client.answerCards(const [
          CandidateCard(front: 'chat', answer: 'talk', topic: 'Verbs'),
          CandidateCard(front: 'parler', answer: 'speak', topic: 'Verbs'),
        ]);
        await tester.pumpAndSettle();
        await import.next();
        await tester.pumpAndSettle();
        expect(import.struck('chat'), isTrue);

        await import.tap(find.byType(Switch));
        await import.swipe('chat', 120);
        await import.swipe('parler', -120);
        await import.tap(find.byType(Switch));

        expect(import.struck('chat'), isTrue, reason: 'still a duplicate');
        expect(import.struck('parler'), isFalse, reason: 'swipe ignored');
        // Control: with the topic on, the same swipe puts it back.
        await import.swipe('chat', 120);
        expect(import.struck('chat'), isFalse);
        await import.close();
      },
    );

    testWidgets(
      'what is typed is kept when the card is removed, another card is tapped, its topic is switched or the cards are added',
      (tester) async {
        // Tall enough that every card is on screen.
        await tester.binding.setSurfaceSize(const Size(800, 2000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final import = await _Import.open(tester);
        await import.shoot();
        import.client.answerCards(const [
          CandidateCard(front: 'chien', answer: 'dog', topic: 'Animals'),
          CandidateCard(front: 'chat', answer: 'cat', topic: 'Animals'),
          CandidateCard(front: 'cheval', answer: 'horse', topic: 'Farm'),
        ]);
        await tester.pumpAndSettle();
        await import.next();
        await tester.pumpAndSettle();
        Future<void> type(String side, String text) async {
          await import.tap(_shown(side));
          await tester.enterText(find.byType(TextField).last, text);
          await tester.pump();
        }

        await type('dog', 'puppy');
        await import.tap(_shown('Remove this card'));
        expect(_shown('puppy'), findsOneWidget);
        expect(import.struck('puppy'), isTrue);

        await type('cat', 'kitten');
        await import.tap(_shown('cheval'));
        expect(_shown('kitten'), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, 'pony');
        await tester.pump();
        // Its own topic, switched off and on again.
        await import.tap(find.byType(Switch).last);
        expect(_shown('pony'), findsOneWidget);
        await import.tap(find.byType(Switch).last);

        await type('kitten', 'kitty');
        await import.tap(_shown('Add 2 cards to the deck'));
        expect(await import.cards(import.french), [
          ('chat', 'kitty', CardSource.import),
          ('cheval', 'pony', CardSource.import),
        ]);
        await import.close();
      },
    );

    testWidgets(
      "an edit whose front the deck holds keeps the card, marked, and merges it into the deck's card",
      (tester) async {
        final import = await _Import.open(tester, french: {'chat': 'cat'});
        await import.extract({'chien': 'dog'});
        expect(_shown('Already in the deck'), findsNothing, reason: 'control');

        await import.tap(_shown('chien'));
        await tester.enterText(find.byType(TextField).first, 'chat');
        await import.tap(_shown('Done'));

        expect(import.struck('chat'), isFalse);
        expect(_shown('Already in the deck'), findsOneWidget);
        await import.tap(_shown('Add 1 card to the deck'));
        expect(await import.cards(import.french), [
          ('chat', 'cat / dog', CardSource.manual),
        ]);
        await import.close();
      },
    );
  });

  group('coach', () {
    testWidgets(
      'on first use it teaches left, right and tap in place of the add button, then is stored as shown',
      (tester) async {
        final import = await _Import.open(tester, coach: true);
        await import.shoot();
        import.client.answer({'chien': 'dog', 'chat': 'cat'});
        await tester.pumpAndSettle();
        await import.next();

        expect(_shown('Swipe left to remove'), findsOneWidget);
        expect(_shown('Add 2 cards to the deck'), findsNothing);
        expect(find.byIcon(LucideIcons.pointer), findsOneWidget);
        await tester.tap(_shown('Next'));
        await tester.pump();
        expect(_shown('Swipe right to put it back'), findsOneWidget);
        await tester.tap(_shown('Next'));
        await tester.pump();
        expect(_shown('Tap to edit'), findsOneWidget);
        // Stored as shown when it first shows, not when it ends.
        expect(import.preferences.getBool('photoReviewCoachShown'), isTrue);
        await tester.tap(_shown('Start'));
        await tester.pumpAndSettle();

        expect(_shown('Tap to edit'), findsNothing);
        expect(find.byIcon(LucideIcons.pointer), findsNothing);
        expect(_shown('Add 2 cards to the deck'), findsOneWidget);
        expect(import.preferences.getBool('photoReviewCoachShown'), isTrue);
        await import.close();
      },
    );

    testWidgets('a swipe, a tap, a switch or Skip ends it', (tester) async {
      for (final end in ['swipe', 'tap', 'switch', 'skip']) {
        final import = await _Import.open(tester, coach: true);
        await import.shoot();
        import.client.answerCards(const [
          CandidateCard(front: 'chien', answer: 'dog', topic: 'Animals'),
        ]);
        await tester.pumpAndSettle();
        await import.next();
        expect(_shown('Swipe left to remove'), findsOneWidget, reason: end);

        switch (end) {
          case 'swipe':
            await tester.drag(import.row('chien'), const Offset(-120, 0));
          case 'tap':
            await tester.tap(import.row('chien'));
          case 'switch':
            await tester.tap(find.byType(Switch));
          case _:
            await tester.tap(_shown('Skip'));
        }
        await tester.pumpAndSettle();

        expect(_shown('Swipe left to remove'), findsNothing, reason: end);
        expect(
          import.preferences.getBool('photoReviewCoachShown'),
          isTrue,
          reason: end,
        );
        await import.close();
      }
    });

    testWidgets('once shown it does not show again, nor under reduce motion', (
      tester,
    ) async {
      for (final (stored, reduceMotion) in [(true, false), (false, true)]) {
        final import = await _Import.open(
          tester,
          coach: !stored,
          disableAnimations: reduceMotion,
        );
        await import.extract({'chien': 'dog'});

        expect(_shown('Swipe left to remove'), findsNothing);
        expect(_shown('Add 1 card to the deck'), findsOneWidget);
        await import.close();
      }
      // Control: neither stored nor under reduce motion, it shows.
      final control = await _Import.open(tester, coach: true);
      await control.shoot();
      control.client.answer({'chien': 'dog'});
      await tester.pumpAndSettle();
      await control.next();
      expect(_shown('Swipe left to remove'), findsOneWidget);
      await control.close();
    });
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

          expect(_shown(message), findsOneWidget);
          expect(_shown('Try again'), retry ? findsOneWidget : findsNothing);
          expect(_shown('Retake'), retake ? findsOneWidget : findsNothing);
          if (retry) {
            await tester.tap(_shown('Try again'));
            await tester.pump();
            expect(import.client.calls, hasLength(2));
            expect(import.client.calls.last.photo, same(testPhoto));
            expect(_shown('Finding cards'), findsOneWidget);
          } else if (retake) {
            await import.tap(_shown('Retake'));
            expect(_shown('Take photo'), findsOneWidget);
          } else {
            await import.tap(_shown('Close'));
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

      await import.tap(_shown('Choose from album'));

      expect(
        _shown("Couldn't read this photo. Choose another one."),
        findsOneWidget,
      );
      expect(_shown('Try again'), findsNothing);
      await import.tap(_shown('Retake'));
      expect(_shown('Take photo'), findsOneWidget);
      expect(import.client.calls, isEmpty);
      await import.close();
    });
  });

  group('accessibility', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        'the source sheet, extracting, the choice screen with its options open, review, a card being edited, the deck sheet, a failure and a refusal meet the guidelines in ${mode.name}',
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

          expect(_shown('Add a photo'), findsOneWidget);
          await check();
          await import.shoot();
          await check();
          import.client.answer({'chat': 'talk', 'chien': 'dog'});
          await tester.pumpAndSettle();
          await import.tap(_shown('chat'));
          expect(_shown('Content first'), findsOneWidget);
          await check();
          await import.next();
          await tester.pumpAndSettle();
          expect(_shown('Add 1 card to the deck'), findsOneWidget);
          await check();
          await import.tap(_shown('Add to · French'));
          expect(_shown('Add to'), findsOneWidget);
          await check();
          await import.tap(_shown('Spanish'));
          expect(_shown('Add 2 cards to the deck'), findsOneWidget);
          await import.tap(_shown('dog'));
          expect(_shown('Remove this card'), findsOneWidget);
          await check();
          await import.tap(_shown('Done'));
          await import.tap(_shown('Retake'));
          await import.shoot();
          import.client.fail(const ModelFailed());
          await tester.pumpAndSettle();
          expect(_shown('Try again'), findsOneWidget);
          await check();
          import.photos.cameraFailure = const PhotoAccessDenied('denied');
          await import.tap(_shown('Retake'));
          await import.tap(_shown('Take photo'));
          expect(_shown('Open Settings'), findsOneWidget);
          await check();
          await import.close();
          semantics.dispose();
        },
      );
    }
  });
}

/// The text on screen that reads [text] once its word joiners are left out.
Finder _shown(String text) => find.byWidgetPredicate(
  (widget) => widget is Text && widget.data?.replaceAll('\u2060', '') == text,
);
