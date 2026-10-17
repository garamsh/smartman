import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/l10n/app_localizations.dart';
import 'package:smartman/study/src/current_card.dart';
import 'package:smartman/study/src/model.dart';
import 'package:smartman/study/src/previous_card.dart';
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
  Future<CardState?> fold(List<ReviewRow> reviews) =>
      throw UnimplementedError('sessions do not fold');

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
  Future<void> record(
    CardId card,
    List<Review> reviews,
    CardState state, {
    required DateTime at,
  }) {
    records.add(card);
    return Completer<void>().future;
  }

  @override
  Future<Duration?> medianReviewDuration() async => null;

  @override
  Future<List<DateTime>> firstAnswersSince(DateTime since) async => [];

  @override
  Future<List<StoredAnswer>> answersSince(DateTime since) async => [];

  @override
  Future<DateTime?> latestAnswerBefore(DateTime end) async => null;
}

/// Schedules as [_InstantScheduler] does, and keeps every answer it is asked
/// to schedule, in order.
class _RecordingScheduler extends _InstantScheduler {
  final answers = <Answer>[];

  @override
  Future<CardState> review(
    CardState? state,
    Answer answer,
    DateTime at, {
    required FuzzFactor fuzz,
  }) {
    answers.add(answer);
    return super.review(state, answer, at, fuzz: fuzz);
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

/// The current card's semantics, without the answer buttons'.
final _cardNode = find
    .descendant(of: _currentCard, matching: find.byType(Semantics))
    .first;

/// The current card's face, without the answer buttons under it.
final _face = find
    .descendant(of: _currentCard, matching: find.byType(GestureDetector))
    .first;

/// Opens a study session over a deck holding a card for each of [cards],
/// created oldest first, with "name front" and "name back" as its sides unless
/// [sides] gives them.
Future<_Study> _open(
  WidgetTester tester,
  List<String> cards, {
  Map<String, (List<Content>, List<Content>)> sides = const {},
  StudyRepository Function(AppDatabase db)? repository,
  Scheduler? scheduler,
  Map<String, CardState> states = const {},
  bool returning = false,
  Size size = _phone,
  double textScale = 1,
  bool disableAnimations = false,
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
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
        await seeding.record(
          card.id,
          [
            Review(
              id: seeding.newReviewId(),
              cardId: card.id,
              answer: Answer.know,
              reviewedAt: states[name]!.lastReview,
              duration: Duration.zero,
              fuzzFactor: FuzzFactor.draw(FirstDraw()),
            ),
          ],
          states[name]!,
          at: DateTime.utc(2026, 9, 1),
        );
      }
    }
    if (returning) {
      // An answer stored in another deck, so this is not the user's first
      // session.
      final other = await deckRepository.createDeck('Spanish');
      final saved = await deckRepository.addCard(
        other.id,
        front: [const TextContent('seen front')],
        back: [const TextContent('seen back')],
      );
      if (saved case CardSaved(:final card)) {
        await seeding.record(
          card.id,
          [
            Review(
              id: seeding.newReviewId(),
              cardId: card.id,
              answer: Answer.know,
              reviewedAt: dueTomorrow.lastReview,
              duration: Duration.zero,
              fuzzFactor: FuzzFactor.draw(FirstDraw()),
            ),
          ],
          dueTomorrow,
          at: DateTime.utc(2026, 9, 1),
        );
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
        schedulerProvider.overrideWithValue(scheduler ?? _InstantScheduler()),
        studyClockProvider.overrideWithValue(() => study.now),
        studyZoneProvider.overrideWithValue((_) => Duration.zero),
        studyRandomProvider.overrideWithValue((_) => FirstDraw()),
      ],
      child: MaterialApp(
        navigatorKey: navigator,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode,
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

/// The vertical centre of the half of a split card that holds [text].
double _halfCenter(WidgetTester tester, Finder text) => tester
    .getRect(find.ancestor(of: text, matching: find.byType(Expanded)).first)
    .center
    .dy;

/// The previous card on screen.
final _previousCard = find.byType(PreviousCardView);

/// The fronts of every previous card built, and "current" when the current
/// card is.
List<String> _built(WidgetTester tester) => [
  for (final element
      in find
          .byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                (widget.properties.label?.contains('. Answer: ') ?? false),
            skipOffstage: false,
          )
          .evaluate())
    RegExp(r'^Front: (.*?)\. Back:')
        .firstMatch((element.widget as Semantics).properties.label!)![1]!,
  if (_currentCard.evaluate().isNotEmpty) 'current',
];

/// The height each card takes on a 390 by 844 screen with no insets: half
/// the space between the top bar and the answer buttons, less the gaps.
final _cardHeight =
    (_phone.height -
        StudyStyle.topBarHeight -
        StudyStyle.topGap -
        StudyStyle.cardGap -
        StudyStyle.answerRow -
        StudyStyle.currentBottomGap) /
    2;

/// Performs the screen reader's custom action [label] on [finder]'s node.
Future<void> _act(WidgetTester tester, Finder finder, String label) async {
  final node = tester.getSemantics(finder);
  node.owner!.performAction(
    node.id,
    SemanticsAction.customAction,
    CustomSemanticsAction.getIdentifier(CustomSemanticsAction(label: label)),
  );
  await tester.pumpAndSettle();
}

const _sentence =
    'This sentence is long enough to wrap across the width of half a card. ';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
    'the screen shows the top bar, the current card in the lower of the two card places and the answer buttons under it, and nothing else',
    (tester) async {
      final study = await _open(tester, ['a', 'b'], returning: true);

      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final card = tester.getRect(_face);
      expect(card.width, _phone.width - 2 * StudyStyle.cardMargin);
      expect(card.height, closeTo(_cardHeight, 0.01));
      expect(
        card.top,
        closeTo(
          StudyStyle.topBarHeight +
              StudyStyle.topGap +
              _cardHeight +
              StudyStyle.cardGap,
          0.01,
        ),
      );
      expect(find.byType(VerticalDivider), findsOneWidget);
      // Every text on screen: the card's sides, of which the back is hidden
      // behind an eye, the count, and the answer buttons. No deck name, hint
      // or next card.
      expect(
        {
          for (final element in find.byType(Text).evaluate())
            (element.widget as Text).data,
        },
        {'a front', 'a back', '0/2', "Don't know", 'Know'},
      );
      expect(_answerShown(tester), isFalse);
      expect(
        find.descendant(of: _currentCard, matching: find.byType(Icon)),
        findsWidgets,
      );
      // The buttons sit under the card, "Don't know" left and "Know" right.
      final buttons = find.byType(TextButton);
      expect(buttons, findsNWidgets(2));
      expect(
        tester.getRect(find.text("Don't know")).top,
        greaterThan(card.bottom),
      );
      expect(
        tester.getCenter(find.text("Don't know")).dx,
        lessThan(tester.getCenter(find.text('Know')).dx),
      );
      for (final button in buttons.evaluate()) {
        expect(
          tester.getSize(find.byWidget(button.widget)).height,
          greaterThanOrEqualTo(AppSize.tapTarget),
        );
      }
      expect(study.current, 'a front');
    },
  );

  testWidgets('the answer buttons answer the current card', (tester) async {
    final study = await _open(tester, ['a', 'b', 'c']);

    await tester.tap(find.widgetWithText(TextButton, 'Know'));
    await tester.pumpAndSettle();
    expect(study.current, 'b front');
    expect(_label(tester, _previous('a front')), endsWith('Answer: Know'));

    await tester.tap(find.widgetWithText(TextButton, "Don't know"));
    await tester.pumpAndSettle();
    expect(study.current, 'c front');
    expect(
      _label(tester, _previous('b front')),
      endsWith("Answer: Don't know"),
    );
  });

  testWidgets(
    'on the first session a guide of two lines holds the previous card\'s place, until the first answer',
    (tester) async {
      final guide = [
        'Try to recall it first, then tap the card to see the answer',
        "Swipe right if you know it, left if you don't",
      ];
      final study = await _open(tester, ['a', 'b', 'c']);

      for (final line in guide) {
        expect(find.text(line), findsOneWidget);
        expect(
          tester.getRect(find.text(line)).bottom,
          lessThan(tester.getRect(_currentCard).top),
        );
      }
      // The line on pulling down for earlier cards is gone.
      expect(find.textContaining('earlier cards'), findsNothing);
      await study.know();
      for (final line in guide) {
        expect(find.text(line), findsNothing);
      }
      expect(_previous('a front'), findsOneWidget);
      await study.know();
      for (final line in guide) {
        expect(find.text(line), findsNothing);
      }

      // Control: a user with an answer stored before sees no guide.
      await _open(tester, ['d'], returning: true);
      for (final line in guide) {
        expect(find.text(line), findsNothing);
      }
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
      expect(find.text('2/3'), findsOneWidget);
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
        expect(
          find.descendant(
            of: _face,
            matching: find.text(dx > 0 ? 'Know' : "Don't know"),
          ),
          findsOneWidget,
        );
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
    'long content scrolls inside each half of the current card, which keeps its size whatever its content',
    (tester) async {
      final long = [TextContent(_sentence * 12)];
      // A few lines at the question's size, which fit the card.
      final medium = [
        const TextContent('This line wraps across a few lines here and there.'),
      ];
      await _open(
        tester,
        ['long', 'medium'],
        sides: {'long': (long, long), 'medium': (medium, medium)},
        returning: true,
      );

      expect(tester.getSize(_face).height, closeTo(_cardHeight, 0.01));
      final halves = find.descendant(
        of: _currentCard,
        matching: find.byType(Scrollable),
      );
      expect(halves, findsNWidgets(2));
      for (final half in halves.evaluate()) {
        final position = (half as StatefulElement).state as ScrollableState;
        expect(position.position.maxScrollExtent, greaterThan(0));
      }
      // Long text starts at the top of its half, below the padding.
      final text = find.descendant(
        of: _currentCard,
        matching: find.text(_sentence * 12),
      );
      expect(
        tester.getRect(text.first).top,
        closeTo(tester.getRect(halves.first).top + StudyStyle.cardPadding, 1),
      );

      await tester.timedDrag(
        _currentCard,
        const Offset(200, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      // Control: a few lines fit, at the same size, and scroll nothing.
      expect(tester.getSize(_face).height, closeTo(_cardHeight, 0.01));
      for (final half in halves.evaluate()) {
        final position = (half as StatefulElement).state as ScrollableState;
        expect(position.position.maxScrollExtent, 0);
      }
    },
  );

  for (final (name, size, textScale) in [
    ('a narrow screen', const Size(320, 700), 1.0),
    ('a large text scale', _phone, 1.5),
  ]) {
    testWidgets(
      'on $name the answer sits under the question, each in its centred half',
      (tester) async {
        await _open(tester, ['a'], size: size, textScale: textScale);

        final divider = find.descendant(
          of: _currentCard,
          matching: find.byType(Divider),
        );
        expect(divider, findsOneWidget);
        expect(
          tester.getCenter(divider).dy,
          closeTo(tester.getCenter(_face).dy, 1),
        );
        final question = find.text('a front');
        expect(
          tester.getCenter(question).dy,
          closeTo(_halfCenter(tester, question), 1),
        );
        expect(
          tester.getCenter(question).dy,
          lessThan(tester.getCenter(divider).dy),
        );
        expect(
          find.descendant(
            of: _currentCard,
            matching: find.byType(VerticalDivider),
          ),
          findsNothing,
        );
      },
    );
  }

  testWidgets(
    'a previous card shrinks long sides as far as their floors, then cuts them, and a tap shows the whole card in a sheet with no action',
    (tester) async {
      final long = _sentence * 12;
      final study = await _open(
        tester,
        ['long', 'b'],
        sides: {
          'long': ([TextContent('long front $long')], [TextContent(long)]),
        },
      );
      await study.know();

      // The two sides; the grade's chip is the third paragraph.
      final paragraphs = tester
          .renderObjectList<RenderParagraph>(
            find.descendant(of: _previousCard, matching: find.byType(RichText)),
          )
          .where((paragraph) => paragraph.maxLines != null)
          .toList();
      expect(paragraphs, hasLength(2));
      for (final (paragraph, floor) in [
        (paragraphs[0], AppType.questionFloor),
        (paragraphs[1], AppType.answerFloor),
      ]) {
        expect(paragraph.text.style!.fontSize, floor);
        expect(paragraph.overflow, TextOverflow.ellipsis);
        expect(paragraph.didExceedMaxLines, isTrue);
        // Cut to the lines that fit inside its half.
        expect(
          paragraph.size.height,
          lessThanOrEqualTo(
            tester.getSize(_previousCard).height - 2 * StudyStyle.cardPadding,
          ),
        );
      }

      await tester.tap(_previous('long front $long'));
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('long front $long')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text(long)),
        findsOneWidget,
      );
      // The answer is changed by a swipe, not from the sheet.
      expect(
        find.descendant(of: sheet, matching: find.byType(ButtonStyleButton)),
        findsNothing,
      );
      expect(study.current, 'b front', reason: 'a tap changes nothing');
      expect(
        _label(tester, _previous('long front $long')),
        endsWith('Answer: Know'),
      );
    },
  );

  testWidgets(
    'short text keeps its full size, centred in each half of the current card and of the previous card',
    (tester) async {
      // Words narrow enough for each half at full size in the test font.
      final study = await _open(
        tester,
        ['a', 'b'],
        sides: {
          'a': ([const TextContent('cat')], [const TextContent('chat')]),
          'b': ([const TextContent('dog')], [const TextContent('chien')]),
        },
      );
      await study.know();
      await tester.tap(_currentCard);
      await tester.pumpAndSettle();

      for (final (card, front, back) in [
        (_currentCard, 'dog', 'chien'),
        (_previousCard, 'cat', 'chat'),
      ]) {
        for (final (side, size) in [
          (front, AppType.question.fontSize),
          (back, AppType.answer.fontSize),
        ]) {
          final text = find.descendant(of: card, matching: find.text(side));
          expect(
            tester.getCenter(text).dy,
            closeTo(_halfCenter(tester, text), 1),
            reason: side,
          );
          expect(
            tester.renderObject<RenderParagraph>(text).text.style!.fontSize,
            size,
            reason: side,
          );
        }
      }
    },
  );

  testWidgets(
    'the screen holds exactly the previous card and the current card, the same size, and a vertical drag reaches no earlier card',
    (tester) async {
      final names = ['a', 'b', 'c', 'd', 'e', 'f'];
      final study = await _open(tester, [...names, 'g', 'h']);
      for (final _ in names) {
        await study.know();
      }

      expect(_built(tester), ['f front', 'current']);
      final previous = tester.getRect(_previousCard);
      final current = tester.getRect(_face);
      expect(previous.size, current.size);
      expect(current.height, closeTo(_cardHeight, 0.01));
      expect(previous.bottom, lessThan(current.top));
      expect(
        find.descendant(of: _previousCard, matching: find.text('f back')),
        findsOneWidget,
      );

      // Control: the screen took the answers, which a pull down would once
      // have reached.
      for (final dy in [300.0, -300.0]) {
        await tester.drag(_previousCard, Offset(0, dy));
        await tester.pumpAndSettle();
        expect(_built(tester), ['f front', 'current']);
        expect(tester.getRect(_previousCard), previous);
        expect(tester.getRect(_face), current);
      }
      expect(study.current, 'g front');
    },
  );

  testWidgets(
    'a horizontal drag on the previous card changes its answer and writes the corrected replay, and neither card moves with a drag on the other',
    (tester) async {
      final scheduler = _RecordingScheduler();
      final study = await _open(tester, [
        'a',
        'b',
        'c',
        'd',
      ], scheduler: scheduler);
      await study.know();
      await study.know();
      scheduler.answers.clear();

      // Toward "Know", the answer it has: it follows a quarter as far and
      // nothing changes.
      var gesture = await tester.startGesture(tester.getCenter(_previousCard));
      for (var moved = 0; moved < 10; moved++) {
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        _dragOffset(tester, _previousCard),
        closeTo(200 * StudyStyle.sameAnswerResistance, 0.01),
      );
      expect(find.text("Change to Don't know"), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_label(tester, _previous('b front')), endsWith('Answer: Know'));
      expect(scheduler.answers, isEmpty);

      // Dragged left, it shows what it would become behind it, and the
      // current card stays where it is.
      gesture = await tester.startGesture(tester.getCenter(_previousCard));
      for (var moved = 0; moved < 10; moved++) {
        await gesture.moveBy(const Offset(-15, 0));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(_dragOffset(tester, _previousCard), closeTo(-150, 0.01));
      expect(_dragOffset(tester, _currentCard), 0);
      expect(find.text("Change to Don't know"), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        _label(tester, _previous('b front')),
        endsWith("Answer: Don't know. Changed"),
      );
      expect(find.text("Change to Don't know"), findsNothing);
      expect(_dragOffset(tester, _previousCard), 0);
      expect(study.current, 'c front');
      // The card's session answers, replayed as they stand, are written.
      expect(scheduler.answers, [Answer.dontKnow]);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      final reviews = await tester.runAsync(
        () => study.db.select(study.db.reviews).get(),
      );
      expect(
        {for (final review in reviews!) review.cardId: review.rating},
        {'id1': 'good', 'id2': 'again'},
      );

      // Control: a drag on the current card moves it alone, and answers it.
      gesture = await tester.startGesture(tester.getCenter(_face));
      for (var moved = 0; moved < 10; moved++) {
        await gesture.moveBy(const Offset(15, 0));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(_dragOffset(tester, _currentCard), closeTo(150, 0.01));
      expect(_dragOffset(tester, _previousCard), 0);
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_label(tester, _previous('c front')), endsWith('Answer: Know'));
    },
  );

  testWidgets(
    'a screen reader changes a previous answer through the card\'s action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final study = await _open(tester, ['a', 'b', 'c']);
      await study.know();
      await _act(tester, _previous('a front'), "Change to Don't know");
      expect(
        _label(tester, _previous('a front')),
        endsWith("Answer: Don't know. Changed"),
      );

      await study.dontKnow();
      await _act(tester, _previous('b front'), 'Change to Know');
      expect(
        _label(tester, _previous('b front')),
        endsWith('Answer: Know. Changed'),
      );
      semantics.dispose();
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
    'each previous card shows its grade by its colour and by a chip naming it, and its label names it',
    (tester) async {
      final study = await _open(tester, ['a', 'b', 'c']);

      for (final (name, answer, fill, line, chip) in [
        (
          'a',
          'Know',
          AppColors.light.knowCard,
          AppColors.light.knowLine,
          AppColors.light.know,
        ),
        (
          'b',
          "Don't know",
          AppColors.light.dontKnowCard,
          AppColors.light.dontKnowLine,
          AppColors.light.dontKnowText,
        ),
      ]) {
        await (answer == 'Know' ? study.know() : study.dontKnow());
        final card = _previous('$name front');
        expect(
          _label(tester, card),
          'Front: $name front. Back: $name back. Answer: $answer',
        );
        final face =
            tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: card,
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        expect(face.color, fill, reason: name);
        expect((face.border! as Border).top.color, line, reason: name);
        final label = find.descendant(of: card, matching: find.text(answer));
        expect(label, findsOneWidget, reason: name);
        expect(
          (tester
                      .widget<Container>(
                        find
                            .ancestor(
                              of: label,
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration!
                  as ShapeDecoration)
              .color,
          chip,
          reason: name,
        );
      }
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

  for (final reduceMotion in [true, false]) {
    testWidgets(
      '${reduceMotion ? 'with' : 'without'} reduce motion a re-decided card ${reduceMotion ? 'settles at once' : 'springs back over time'}, and the card answered just now ${reduceMotion ? 'fades' : 'rises'} into the previous card\'s place',
      (tester) async {
        final study = await _open(tester, [
          'a',
          'b',
          'c',
        ], disableAnimations: reduceMotion);
        await study.know();

        await tester.timedDrag(
          _previousCard,
          const Offset(-200, 0),
          const Duration(seconds: 1),
        );
        await tester.pump();
        final moved = _dragOffset(tester, _previousCard);
        expect(moved, reduceMotion ? 0 : lessThan(0));
        await tester.pumpAndSettle();
        expect(
          _label(tester, _previous('a front')),
          endsWith("Answer: Don't know. Changed"),
        );

        await tester.tap(find.widgetWithText(TextButton, 'Know'));
        await tester.pump();
        // Past the answered card's flight, into the next cards' entrance.
        await tester.pump(
          reduceMotion ? Duration.zero : StudyStyle.flyDuration,
        );
        await tester.pump(StudyStyle.fadeDuration ~/ 2);
        final rising = find.ancestor(
          of: _previous('b front'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Transform && widget.transform.getTranslation().y > 0,
          ),
        );
        expect(rising, reduceMotion ? findsNothing : findsOneWidget);
        expect(
          find.ancestor(
            of: _previous('b front'),
            matching: find.byType(FadeTransition),
          ),
          findsWidgets,
        );
        await tester.pumpAndSettle();
        expect(_built(tester), ['b front', 'current']);
      },
    );
  }
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
        tester.getSemantics(_cardNode),
        isSemantics(label: '앞면: a front', hasTapAction: true),
      );
      expect([
        for (final id
            in tester
                .getSemantics(_cardNode)
                .getSemanticsData()
                .customSemanticsActionIds!)
          CustomSemanticsAction.getAction(id)!.label,
      ], containsAll(['안다', '모른다']));
      tester.semantics.tap(find.semantics.byLabel('앞면: a front'));
      await tester.pump();
      expect(
        tester.getSemantics(_cardNode),
        isSemantics(label: '앞면: a front. 뒷면: a back'),
      );

      Future<void> act(String action) async {
        final node = tester.getSemantics(_cardNode);
        node.owner!.performAction(
          node.id,
          SemanticsAction.customAction,
          CustomSemanticsAction.getIdentifier(
            CustomSemanticsAction(label: action),
          ),
        );
        await tester.pumpAndSettle();
      }

      String actions(String label) => [
        for (final id
            in find.semantics
                    .byLabel(label)
                    .evaluate()
                    .single
                    .getSemanticsData()
                    .customSemanticsActionIds ??
                <int>[])
          // The tap hint rides as an action with no label of its own.
          ?CustomSemanticsAction.getAction(id)!.label,
      ].join(', ');

      await act('모른다');
      expect(
        find.semantics
            .byLabel('앞면: a front. 뒷면: a back. 답: 모른다')
            .evaluate()
            .single,
        isSemantics(isButton: true, hasTapAction: true),
      );
      expect(actions('앞면: a front. 뒷면: a back. 답: 모른다'), '안다로 바꾸기');
      await act('안다');
      expect(actions('앞면: b front. 뒷면: b back. 답: 안다'), '모른다로 바꾸기');
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
    'once no card is left the completion card takes the current card\'s place, below the stack, with today\'s answers, time and streak',
    (tester) async {
      final study = await _open(tester, ['a', 'b']);

      await study.dontKnow(elapsed: const Duration(seconds: 10));
      await study.know(elapsed: const Duration(seconds: 10));
      expect(study.current, 'a front');
      await study.know(elapsed: const Duration(seconds: 45));

      expect(find.text('Done for today'), findsOneWidget);
      expect(_currentCard, findsNothing);
      expect(
        find.bySemanticsLabel("Know 2, don't know 1, 2 min, 1-day streak"),
        findsOneWidget,
      );
      expect(find.text('2/2'), findsOneWidget);
      // The previous card stays above the completion card.
      expect(
        tester.getRect(_previous('a front').last).bottom,
        lessThan(tester.getRect(find.text('Done for today')).top),
      );
      expect(find.text('Keep studying'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);

      // Changing the last answer to "Don't know" studies the card again.
      final semantics = tester.ensureSemantics();
      await _act(tester, _previous('a front').last, "Change to Don't know");
      semantics.dispose();
      expect(find.text('Done for today'), findsNothing);
      expect(study.current, 'a front');
    },
  );

  testWidgets(
    'keep studying goes on as practice in the same screen and route, and stop closes it',
    (tester) async {
      final study = await _open(tester, ['a', 'b']);
      await study.know();
      await study.know();
      final screen = tester.state(find.byType(StudyScreen));
      final route = ModalRoute.of(tester.element(find.byType(StudyScreen)));

      await tester.tap(find.text('Keep studying'));
      await tester.pumpAndSettle();

      expect(study.current, 'a front');
      expect(tester.state(find.byType(StudyScreen)), same(screen));
      expect(
        ModalRoute.of(tester.element(find.byType(StudyScreen))),
        same(route),
      );
      expect(route!.isCurrent, isTrue);
      expect(find.text('2/2'), findsOneWidget);
      await study.know();
      expect(study.current, 'b front');
      await study.know();
      expect(study.current, 'a front', reason: 'every card again');

      // Control: the completion card's other choice closes the screen.
      final other = await _open(tester, ['c']);
      await other.know();
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(find.byType(StudyScreen), findsNothing);
    },
  );

  testWidgets(
    'a deck with no card left today and none answered today says there is nothing to study',
    (tester) async {
      final study = await _open(
        tester,
        ['later'],
        states: {'later': dueTomorrow},
      );

      // The card exists and was left out because it is not due today.
      final stored = await tester.runAsync(
        () => study.db.select(study.db.cardStates).get(),
      );
      expect(stored, hasLength(1));
      expect(find.text('No cards to study today'), findsOneWidget);
      expect(find.text('Done for today'), findsNothing);
      expect(find.text('Keep studying'), findsNothing);
      expect(study.current, isNull);
    },
  );

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

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'in the ${mode.name} theme the current card, the stack and the summary meet the contrast and tap target guidelines',
      (tester) async {
        final study = await _open(tester, ['a', 'b', 'c'], themeMode: mode);
        expect(
          Theme.of(tester.element(_currentCard)).brightness,
          mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
        );
        await study.know();
        await study.dontKnow();
        await tester.tap(_currentCard);
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

        await tester.tap(_previous('b front'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);

        await study.know();
        await study.know();
        expect(find.text('Done for today'), findsOneWidget);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      },
    );
  }

  for (final (name, leave) in [
    ('going back', (WidgetTester tester) => tester.binding.handlePopRoute()),
    (
      'the close button',
      (WidgetTester tester) => tester.tap(find.byTooltip('Close')),
    ),
  ]) {
    testWidgets(
      '$name mid-session closes the screen, and the answers given are still written',
      (tester) async {
        final study = await _open(tester, ['a', 'b', 'c']);
        await study.know();
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

        await leave(tester);
        await tester.pumpAndSettle();

        expect(find.byType(StudyScreen), findsNothing);
        expect(find.text('Done for today'), findsNothing);
        final reviews = await tester.runAsync(
          () => study.db.select(study.db.reviews).get(),
        );
        expect(reviews, hasLength(1));
      },
    );
  }
}

/// Due at 05:00 UTC tomorrow, an hour after the next study day starts.
final dueTomorrow = CardState(
  stability: 3,
  difficulty: 5,
  lastReview: DateTime.utc(2026, 10, 12),
  due: DateTime.utc(2026, 10, 15, 5),
);
