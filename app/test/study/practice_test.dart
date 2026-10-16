import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/study/src/model.dart';
import 'package:smartman/study/src/rust/api/engine.dart';
import 'package:smartman/study/src/scheduler.dart';
import 'package:smartman/study/src/session.dart';
import 'package:smartman/study/src/study_repository.dart';

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

  /// A session opened at [_now] in UTC, drawing from [random].
  Future<StudySession> session([Random? random]) async {
    final session = StudySession(
      decks: DeckSelection(id),
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

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('practice shows every card answered today, then the missed ones until each is answered right, then every card again', () async {
    final deck = await _Deck.open(['a', 'b', 'c', 'd']);
    final session = await deck.session();
    for (final _ in ['a', 'b', 'c', 'd']) {
      session.answer(_know);
    }
    expect(session.state, isA<SessionComplete>());

    session.practice();
    final shown = <String>[];
    void answer(Answer answer) {
      shown.add(_current(session));
      session.answer(answer);
    }

    // The pass over all, missing b and d.
    for (final choice in [_know, _dontKnow, _know, _dontKnow]) {
      answer(choice);
    }
    // The missed ones: b missed again comes back after d, then both right.
    for (final choice in [_dontKnow, _know, _know]) {
      answer(choice);
    }
    // Every card again.
    for (final _ in ['a', 'b', 'c', 'd']) {
      answer(_know);
    }

    expect(shown, ['a', 'b', 'c', 'd', 'b', 'd', 'b', 'a', 'b', 'c', 'd']);
    expect(_current(session), 'a', reason: 'and so on, until the user stops');
  });

  test('each practice pass is shuffled from the session source', () async {
    final orders = <String>{};
    for (var seed = 0; seed < 10; seed++) {
      final deck = await _Deck.open(['a', 'b', 'c', 'd', 'e', 'f']);
      final session = await deck.session(Random(seed));
      final answered = <String>[];
      while (session.state is SessionStudying) {
        answered.add(_current(session));
        session.answer(_know);
      }
      session.practice();
      final pass = <String>[];
      for (var index = 0; index < 6; index++) {
        pass.add(_current(session));
        session.answer(_know);
      }
      expect(pass, unorderedEquals(answered));
      orders.add(pass.join());
    }
    // Control: the passes differ between seeds.
    expect(orders.length, greaterThan(1));
  });

  test('practice answers and their toggles write nothing to the database; a written answer toggled during practice still does', () async {
    final deck = await _Deck.open(['a', 'b']);
    final session = await deck.session();
    session.answer(_know);
    session.answer(_dontKnow);
    session.answer(_know);
    await session.settled;
    final (reviews, states) = await deck.rows();
    expect(reviews, hasLength(3), reason: 'the setup wrote every answer');
    expect(states, hasLength(2));

    session.practice();
    session.answer(_dontKnow);
    session.answer(_know);
    session.answer(_know);
    session.toggle(3);
    await session.settled;

    final (practisedReviews, practisedStates) = await deck.rows();
    expect(practisedReviews, reviews);
    expect(practisedStates, states);

    // Control: toggling a written answer during practice rewrites it.
    session.toggle(0);
    await session.settled;
    final (toggled, _) = await deck.rows();
    expect(
      toggled.firstWhere((row) => row.id == reviews.first.id).rating,
      'again',
    );
  });

  test('practice answers do not count in the completion card', () async {
    final deck = await _Deck.open(['a']);
    final session = await deck.session();
    session.answer(_know);
    final before = (session.state as SessionComplete).completion;

    session.practice();
    session.answer(_dontKnow);
    session.answer(_know);

    // The completion card shows again only through a written answer, so its
    // counts are read from a fresh session over the same day.
    await session.settled;
    final reopened = await deck.session();
    final after = (reopened.state as SessionComplete).completion;
    expect(
      (after.knowCount, after.dontKnowCount, after.streak),
      (before.knowCount, before.dontKnowCount, before.streak),
    );
    expect((after.knowCount, after.dontKnowCount, after.streak), (1, 0, 1));
  });

  test('with no card left and none answered today, the session has nothing to study; with one answered today it opens on the completion card', () async {
    final deck = await _Deck.open(['a']);
    final card = (await deck.cards.listCards(deck.id)).single;
    // Answered yesterday, due again in a week.
    final yesterday = _now.subtract(const Duration(days: 1));
    await deck.study.record(
      card.id,
      [
        Review(
          id: deck.study.newReviewId(),
          cardId: card.id,
          answer: _know,
          reviewedAt: yesterday,
          duration: const Duration(seconds: 3),
          fuzzFactor: FuzzFactor.draw(FirstDraw()),
        ),
      ],
      CardState(
        stability: 7,
        difficulty: 5,
        lastReview: yesterday,
        due: yesterday.add(const Duration(days: 7)),
      ),
      at: yesterday,
    );

    final empty = await deck.session();
    expect(empty.state, isA<SessionEmpty>());
    empty.practice();
    expect(empty.state, isA<SessionEmpty>(), reason: 'nothing to practise');

    // Control: the same card answered this morning is practised from the
    // completion card, with the morning's answer counted.
    final morning = DateTime.utc(2026, 10, 14, 5);
    await deck.study.record(
      card.id,
      [
        Review(
          id: deck.study.newReviewId(),
          cardId: card.id,
          answer: _dontKnow,
          reviewedAt: morning,
          duration: const Duration(seconds: 90),
          fuzzFactor: FuzzFactor.draw(FirstDraw()),
        ),
      ],
      CardState(
        stability: 7,
        difficulty: 5,
        lastReview: morning,
        due: morning.add(const Duration(days: 7)),
      ),
      at: morning,
    );
    final complete = await deck.session();
    final completion = (complete.state as SessionComplete).completion;
    expect(
      (
        completion.knowCount,
        completion.dontKnowCount,
        completion.timeSpent,
        completion.streak,
      ),
      (0, 1, const Duration(seconds: 90), 2),
    );
    complete.practice();
    expect(_current(complete), 'a');
  });
}
