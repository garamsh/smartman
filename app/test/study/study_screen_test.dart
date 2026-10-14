import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/shared/database.dart';
import 'package:smartman/shared/l10n/app_localizations.dart';
import 'package:smartman/study/src/current_card.dart';
import 'package:smartman/study/src/model.dart';
import 'package:smartman/study/src/previous_cards.dart';
import 'package:smartman/study/src/providers.dart';
import 'package:smartman/study/src/rust/api/engine.dart';
import 'package:smartman/study/src/scheduler.dart';
import 'package:smartman/study/src/study_repository.dart';
import 'package:smartman/study/src/study_screen.dart';
import 'package:smartman/study/src/study_style.dart';

import 'fixtures.dart';

/// Schedules every review one day out, at once.
class _InstantScheduler implements Scheduler {
  @override
  Future<CardState> review(
    CardState? state,
    Answer answer,
    DateTime at, {
    required FuzzFactor fuzz,
  }) async => CardState(
    stability: 1,
    difficulty: 5,
    lastReview: at,
    due: at.add(const Duration(days: 1)),
  );
}

/// Reads no state and never finishes a write.
class _StalledRepository implements StudyRepository {
  var _ids = 0;
  final records = <CardId>[];

  @override
  ReviewId newReviewId() => ReviewId('review${_ids++}');

  @override
  Future<Map<CardId, CardState>> statesOf(List<CardId> cards) async => {};

  @override
  Future<void> record(CardId card, List<Review> reviews, CardState state) {
    records.add(card);
    return Completer<void>().future;
  }
}

/// A phone in portrait: 390 by 844 logical pixels.
const _phone = Size(390, 844);

class _Study {
  _Study(this.tester, this.db);

  final WidgetTester tester;
  final AppDatabase db;
  DateTime now = DateTime.utc(2026, 10, 14, 9);

  /// Drags the current card [dx] to the side over [duration], slowly enough
  /// that the release is no fling, then lets every animation finish.
  Future<void> swipe(
    double dx, {
    Duration elapsed = Duration.zero,
    Duration duration = const Duration(seconds: 1),
  }) async {
    now = now.add(elapsed);
    await tester.timedDrag(_currentCard, Offset(dx, 0), duration);
    await tester.pumpAndSettle();
  }

  Future<void> know({Duration elapsed = Duration.zero}) =>
      swipe(200, elapsed: elapsed);

  Future<void> dontKnow({Duration elapsed = Duration.zero}) =>
      swipe(-200, elapsed: elapsed);

  /// The front of the card under study, or null when none is.
  String? get current {
    final fronts = find.descendant(
      of: _currentCard,
      matching: find.textContaining(RegExp(r'^\w+ front$')),
    );
    return fronts.evaluate().isEmpty
        ? null
        : (fronts.evaluate().single.widget as Text).data;
  }
}

final _currentCard = find.byType(CurrentCard);

/// Opens a study session over a deck holding a card for each of [cards],
/// created oldest first, with "name front" and "name back" as its sides unless
/// [sides] gives them.
Future<_Study> _open(
  WidgetTester tester,
  List<String> cards, {
  Map<String, (List<Content>, List<Content>)> sides = const {},
  StudyRepository Function(AppDatabase db)? repository,
  Map<String, CardState> states = const {},
  Size size = _phone,
  double textScale = 1,
  bool disableAnimations = false,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = AppDatabase(NativeDatabase.memory());
  var created = DateTime.utc(2026, 9, 1);
  var ids = 0;
  final deckRepository = DeckRepository(
    db,
    clock: () => created = created.add(const Duration(minutes: 1)),
    newId: () => 'id${ids++}',
  );
  final studyRepository =
      (repository ??
      (db) => StudyRepository(db, newId: () => 'review${ids++}'))(db);
  final seeding = StudyRepository(db, newId: () => 'seed${ids++}');
  final deck = (await tester.runAsync(() async {
    final deck = await deckRepository.createDeck('French');
    for (final name in cards) {
      final (front, back) =
          sides[name] ??
          ([TextContent('$name front')], [TextContent('$name back')]);
      final saved = await deckRepository.addCard(
        deck.id,
        front: front,
        back: back,
      );
      if (saved case CardSaved(:final card) when states.containsKey(name)) {
        await seeding.record(card.id, [
          Review(
            id: seeding.newReviewId(),
            cardId: card.id,
            answer: Answer.know,
            reviewedAt: states[name]!.lastReview,
            duration: Duration.zero,
            fuzzFactor: FuzzFactor.draw(FirstDraw()),
          ),
        ], states[name]!);
      }
    }
    return deck;
  }))!;
  final study = _Study(tester, db);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deckRepositoryProvider.overrideWithValue(deckRepository),
        studyRepositoryProvider.overrideWithValue(studyRepository),
        schedulerProvider.overrideWithValue(_InstantScheduler()),
        studyClockProvider.overrideWithValue(() => study.now),
        studyRandomProvider.overrideWithValue((_) => FirstDraw()),
      ],
      child: MaterialApp(
        navigatorKey: navigator,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
        home: const Scaffold(),
      ),
    ),
  );
  unawaited(
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => StudyScreen(decks: DeckSelection(deck.id)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return study;
}

/// The previous card whose front reads [front].
Finder _previous(String front) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label?.startsWith('Front: $front. Back:') ?? false),
  skipOffstage: false,
);

String? _label(WidgetTester tester, Finder finder) =>
    tester.widget<Semantics>(finder).properties.label;

/// The card's horizontal offset from its place.
double _dragOffset(WidgetTester tester, Finder card) => tester
    .widget<Transform>(
      find.descendant(of: card, matching: find.byType(Transform)).first,
    )
    .transform
    .getTranslation()
    .x;

final _answerVisibility = find.descendant(
  of: _currentCard,
  matching: find.byType(Visibility),
);

bool _answerShown(WidgetTester tester) =>
    tester.widget<Visibility>(_answerVisibility).visible;

const _sentence =
    'This sentence is long enough to wrap across the width of half a card. ';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
    'the screen shows the top bar and the current card at about 57% of its height, and nothing else',
    (tester) async {
      final study = await _open(tester, ['a', 'b']);

      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final card = tester.getRect(_currentCard);
      expect(card.width, _phone.width - 2 * StudyStyle.cardMargin);
      expect(card.height, closeTo(StudyStyle.currentMinHeight, 0.01));
      expect(card.center.dy, closeTo(_phone.height * 0.57, 1));
      expect(find.byType(VerticalDivider), findsOneWidget);
      // Every text on screen: the card's sides, of which the back is hidden,
      // and the count. No deck name, button, hint or next card.
      expect(
        {
          for (final element in find.byType(Text).evaluate())
            (element.widget as Text).data,
        },
        {'a front', 'a back', '0 / 2'},
      );
      expect(_answerShown(tester), isFalse);
      expect(find.byType(ButtonStyleButton), findsNothing);
      expect(study.current, 'a front');
    },
  );

  testWidgets('a tap shows the answer half and a second tap hides it', (
    tester,
  ) async {
    await _open(tester, ['a']);

    await tester.tap(_currentCard);
    await tester.pump();
    expect(_answerShown(tester), isTrue);

    await tester.tap(_currentCard);
    await tester.pump();
    expect(_answerShown(tester), isFalse);
  });

  testWidgets(
    "a swipe right past the threshold answers Know and a swipe left Don't know",
    (tester) async {
      final study = await _open(tester, ['a', 'b', 'c']);

      await study.swipe(StudyStyle.commitDistance + 10);
      expect(study.current, 'b front');
      expect(_label(tester, _previous('a front')), endsWith('Answer: Know'));

      await study.swipe(-(StudyStyle.commitDistance + 10));
      expect(study.current, 'c front');
      expect(
        _label(tester, _previous('b front')),
        endsWith("Answer: Don't know"),
      );
      expect(find.text('2 / 3'), findsOneWidget);
    },
  );

  testWidgets(
    'a drag short of the threshold springs back in both directions and answers nothing',
    (tester) async {
      final study = await _open(tester, ['a', 'b']);

      for (final dx in [
        StudyStyle.commitDistance - 10,
        -(StudyStyle.commitDistance - 10),
      ]) {
        final gesture = await tester.startGesture(
          tester.getCenter(_currentCard),
        );
        for (var moved = 0; moved < 10; moved++) {
          await gesture.moveBy(Offset(dx / 10, 0), timeStamp: Duration.zero);
          await tester.pump(const Duration(milliseconds: 100));
        }
        // The card follows the finger and shows the answer it would give.
        expect(_dragOffset(tester, _currentCard), closeTo(dx, 0.01));
        expect(find.text(dx > 0 ? 'Know' : "Don't know"), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 300));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(_dragOffset(tester, _currentCard), 0);
        expect(study.current, 'a front');
        expect(_previous('a front'), findsNothing);
      }
    },
  );

  testWidgets('a short fling commits in its direction', (tester) async {
    final study = await _open(tester, ['a', 'b', 'c']);

    await tester.fling(_currentCard, const Offset(-60, 0), 1500);
    await tester.pumpAndSettle();
    expect(study.current, 'b front');
    expect(
      _label(tester, _previous('a front')),
      endsWith("Answer: Don't know"),
    );

    // Control: the same distance without the speed springs back.
    await study.swipe(60);
    expect(study.current, 'b front');
  });

  testWidgets(
    'long content grows the card to its cap and then scrolls inside each half',
    (tester) async {
      final long = [TextContent(_sentence * 12)];
      final medium = [TextContent(_sentence)];
      await _open(
        tester,
        ['long', 'medium'],
        sides: {'long': (long, long), 'medium': (medium, medium)},
      );

      final cap = _phone.height * StudyStyle.currentMaxHeightFraction;
      expect(tester.getSize(_currentCard).height, closeTo(cap, 1));
      expect(
        tester.getCenter(_currentCard).dy,
        closeTo(_phone.height * 0.57, 1),
      );
      final halves = find.descendant(
        of: _currentCard,
        matching: find.byType(Scrollable),
      );
      expect(halves, findsNWidgets(2));
      for (final half in halves.evaluate()) {
        final position = (half as StatefulElement).state as ScrollableState;
        expect(position.position.maxScrollExtent, greaterThan(0));
      }

      await tester.timedDrag(
        _currentCard,
        const Offset(200, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      // Control: one sentence grows the card without reaching the cap.
      final height = tester.getSize(_currentCard).height;
      expect(height, greaterThan(StudyStyle.currentMinHeight));
      expect(height, lessThan(cap));
    },
  );

  for (final (name, size, textScale) in [
    ('a narrow screen', const Size(320, 700), 1.0),
    ('a large text scale', _phone, 1.5),
  ]) {
    testWidgets('on $name the answer sits under the question', (tester) async {
      await _open(tester, ['a'], size: size, textScale: textScale);

      expect(
        find.descendant(of: _currentCard, matching: find.byType(Divider)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _currentCard,
          matching: find.byType(VerticalDivider),
        ),
        findsNothing,
      );
    });
  }

  testWidgets(
    'a previous card shows two lines of each side, and its whole content on long-press',
    (tester) async {
      final long = _sentence * 6;
      final study = await _open(
        tester,
        ['long', 'b'],
        sides: {
          'long': ([TextContent('long front $long')], [TextContent(long)]),
        },
      );
      await study.know();

      final paragraphs = tester
          .renderObjectList<RenderParagraph>(
            find.descendant(
              of: find.byType(PreviousCards),
              matching: find.byType(RichText),
            ),
          )
          .toList();
      expect(paragraphs, hasLength(2));
      for (final paragraph in paragraphs) {
        expect(paragraph.maxLines, 2);
        expect(paragraph.overflow, TextOverflow.ellipsis);
        expect(paragraph.didExceedMaxLines, isTrue);
      }

      await tester.longPress(_previous('long front $long'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('long front $long'),
        ),
        findsOneWidget,
      );
      expect(study.current, 'b front', reason: 'a long-press toggles nothing');
    },
  );

  testWidgets('a block this version cannot show renders as its placeholder', (
    tester,
  ) async {
    await _open(
      tester,
      ['a'],
      sides: {
        'a': (
          const [TextContent('a front'), UnsupportedContent('image', null)],
          const [TextContent('a back')],
        ),
      },
    );

    expect(
      find.descendant(
        of: _currentCard,
        matching: find.text('[Content this version cannot show: image]'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'every answer of the session stays in one opaque, receding stack, and the first can be scrolled to and toggled',
    (tester) async {
      final names = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
      final study = await _open(tester, [...names, 'i']);
      for (final _ in names) {
        await study.know();
      }

      final stack = find.byType(PreviousCards);
      final scrollable = find.descendant(
        of: stack,
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      // Every answer is reached in the one scroll view, newest to oldest, and
      // read as it comes into view.
      final colors = <Color>[];
      final scales = <double>[];
      final blurred = <bool>[];
      for (final name in names.reversed) {
        final card = _previous('$name front');
        await tester.scrollUntilVisible(card, -50, scrollable: scrollable);
        await tester.pumpAndSettle();
        colors.add(
          (tester
                      .widget<AnimatedContainer>(
                        find.descendant(
                          of: card,
                          matching: find.byType(AnimatedContainer),
                        ),
                      )
                      .decoration!
                  as BoxDecoration)
              .color!,
        );
        scales.add(
          tester
              .widget<AnimatedScale>(
                find.ancestor(of: card, matching: find.byType(AnimatedScale)),
              )
              .scale,
        );
        blurred.add(
          find
              .descendant(of: card, matching: find.byType(ImageFiltered))
              .evaluate()
              .isNotEmpty,
        );
        // Opaque: no translucent layer once the stack has settled.
        expect(
          tester
              .widgetList<Opacity>(
                find.descendant(of: stack, matching: find.byType(Opacity)),
              )
              .where((opacity) => opacity.opacity < 1),
          isEmpty,
        );
      }
      expect(colors.every((color) => color.a == 1), isTrue);
      // Depth, newest first: white and sharp, then greyer, smaller and
      // blurred, down to the floor scale; past the depth cap, unblurred.
      expect(colors.first, StudyStyle.cardColor);
      expect(colors.last, isNot(StudyStyle.cardColor));
      expect(
        scales,
        orderedEquals(List<double>.of(scales)..sort((a, b) => b.compareTo(a))),
      );
      expect(scales.last, StudyStyle.depthScaleFloor);
      expect(blurred, [false, true, true, true, true, true, false, false]);

      await tester.tap(_previous('a front'));
      await tester.pumpAndSettle();

      expect(
        _label(tester, _previous('a front')),
        "Front: a front. Back: a back. Answer: Don't know. Changed",
      );
      expect(
        find.descendant(
          of: _previous('a front'),
          matching: find.text('Changed'),
        ),
        findsOneWidget,
      );
      Color dot(String name) =>
          (tester
                      .widget<Container>(
                        find.descendant(
                          of: _previous('$name front'),
                          matching: find.byWidgetPredicate(
                            (widget) =>
                                widget is Container &&
                                widget.constraints?.maxWidth ==
                                    StudyStyle.dotSize,
                          ),
                        ),
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;
      expect(dot('a'), StudyStyle.dontKnowColor);
      expect(dot('b'), StudyStyle.knowColor);
      // Control: the untouched answer still reads as given.
      expect(
        find.descendant(
          of: _previous('b front'),
          matching: find.text('Changed'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'with reduce motion the card does not fly off and the next one cross-fades in',
    (tester) async {
      final study = await _open(tester, ['a', 'b'], disableAnimations: true);

      await tester.timedDrag(
        _currentCard,
        const Offset(200, 0),
        const Duration(seconds: 1),
      );
      await tester.pump();

      // Both cards are on screen, fading, neither moved nor scaled by the
      // transition.
      expect(_currentCard, findsNWidgets(2));
      for (final card in _currentCard.evaluate()) {
        expect(
          find.ancestor(
            of: find.byWidget(card.widget),
            matching: find.byType(FadeTransition),
          ),
          findsWidgets,
        );
        expect(
          find.ancestor(
            of: find.byWidget(card.widget),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Transform &&
                  !widget.transform.isIdentity() &&
                  widget is! RotatedBox,
            ),
          ),
          findsNothing,
        );
      }
      await tester.pumpAndSettle();
      expect(study.current, 'b front');
    },
  );

  testWidgets(
    'without reduce motion the answered card flies off before the next one emerges',
    (tester) async {
      final study = await _open(tester, ['a', 'b']);

      await tester.timedDrag(
        _currentCard,
        const Offset(200, 0),
        const Duration(seconds: 1),
      );
      await tester.pump(StudyStyle.flyDuration ~/ 2);

      expect(_currentCard, findsOneWidget);
      expect(_dragOffset(tester, _currentCard), greaterThan(200));
      await tester.pumpAndSettle();
      expect(study.current, 'b front');
    },
  );

  testWidgets(
    'a screen reader answers the current card through its actions and reads its labels',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _open(tester, ['a', 'b', 'c'], locale: const Locale('ko'));

      expect(
        tester.getSemantics(_currentCard),
        isSemantics(label: '앞면: a front', hasTapAction: true),
      );
      expect([
        for (final id
            in tester
                .getSemantics(_currentCard)
                .getSemanticsData()
                .customSemanticsActionIds!)
          CustomSemanticsAction.getAction(id)!.label,
      ], containsAll(['안다', '모른다']));
      tester.semantics.tap(find.semantics.byLabel('앞면: a front'));
      await tester.pump();
      expect(
        tester.getSemantics(_currentCard),
        isSemantics(label: '앞면: a front. 뒷면: a back'),
      );

      Future<void> act(String action) async {
        final node = tester.getSemantics(_currentCard);
        node.owner!.performAction(
          node.id,
          SemanticsAction.customAction,
          CustomSemanticsAction.getIdentifier(
            CustomSemanticsAction(label: action),
          ),
        );
        await tester.pumpAndSettle();
      }

      await act('모른다');
      await act('안다');

      expect(
        find.semantics
            .byLabel('앞면: a front. 뒷면: a back. 답: 모른다')
            .evaluate()
            .single,
        isSemantics(
          isButton: true,
          hasTapAction: true,
          hasLongPressAction: true,
        ),
      );
      expect(
        find.semantics
            .byLabel('앞면: b front. 뒷면: b back. 답: 안다')
            .evaluate()
            .single,
        isSemantics(isButton: true, hasTapAction: true),
      );
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    },
  );

  testWidgets(
    'the next card is on screen once the answer is given, while its write is still running',
    (tester) async {
      final stalled = _StalledRepository();
      final study = await _open(tester, [
        'a',
        'b',
        'c',
      ], repository: (_) => stalled);

      await study.know();

      expect(study.current, 'b front');
      expect(stalled.records, [const CardId('id1')]);
      await study.know();
      expect(study.current, 'c front');
    },
  );

  testWidgets(
    'the summary takes the card\'s place and counts cards, answers and time',
    (tester) async {
      final study = await _open(tester, ['a', 'b']);

      await study.dontKnow(elapsed: const Duration(seconds: 10));
      await study.know(elapsed: const Duration(seconds: 10));
      expect(study.current, 'a front');
      await study.know(elapsed: const Duration(seconds: 45));

      expect(find.text('Session complete'), findsOneWidget);
      expect(find.text('2 cards studied'), findsOneWidget);
      expect(find.text('Know: 2'), findsOneWidget);
      expect(find.text("Don't know: 1"), findsOneWidget);
      expect(find.text('Time spent: 1 min 5 s'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);

      // The stack stays, and toggling its last answer studies the card again.
      await tester.tap(
        find.byWidget(tester.widgetList(_previous('a front')).last),
      );
      await tester.pumpAndSettle();
      expect(find.text('Session complete'), findsNothing);
      expect(study.current, 'a front');
    },
  );

  testWidgets('a deck with nothing due and no new card opens on the summary', (
    tester,
  ) async {
    final study = await _open(
      tester,
      ['later'],
      states: {'later': dueTomorrow},
    );

    // The card exists and was left out because it is not due.
    final stored = await tester.runAsync(
      () => study.db.select(study.db.cardStates).get(),
    );
    expect(stored, hasLength(1));
    expect(find.text('Session complete'), findsOneWidget);
    expect(find.text('Nothing to study right now.'), findsOneWidget);
    expect(find.text('0 cards studied'), findsOneWidget);
    expect(study.current, isNull);
  });

  testWidgets('an answer the storage fails to write is reported to the user', (
    tester,
  ) async {
    final study = await _open(tester, ['a', 'b']);
    // Deleting the card makes the review's foreign key fail on write.
    final deleted = await tester.runAsync(
      () => (study.db.delete(
        study.db.cards,
      )..where((card) => card.id.equals('id1'))).go(),
    );
    expect(deleted, 1);

    await study.know();
    expect(study.current, 'b front');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(
      find.text(
        "Couldn't save your answer on this device. This card's schedule did not change.",
      ),
      findsOneWidget,
    );
  });

  for (final (name, leave) in [
    ('going back', (WidgetTester tester) => tester.binding.handlePopRoute()),
    (
      'the close button',
      (WidgetTester tester) => tester.tap(find.byTooltip('Close')),
    ),
  ]) {
    testWidgets(
      '$name mid-session shows the summary without the stack, and tap targets carry labels',
      (tester) async {
        final study = await _open(tester, ['a', 'b', 'c']);
        await study.know();
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

        await leave(tester);
        await tester.pumpAndSettle();

        expect(find.text('Session complete'), findsOneWidget);
        expect(find.text('1 card studied'), findsOneWidget);
        expect(_previous('a front'), findsNothing);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.byType(StudyScreen), findsNothing);
      },
    );
  }
}

final dueTomorrow = CardState(
  stability: 3,
  difficulty: 5,
  lastReview: DateTime.utc(2026, 10, 12),
  due: DateTime.utc(2026, 10, 15),
);
