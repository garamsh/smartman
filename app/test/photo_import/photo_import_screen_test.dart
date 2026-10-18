import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/l10n/app_localizations.dart';
import 'package:smartman/photo_import/photo_import.dart';

import '../home/home_data.dart';
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
  final UnreadableDecks repository;
  final Deck french;
  final Deck spanish;
  final SharedPreferencesWithCache preferences;
  final photos = FakePhotoSource();
  final client = FakeExtractionClient();

  /// Semantics, on for the import's life, so rows are found by what a
  /// screen reader hears.
  late final SemanticsHandle _semantics = tester.ensureSemantics();

  /// What photo import resolved to, once it has.
  Object? popped = _notPopped;
  static const _notPopped = Object();

  static Future<_Import> open(
    WidgetTester tester, {
    DeckId? Function(_Import import)? deck,
    Map<String, String> french = const {},
    ThemeMode themeMode = ThemeMode.light,
    bool disableAnimations = false,
    void Function(_Import import)? before,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var ids = 0;
    var tick = 0;
    final repository = UnreadableDecks(
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
    final preferences = await openPreferences(tester);
    final import = _Import._(
      tester,
      repository,
      frenchDeck,
      spanishDeck,
      preferences,
    );
    import._semantics;
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

  /// Takes a photo and answers its extraction with vocabulary cards of one
  /// sense, front → meaning.
  Future<void> extract(Map<String, String> cards) async {
    await shoot();
    client.answer(cards);
    await tester.pumpAndSettle();
  }

  /// Takes a photo and answers its extraction with [cards].
  Future<void> extractCards(List<CandidateCard> cards) async {
    await shoot();
    client.answerCards(cards);
    await tester.pumpAndSettle();
  }

  /// The list row showing [text], which a drag moves.
  Finder row(String text) =>
      find.ancestor(of: _shown(text), matching: find.byType(Dismissible)).first;

  /// Drags the row showing [text] by [dx], left when negative.
  Future<void> swipe(String text, double dx) async {
    await tester.drag(row(text), Offset(dx, 0));
    await tester.pumpAndSettle();
  }

  /// The check of the row whose front reads [front].
  Finder check(String front) => find.bySemanticsLabel('Include $front');

  /// Whether the row whose front reads [front] is included.
  bool included(String front) =>
      isSemantics(isChecked: true)
          .matches(tester.getSemantics(check(front)), {});

  /// Opens the form menu of the section titled [title].
  Future<void> menu(String title) =>
      tap(find.bySemanticsLabel(RegExp('^${RegExp.escape(title)} card form')));

  /// Picks the menu item reading [label].
  Future<void> pickItem(String label) =>
      tap(find.widgetWithText(MenuItemButton, label));

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
    _semantics.dispose();
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
        expect(_shown('Found 1 word'), findsOneWidget);
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

  group('list', () {
    /// A word-book page of two topics: a word of two senses with its
    /// pronunciation and a synonym, a word of one, and a phrase with no part
    /// of speech.
    final words = [
      const CandidateCard(
        front: 'face',
        kind: CardKind.vocabulary,
        senses: [
          Sense(pos: '[동]', meaning: '직면하다, 마주하다'),
          Sense(pos: '[명]', meaning: '표면, 겉면'),
        ],
        pronunciation: "['feis]",
        extras: [Extra(label: '유의어', text: 'confront')],
        topic: '최빈출 단어',
      ),
      CandidateCard.word(
        front: 'include',
        meaning: '포함하다',
        partOfSpeech: '[동]',
        topic: '최빈출 단어',
      ),
      CandidateCard.word(
        front: 'in addition',
        meaning: '~뿐만 아니라',
        topic: '빈출 숙어',
      ),
    ];

    /// A notes page: two rules and an identify card of their topic.
    const notes = [
      CandidateCard(front: '양성모음', answer: 'ㅏ ㅗ ㅑ ㅛ', topic: '모음조화'),
      CandidateCard(front: '음성모음', answer: 'ㅓ ㅜ ㅡ', topic: '모음조화'),
      CandidateCard(
        front: "'아름다운 꽃'의 '아'",
        answer: '양성모음 — ㅏ',
        type: CardType.identify,
        topic: '모음조화',
      ),
    ];

    testWidgets(
      'a word page shows the words found, the deck, each topic with its count and form, and each row checked with its senses one per line',
      (tester) async {
        final import = await _Import.open(tester);
        await import.extractCards(words);

        expect(_shown('Found 3 words'), findsOneWidget);
        expect(_shown("Adds to the deck '"), findsOneWidget);
        expect(_shown('French'), findsOneWidget);
        expect(_shown('최빈출 단어 2'), findsOneWidget);
        expect(_shown('빈출 숙어 1'), findsOneWidget);
        expect(_shown('Word → meaning'), findsNWidgets(2));
        expect(_shown('face'), findsOneWidget);
        expect(_shown('[동] 직면하다, 마주하다\n[명] 표면, 겉면'), findsOneWidget);
        expect(_shown('~뿐만 아니라'), findsOneWidget, reason: 'no label');
        for (final front in ['face', 'include', 'in addition']) {
          expect(import.included(front), isTrue, reason: front);
        }
        expect(_shown('Add 3 cards'), findsOneWidget);
        expect(find.byType(Switch), findsNothing);
        expect(_shown('Next'), findsNothing, reason: 'no choice screen');
        await import.close();
      },
    );

    testWidgets(
      'a notes page counts the cards made, its rules front to back and its identify cards in their own section, left out',
      (tester) async {
        final import = await _Import.open(tester);
        await import.extractCards(notes);

        expect(_shown('Made 3 cards'), findsOneWidget);
        expect(_shown('모음조화 2'), findsOneWidget);
        expect(_shown('Identify · 모음조화 1'), findsOneWidget);
        expect(_shown('Front → back'), findsNWidgets(2));
        expect(import.included('양성모음'), isTrue);
        expect(import.included("'아름다운 꽃'의 '아'"), isFalse);
        expect(_shown('Add 2 cards'), findsOneWidget);

        await import.tap(import.check("'아름다운 꽃'의 '아'"));
        await import.tap(_shown('Add 3 cards'));
        expect(await import.cards(import.french), [
          ('양성모음', 'ㅏ ㅗ ㅑ ㅛ', CardSource.import),
          ('음성모음', 'ㅓ ㅜ ㅡ', CardSource.import),
          ("'아름다운 꽃'의 '아'", '양성모음 — ㅏ', CardSource.import),
        ]);
        await import.close();
      },
    );

    testWidgets(
      'a check leaves a row out and puts it back, and only the rows checked are added',
      (tester) async {
        final import = await _Import.open(tester);
        await import.extractCards(words);

        await import.tap(import.check('include'));
        expect(import.included('include'), isFalse);
        expect(_shown('Add 2 cards'), findsOneWidget);
        await import.tap(import.check('in addition'));
        await import.tap(import.check('in addition'));
        expect(import.included('in addition'), isTrue, reason: 'put back');

        await import.tap(_shown('Add 2 cards'));
        expect(await import.cards(import.french), [
          ('face', '[동] 직면하다, 마주하다 / [명] 표면, 겉면', CardSource.import),
          ('in addition', '~뿐만 아니라', CardSource.import),
        ]);
        await import.close();
      },
    );

    testWidgets('a swipe left leaves a row out, and a short drag does not', (
      tester,
    ) async {
      final import = await _Import.open(tester);
      await import.extract({'chien': 'dog', 'chat': 'cat'});

      await import.swipe('chien', -30);
      expect(import.included('chien'), isTrue, reason: 'control: short');
      await import.swipe('chien', -600);
      expect(import.included('chien'), isFalse);
      expect(_shown('chien'), findsOneWidget, reason: 'still listed');
      expect(_shown('Add 1 card'), findsOneWidget);
      // A swipe does not put it back; its check does.
      await import.swipe('chien', -600);
      expect(import.included('chien'), isFalse);
      await import.tap(import.check('chien'));
      expect(import.included('chien'), isTrue);
      await import.close();
    });

    testWidgets(
      "the menu's direction turns a section's cards to meaning → word, or makes both, counting each card",
      (tester) async {
        final import = await _Import.open(tester);
        await import.extractCards(words);

        await import.menu('빈출 숙어');
        expect(find.byType(MenuItemButton), findsNWidgets(6));
        await import.pickItem('Meaning → word');
        expect(_shown('Meaning → word'), findsOneWidget, reason: 'header');
        expect(_shown('Add 3 cards'), findsOneWidget);

        await import.menu('최빈출 단어');
        await import.pickItem('Both ways');
        expect(_shown('Both ways'), findsOneWidget, reason: 'header');
        expect(_shown('Add 5 cards'), findsOneWidget);

        await import.tap(_shown('Add 5 cards'));
        expect(await import.cards(import.french), [
          ('face', '[동] 직면하다, 마주하다 / [명] 표면, 겉면', CardSource.import),
          ('[동] 직면하다, 마주하다\n[명] 표면, 겉면', 'face', CardSource.import),
          ('include', '[동] 포함하다', CardSource.import),
          ('[동] 포함하다', 'include', CardSource.import),
          ('~뿐만 아니라', 'in addition', CardSource.import),
        ]);
        await import.close();
      },
    );

    testWidgets(
      'first meaning only and the part of speech change what a section shows and saves',
      (tester) async {
        final import = await _Import.open(tester);
        await import.extractCards(words);

        await import.menu('최빈출 단어');
        await import.pickItem('First meaning only');
        expect(_shown('[동] 직면하다, 마주하다'), findsOneWidget);
        await import.menu('최빈출 단어');
        await import.pickItem('Show part of speech');
        expect(_shown('직면하다, 마주하다'), findsOneWidget);
        expect(_shown('[동] 직면하다, 마주하다'), findsNothing);

        await import.tap(_shown('Add 3 cards'));
        expect((await import.cards(import.french)).take(2).toList(), [
          ('face', '직면하다, 마주하다', CardSource.import),
          ('include', '포함하다', CardSource.import),
        ]);
        await import.close();
      },
    );

    testWidgets(
      'pronunciation and extras are offered only where the page prints them, and off until chosen',
      (tester) async {
        final import = await _Import.open(tester);
        await import.extractCards(words);
        expect(_shown("face\n['feis]"), findsNothing);

        await import.menu('빈출 숙어');
        expect(
          find.widgetWithText(MenuItemButton, 'Show pronunciation'),
          findsNothing,
        );
        expect(
          find.widgetWithText(MenuItemButton, 'Show synonyms and more'),
          findsNothing,
        );
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();

        await import.menu('최빈출 단어');
        await import.pickItem('Show pronunciation');
        expect(_shown("face\n['feis]"), findsOneWidget);
        await import.menu('최빈출 단어');
        await import.pickItem('Show synonyms and more');
        expect(
          _shown('[동] 직면하다, 마주하다\n[명] 표면, 겉면\n유의어 confront'),
          findsOneWidget,
        );
        await import.close();
      },
    );

    testWidgets("a note section's menu swaps front and back", (tester) async {
      final import = await _Import.open(tester);
      await import.extractCards(notes);

      await import.menu('모음조화');
      expect(
        find.widgetWithText(MenuItemButton, 'Meaning → word'),
        findsNothing,
      );
      await import.pickItem('Swap sides');
      expect(_shown('Back → front'), findsOneWidget);

      await import.tap(_shown('Add 2 cards'));
      expect(await import.cards(import.french), [
        ('ㅏ ㅗ ㅑ ㅛ', '양성모음', CardSource.import),
        ('ㅓ ㅜ ㅡ', '음성모음', CardSource.import),
      ]);
      await import.close();
    });

    testWidgets(
      "the menu's last item leaves out every row of a section, then includes them",
      (tester) async {
        final import = await _Import.open(tester);
        await import.extractCards(words);

        await import.menu('최빈출 단어');
        await import.pickItem('Leave out this group');
        expect(import.included('face'), isFalse);
        expect(import.included('include'), isFalse);
        expect(import.included('in addition'), isTrue, reason: 'control');
        expect(_shown('Add 1 card'), findsOneWidget);

        await import.menu('최빈출 단어');
        await import.pickItem('Include this group');
        expect(import.included('face'), isTrue);
        expect(_shown('Add 3 cards'), findsOneWidget);
        await import.close();
      },
    );

    testWidgets(
      'a row the deck holds starts left out, marked, and merges into its card when checked',
      (tester) async {
        final import = await _Import.open(tester, french: {'chat': 'cat'});
        await import.extract({'chat': 'talk', 'chien': 'dog'});

        expect(import.included('chat'), isFalse);
        expect(_shown('Already in the deck'), findsOneWidget);
        expect(import.included('chien'), isTrue, reason: 'control');

        await import.tap(import.check('chat'));
        await import.tap(_shown('Add 2 cards'));
        expect(await import.cards(import.french), [
          ('chat', 'cat / talk', CardSource.manual),
          ('chien', 'dog', CardSource.import),
        ]);
        await import.close();
      },
    );

    testWidgets(
      'the deck name opens the deck chooser, and another deck decides again which rows it holds',
      (tester) async {
        final import = await _Import.open(tester, french: {'chat': 'cat'});
        await import.extract({'chat': 'talk', 'chien': 'dog'});
        expect(import.included('chat'), isFalse);

        await import.tap(_shown('French'));
        expect(_shown('Add to'), findsOneWidget);
        await import.tap(_shown('Spanish'));
        expect(import.included('chat'), isTrue);
        expect(_shown('Already in the deck'), findsNothing);
        await import.tap(_shown('Add 2 cards'));

        expect(await import.cards(import.spanish), [
          ('chat', 'talk', CardSource.import),
          ('chien', 'dog', CardSource.import),
        ]);
        expect((import.popped! as Deck).id, import.spanish.id);
        await import.close();
      },
    );

    testWidgets('a new deck is named when saving, and created only then', (
      tester,
    ) async {
      final import = await _Import.open(tester, deck: (_) => null);
      await import.extract({'chien': 'dog', 'chat': 'cat'});
      expect(_shown('New deck'), findsOneWidget);
      expect(await import.deckNames(), ['French', 'Spanish']);

      await import.tap(_shown('Add 2 cards'));
      await tester.enterText(find.byType(TextField), 'Page 12');
      await import.tap(_shown('Create'));

      expect(await import.deckNames(), ['French', 'Page 12', 'Spanish']);
      expect(await import.cards(import.popped! as Deck), [
        ('chien', 'dog', CardSource.import),
        ('chat', 'cat', CardSource.import),
      ]);
      await import.close();
    });

    testWidgets(
      "a section's form is remembered for its deck and topic, and not for another deck or topic",
      (tester) async {
        final import = await _Import.open(tester);
        await import.extractCards(words);
        await import.menu('빈출 숙어');
        await import.pickItem('Meaning → word');
        await import.tap(_shown('Add 3 cards'));

        await import.tap(_shown('open'));
        await import.extractCards(words);
        expect(_shown('Meaning → word'), findsOneWidget, reason: '빈출 숙어');
        expect(_shown('Word → meaning'), findsOneWidget, reason: '최빈출 단어');

        // Saved into Spanish, a form is Spanish's alone.
        await import.menu('최빈출 단어');
        await import.pickItem('Both ways');
        await import.tap(_shown('French'));
        await import.tap(_shown('Spanish'));
        await import.tap(_shown('Add 5 cards'));

        await import.tap(_shown('open'));
        await import.extractCards(words);
        expect(_shown('Both ways'), findsNothing, reason: "French's forms");
        expect(_shown('Meaning → word'), findsOneWidget);
        await import.tap(_shown('French'));
        await import.tap(_shown('Spanish'));
        expect(_shown('Both ways'), findsOneWidget, reason: "Spanish's forms");
        await import.close();
      },
    );

    testWidgets(
      'candidates of one card key on the photo are one row with their senses, and a card with no topic goes under This page',
      (tester) async {
        final import = await _Import.open(tester);
        await import.extractCards([
          CandidateCard.word(front: 'run', meaning: '달리다', partOfSpeech: '[동]'),
          CandidateCard.word(
            front: 'Run',
            meaning: '경영하다',
            partOfSpeech: '[동]',
          ),
        ]);

        expect(_shown('Found 1 word'), findsOneWidget);
        expect(_shown('This page 1'), findsOneWidget);
        expect(_shown('[동] 달리다\n[동] 경영하다'), findsOneWidget);
        await import.close();
      },
    );

    testWidgets('with nothing to add, the add button is disabled', (
      tester,
    ) async {
      final import = await _Import.open(tester);
      await import.extract({'a': '1'});

      await import.tap(import.check('a'));

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add 0 cards'),
      );
      expect(button.onPressed, isNull);
      await import.close();
    });

    testWidgets(
      'retake offers the camera and the album again; a cancel keeps the list, a photo replaces it',
      (tester) async {
        final import = await _Import.open(tester);
        await import.extract({'a': '1'});
        await import.tap(import.check('a'));

        await import.tap(_shown('Retake'));
        import.photos.cameraPhoto = null;
        await import.tap(_shown('Take photo'));
        expect(_shown('Found 1 word'), findsOneWidget);
        expect(import.included('a'), isFalse, reason: 'kept as it was');
        expect(import.client.calls, hasLength(1));

        import.photos.cameraPhoto = testPhoto;
        await import.tap(_shown('Retake'));
        await import.extract({'b': '2', 'c': '3'});
        expect(_shown('Found 2 words'), findsOneWidget);
        expect(_shown('a'), findsNothing);
        expect(await import.cards(import.french), isEmpty);
        await import.close();
      },
    );

    testWidgets(
      'cancel closes the list, writes nothing and pops with nothing',
      (tester) async {
        final import = await _Import.open(tester, deck: (_) => null);
        await import.extract({'a': '1'});

        await import.tap(_shown('Cancel'));

        expect(import.hasPopped, isTrue);
        expect(import.popped, isNull);
        expect(await import.deckNames(), ['French', 'Spanish']);
        await import.close();
      },
    );

    testWidgets(
      'a deck that cannot be read says so in a snack bar, and the list opens with no row marked as held',
      (tester) async {
        final import = await _Import.open(
          tester,
          french: {'chat': 'cat'},
          before: (import) =>
              import.repository.unreadable.add(import.french.id),
        );
        await import.extract({'chat': 'talk'});

        expect(
          _shown(
            "Couldn't read or write the device's storage. Please try again.",
          ),
          findsOneWidget,
        );
        expect(_shown('Found 1 word'), findsOneWidget);
        expect(import.included('chat'), isTrue);
        await import.close();
      },
    );
  });

  group('edit sheet', () {
    final face = [
      const CandidateCard(
        front: 'face',
        kind: CardKind.vocabulary,
        senses: [
          Sense(pos: '[동]', meaning: '직면하다'),
          Sense(pos: '[명]', meaning: '표면'),
          Sense(pos: '[명]', meaning: '얼굴'),
        ],
      ),
    ];

    testWidgets(
      "a tap opens the sheet with the front and each sense; Done applies the edits and a dismissal none",
      (tester) async {
        final import = await _Import.open(tester);
        await import.extractCards(face);

        await import.tap(_shown('face'));
        expect(_shown('Edit card'), findsOneWidget);
        expect(find.byType(TextField), findsNWidgets(4));
        await tester.enterText(find.byType(TextField).at(2), '겉면');
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();
        expect(
          _shown('[동] 직면하다\n[명] 표면\n[명] 얼굴'),
          findsOneWidget,
          reason: 'dismissed',
        );

        await import.tap(_shown('face'));
        await tester.enterText(find.byType(TextField).first, 'faces');
        await tester.enterText(find.byType(TextField).at(2), '겉면');
        await import.tap(_shown('Done'));
        expect(_shown('faces'), findsOneWidget);
        expect(_shown('[동] 직면하다\n[명] 겉면\n[명] 얼굴'), findsOneWidget);
        await import.close();
      },
    );

    testWidgets(
      'a sense dropped leaves the card, and with every sense dropped Done is disabled',
      (tester) async {
        final import = await _Import.open(tester);
        await import.extractCards(face);

        await import.tap(_shown('face'));
        await import.tap(find.byType(Checkbox).at(1));
        await import.tap(_shown('Done'));
        expect(_shown('[동] 직면하다\n[명] 얼굴'), findsOneWidget);

        await import.tap(_shown('face'));
        for (final i in [0, 2]) {
          await import.tap(find.byType(Checkbox).at(i));
        }
        final done = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Done'),
        );
        expect(done.onPressed, isNull);
        // Control: one sense kept again.
        await import.tap(find.byType(Checkbox).at(2));
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Done'))
              .onPressed,
          isNotNull,
        );
        await import.close();
      },
    );

    testWidgets('a sense dragged by its handle moves, and the card follows', (
      tester,
    ) async {
      final import = await _Import.open(tester);
      await import.extractCards(face);

      await import.tap(_shown('face'));
      final handle = find.bySemanticsLabel('Move meaning 3');
      await tester.drag(handle, const Offset(0, -300));
      await tester.pumpAndSettle();
      await import.tap(_shown('Done'));

      expect(_shown('[명] 얼굴\n[동] 직면하다\n[명] 표면'), findsOneWidget);
      await import.tap(_shown('Add 1 card'));
      expect(await import.cards(import.french), [
        ('face', '[명] 얼굴 / [동] 직면하다 / [명] 표면', CardSource.import),
      ]);
      await import.close();
    });

    testWidgets("a note's sheet edits its back", (tester) async {
      final import = await _Import.open(tester);
      await import.extractCards(const [
        CandidateCard(front: '양성모음', answer: 'ㅏ ㅗ', topic: '모음조화'),
      ]);

      await import.tap(_shown('양성모음'));
      expect(find.byType(Checkbox), findsNothing);
      await tester.enterText(find.byType(TextField).last, 'ㅏ ㅗ ㅑ ㅛ');
      await import.tap(_shown('Done'));

      expect(_shown('ㅏ ㅗ ㅑ ㅛ'), findsOneWidget);
      await import.close();
    });

    testWidgets(
      "an edit whose front the deck holds keeps the row, marked, and merges it into the deck's card",
      (tester) async {
        final import = await _Import.open(tester, french: {'chat': 'cat'});
        await import.extract({'chien': 'dog'});

        await import.tap(_shown('chien'));
        await tester.enterText(find.byType(TextField).first, 'chat');
        await import.tap(_shown('Done'));

        expect(import.included('chat'), isTrue);
        expect(_shown('Already in the deck'), findsOneWidget);
        await import.tap(_shown('Add 1 card'));
        expect(await import.cards(import.french), [
          ('chat', 'cat / dog', CardSource.manual),
        ]);
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
        'the source sheet, extracting, the list with a row left out and a row held, its form menu, the edit sheet, the deck sheet, a failure and a refusal meet the guidelines in ${mode.name}',
        (tester) async {
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
          import.client.answer({
            'chat': 'talk',
            'chien': 'dog',
            'cheval': 'horse',
          });
          await tester.pumpAndSettle();
          await import.tap(import.check('cheval'));
          expect(_shown('Already in the deck'), findsOneWidget);
          expect(_shown('Add 1 card'), findsOneWidget);
          await check();
          await import.menu('This page');
          expect(find.byType(MenuItemButton), findsWidgets);
          await check();
          await tester.tapAt(Offset.zero);
          await tester.pumpAndSettle();
          await import.tap(_shown('dog'));
          expect(_shown('Edit card'), findsOneWidget);
          await check();
          await import.tap(_shown('Done'));
          await import.tap(_shown('French'));
          expect(_shown('Add to'), findsOneWidget);
          await check();
          await import.tap(_shown('Spanish'));
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
        },
      );
    }

    testWidgets(
      "a screen reader hears each row's sides and its check's state, and taps either",
      (tester) async {
        final import = await _Import.open(tester);
        await import.extract({'chien': 'dog'});

        expect(
          tester.getSemantics(find.bySemanticsLabel('chien, dog. Tap to edit')),
          matchesSemantics(
            label: 'chien, dog. Tap to edit',
            isButton: true,
            hasTapAction: true,
          ),
        );
        expect(
          tester.getSemantics(import.check('chien')),
          matchesSemantics(
            label: 'Include chien',
            hasCheckedState: true,
            isChecked: true,
            hasTapAction: true,
          ),
        );
        tester.semantics.tap(find.semantics.byLabel('Include chien'));
        await tester.pumpAndSettle();
        expect(import.included('chien'), isFalse);
        tester.semantics.tap(find.semantics.byLabel('chien, dog. Tap to edit'));
        await tester.pumpAndSettle();
        expect(_shown('Edit card'), findsOneWidget);
        await import.close();
      },
    );
  });
}

/// The text on screen that reads [text] once its word joiners are left out.
Finder _shown(String text) => find.byWidgetPredicate(
  (widget) => widget is Text && widget.data?.replaceAll('\u2060', '') == text,
);
