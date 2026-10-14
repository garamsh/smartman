import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/shared/database.dart';
import 'package:smartman/study/src/model.dart';
import 'package:smartman/study/src/rust/api/engine.dart';
import 'package:smartman/study/src/scheduler.dart';
import 'package:smartman/study/src/session.dart';
import 'package:smartman/study/src/study_repository.dart';

/// The engine's own answer for [state] reviewed with [answer] at [at],
/// asked through the bridge directly.
Future<Scheduled> _engine(CardState state, Answer answer, DateTime at) =>
    reviewCard(
      state: MemoryStateParts(
        stability: state.stability,
        difficulty: state.difficulty,
        lastReview: state.lastReview.millisecondsSinceEpoch ~/ 1000,
      ),
      answer: answer,
      at: at.millisecondsSinceEpoch ~/ 1000,
    );

void _expectStored(CardState stored, Scheduled expected) {
  expect(stored.stability, expected.state.stability);
  expect(stored.difficulty, expected.state.difficulty);
  expect(
    stored.lastReview.millisecondsSinceEpoch ~/ 1000,
    expected.state.lastReview,
  );
  expect(stored.due.millisecondsSinceEpoch ~/ 1000, expected.due);
}

Future<void> _untilLoaded(StudySession session) {
  final loaded = Completer<void>();
  void check() {
    if (session.state is! SessionLoading && !loaded.isCompleted) {
      loaded.complete();
    }
  }

  session.addListener(check);
  check();
  return loaded.future.whenComplete(() => session.removeListener(check));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Scheduler scheduler;
  setUpAll(() async => scheduler = await Scheduler.load());

  test('a corrected Know is rescheduled as a Don\'t know from the state before it, at the same time', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final firstSeen = DateTime.utc(2026, 10, 1, 9);
    final now = DateTime.utc(2026, 10, 14, 9);
    var ids = 0;
    final cards = DeckRepository(
      db,
      clock: () => firstSeen,
      newId: () => 'id${ids++}',
    );
    final repository = StudyRepository(db, newId: () => 'review${ids++}');
    final deck = await cards.createDeck('French');
    final card = switch (await cards.addCard(
      deck.id,
      front: const [TextContent('chat')],
      back: const [TextContent('cat')],
    )) {
      CardSaved(:final card) => card,
      DuplicateFront() => fail('the deck was empty'),
    };
    final firstReview = Review(
      id: repository.newReviewId(),
      cardId: card.id,
      answer: Answer.know,
      reviewedAt: firstSeen,
      duration: const Duration(seconds: 2),
    );
    await repository.record(
      firstReview,
      await scheduler.review(null, Answer.know, firstSeen),
    );
    final before = (await repository.statesOf([card.id]))[card.id]!;
    expect(before.due.isAfter(now), isFalse, reason: 'the card must be due');

    final failures = <Object>[];
    final session = StudySession(
      deckId: deck.id,
      cards: cards,
      repository: repository,
      scheduler: scheduler,
      clock: () => now,
      onFailure: failures.add,
    );
    addTearDown(session.dispose);
    await _untilLoaded(session);
    expect((session.state as SessionStudying).current.id, card.id);

    // Control: the uncorrected answer is the engine's Know from the same state.
    session.answer(Answer.know);
    await session.settled;
    final know = await _engine(before, Answer.know, now);
    _expectStored((await repository.statesOf([card.id]))[card.id]!, know);

    session.correctPrevious();
    await session.settled;
    final dontKnow = await _engine(before, Answer.dontKnow, now);
    expect(dontKnow.due, isNot(know.due));
    _expectStored((await repository.statesOf([card.id]))[card.id]!, dontKnow);

    // The correction replaced the session's review rather than adding one.
    final reviews = await db.select(db.reviews).get();
    expect(reviews, hasLength(2));
    final corrected = reviews.singleWhere(
      (review) => review.id != firstReview.id.value,
    );
    expect(corrected.rating, 'again');
    expect(corrected.reviewedAt.isAtSameMomentAs(now), isTrue);
    expect(failures, isEmpty);
  });
}
