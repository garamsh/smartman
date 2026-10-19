import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/study/src/model.dart';
import 'package:smartman/study/src/overview.dart';
import 'package:smartman/study/src/queue.dart';
import 'package:smartman/study/src/rust/api/engine.dart';
import 'package:smartman/study/src/scheduler.dart';
import 'package:smartman/study/src/session.dart';
import 'package:smartman/study/src/today.dart';
import 'package:smartman/study/src/study_repository.dart';

import 'fixtures.dart';

/// Schedules every review one day out, at once.
class _InstantScheduler implements Scheduler {
  @override
  Future<CardState?> fold(List<ReviewRow> reviews) =>
      throw UnimplementedError('sessions do not fold');

  @override
  Future<List<CardState>> history(List<ReviewRow> reviews) =>
      throw UnimplementedError('sessions do not fold');

  @override
  Future<double> retrievability(CardState state, DateTime at) =>
      throw UnimplementedError('sessions read no recall');

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

/// UTC as the device's time zone.
Duration _utc(DateTime _) => Duration.zero;

/// 09:00 UTC on 14 October, five hours into the study day.
final _now = DateTime.utc(2026, 10, 14, 9);

/// A deck holding a card for each of [names], in a database of its own.
class _Deck {
  _Deck._(this.db, this.cards, this.study, this.id);

  final AppDatabase db;
  final DeckRepository cards;
  final StudyRepository study;
  final DeckId id;

  static Future<_Deck> open(List<String> names) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var created = DateTime.utc(2026, 9, 1);
    var ids = 0;
    final cards = DeckRepository(
      db,
      clock: () => created = created.add(const Duration(minutes: 1)),
      newId: () => 'id${ids++}',
    );
    final deck = await cards.createDeck('French');
    await StudyRepository(
      db,
      newId: () => 'setting',
    ).setDailyMinutes(5, at: created);
    for (final name in names) {
      await cards.addCard(
        deck.id,
        front: [TextContent(name)],
        back: [TextContent(name)],
      );
    }
    return _Deck._(
      db,
      cards,
      StudyRepository(db, newId: () => 'review${ids++}'),
      deck.id,
    );
  }

  /// A session opened at [_now] in UTC over [decks], this deck's by
  /// default, drawing from [random].
  Future<StudySession> session([Random? random, DeckSelection? decks]) async {
    final session = StudySession(
      decks: decks ?? DeckSelection(id),
      cards: cards,
      repository: study,
      scheduler: _InstantScheduler(),
      clock: () => _now,
      random: random ?? FirstDraw(),
      onFailure: (failure) => fail('unexpected $failure'),
      offsetAt: _utc,
    );
    addTearDown(session.dispose);
    // Runs before the database closes: the writes still queued need it.
    addTearDown(() => session.settled);
    await untilLoaded(session);
    return session;
  }

  /// The card of this database whose front reads [front].
  Future<Card> card(String front) async {
    for (final deck in await cards.watchDecks().first) {
      for (final card in await cards.listCards(deck.id)) {
        if (plainText(card.front) == front) return card;
      }
    }
    throw StateError('no card reads $front');
  }

  /// Stores an answer of "Know" to the card reading [front] at [at].
  Future<void> answer(String front, DateTime at) async {
    final card = await this.card(front);
    await study.record(
      card.id,
      [
        Review(
          id: study.newReviewId(),
          cardId: card.id,
          answer: Answer.know,
          reviewedAt: at,
          duration: Duration.zero,
          fuzzFactor: FuzzFactor.draw(FirstDraw()),
        ),
      ],
      CardState(
        stability: 1,
        difficulty: 5,
        lastReview: at,
        due: at.add(const Duration(days: 1)),
      ),
      at: at,
    );
  }

  /// Every stored review and card state, as rows.
  Future<(List<ReviewRow>, List<CardStateRow>)> rows() async =>
      (await db.select(db.reviews).get(), await db.select(db.cardStates).get());
}

/// The front of the card on screen.
String _current(StudySession session) => switch (session.state) {
  SessionStudying(:final current) => plainText(current.front),
  final state => fail('no card is on screen: $state'),
};

const _know = Answer.know;
const _dontKnow = Answer.dontKnow;

/// The day's new cards: the 5 daily minutes [_Deck] stores, at 10 s a card,
/// the pace while too few answers are stored. A deck of more cards stops short
/// of them.
const _today = 30;

/// The fronts of a deck of [count] cards, created oldest first.
List<String> _names(int count) => [
  for (var i = 0; i < count; i++) 'c${i.toString().padLeft(2, '0')}',
];

/// Answers "Know" to each card on screen until none is.
void _answerAll(StudySession session) {
  while (session.state is SessionStudying) {
    session.answer(_know);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('past today\'s cards, 학습하기 goes on with the next new cards oldest first, each answer written and counted', () async {
    final deck = await _Deck.open(_names(_today + 2));
    final session = await deck.session();
    _answerAll(session);
    await session.settled;

    final complete = session.state;
    expect(complete, isA<SessionComplete>());
    expect((complete as SessionComplete).more, isTrue);
    expect(complete.progress.total, _today);
    // Control: today's cards alone are written so far.
    expect((await deck.rows()).$1, hasLength(_today));

    session.studyOn();
    expect(_current(session), 'c${_today.toString().padLeft(2, '0')}');
    session.answer(_know);
    expect(_current(session), 'c${(_today + 1).toString().padLeft(2, '0')}');
    session.answer(_know);
    await session.settled;

    final done = session.state as SessionComplete;
    expect(done.more, isFalse);
    expect((done.progress.done, done.progress.total), (_today + 2, _today + 2));
    final (reviews, states) = await deck.rows();
    expect(reviews, hasLength(_today + 2));
    expect(states, hasLength(_today + 2));
    // Recorded answers, so the day's goal counts them done.
    final stored = await deck.study.answersSince(DateTime.utc(2026, 10, 14, 4));
    final (cards, cardStates) = await readCards(
      DeckSelection(deck.id),
      deck.cards,
      deck.study,
    );
    final goal = DailyGoal.of(
      dayPlanOf(
        cards,
        cardStates,
        StudyDay.at(
          _now,
          firstAnswers: [for (final answer in stored) answer.at],
          newCards: _today,
          offsetAt: _utc,
        ),
        [
          for (final answer in stored)
            (card: answer.card, answer: answer.answer, at: answer.at),
        ],
      ),
    );
    expect((goal.done, goal.goal), (_today + 2, _today + 2));
  });

  test('past today\'s cards, a card answered today comes back only as the re-show after Don\'t know', () async {
    final deck = await _Deck.open(_names(_today + 2));
    final session = await deck.session();
    _answerAll(session);
    session.studyOn();

    final shown = <String>[];
    for (final answer in [_dontKnow, _know, _know]) {
      shown.add(_current(session));
      session.answer(answer);
    }
    final first = 'c${_today.toString().padLeft(2, '0')}';
    final second = 'c${(_today + 1).toString().padLeft(2, '0')}';
    expect(shown, [first, second, first]);
    expect(session.state, isA<SessionComplete>());
    expect((session.state as SessionComplete).more, isFalse);
  });

  test('a session opened with no card left today starts on the next new cards, its size holding no card, under the day\'s last card answered earlier', () async {
    final deck = await _Deck.open(_names(_today + 2));
    final first = await deck.session();
    // Control: a session with today's cards opens on them, sized, with no
    // earlier answer of the day.
    expect(first.size.cards, _today);
    expect((first.state as SessionStudying).earlier, isNull);
    _answerAll(first);
    await first.settled;

    final again = await deck.session();
    final state = again.state as SessionStudying;
    expect(
      plainText(state.current.front),
      'c${_today.toString().padLeft(2, '0')}',
    );
    expect(again.size.cards, 0);
    expect(state.earlier?.answer, Answer.know);
    // The day's count goes on from today's answered cards.
    expect((state.progress.done, state.progress.total), (_today, _today + 2));
  });

  test('with no new card left past today\'s, the completion card offers none and 학습하기 does nothing', () async {
    final deck = await _Deck.open(['a', 'b']);
    final session = await deck.session();
    _answerAll(session);
    final complete = session.state as SessionComplete;
    expect(complete.more, isFalse);

    session.studyOn();
    expect(session.state, isA<SessionComplete>());

    // Reopened, with both answered today, it opens on the completion card.
    await session.settled;
    final again = await deck.session();
    expect(again.state, isA<SessionComplete>());
    expect((again.state as SessionComplete).more, isFalse);
  });

  group("the day's last card from an earlier session", () {
    /// The front of the earlier answer [session] shows, or null.
    String? earlier(StudySession session) => switch (session.state) {
      SessionStudying(:final earlier) || SessionComplete(:final earlier) =>
        earlier == null ? null : plainText(earlier.card.front),
      _ => null,
    };

    test('is the last answer to a card still in the decks, not one to a card deleted since', () async {
      final deck = await _Deck.open(['a', 'b', 'c']);
      await deck.answer('a', DateTime.utc(2026, 10, 14, 6));
      await deck.answer('b', DateTime.utc(2026, 10, 14, 7));
      // Control: with b in the deck, its answer is the last.
      expect(earlier(await deck.session()), 'b');

      await deck.cards.deleteCard((await deck.card('b')).id);
      expect(earlier(await deck.session()), 'a');
    });

    test("is the last answer within the session's decks, not a later one in another deck", () async {
      final deck = await _Deck.open(['a', 'b']);
      final other = await deck.cards.createDeck('German');
      await deck.cards.addCard(
        other.id,
        front: [TextContent('z')],
        back: [TextContent('z')],
      );
      await deck.answer('a', DateTime.utc(2026, 10, 14, 6));
      await deck.answer('z', DateTime.utc(2026, 10, 14, 7));

      expect(earlier(await deck.session()), 'a');
      // Control: over both decks, the other deck's later answer is the last.
      expect(
        earlier(await deck.session(null, DeckSelection(deck.id, [other.id]))),
        'z',
      );
    });

    test(
      'is an answer from 04:00 today, not one at 03:59, the day before',
      () async {
        final deck = await _Deck.open(['a', 'b', 'c']);
        await deck.answer('a', DateTime.utc(2026, 10, 14, 3, 59));
        expect(earlier(await deck.session()), isNull);

        // Control: at 04:00 the answer is the day's.
        await deck.answer('b', DateTime.utc(2026, 10, 14, 4));
        expect(earlier(await deck.session()), 'b');
      },
    );
  });
}
