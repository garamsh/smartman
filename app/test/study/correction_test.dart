import 'package:drift/drift.dart' show OrderingTerm, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/shared/database.dart';
import 'package:smartman/study/src/model.dart';
import 'package:smartman/study/src/rust/api/engine.dart';
import 'package:smartman/study/src/scheduler.dart';
import 'package:smartman/study/src/session.dart';
import 'package:smartman/study/src/study_repository.dart';

import 'fixtures.dart';

int _seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

/// The engine's own answer for a card in [before] (null for a new card)
/// reviewed with each of [history] in turn, asked through the bridge
/// directly, one `reviewCard` per review.
Future<Scheduled> _engine(
  CardState? before,
  List<(Answer, DateTime)> history,
) async {
  final (firstAnswer, firstAt) = history.first;
  var scheduled = before == null
      ? await reviewNewCard(answer: firstAnswer, at: _seconds(firstAt))
      : await reviewCard(
          state: MemoryStateParts(
            stability: before.stability,
            difficulty: before.difficulty,
            lastReview: _seconds(before.lastReview),
          ),
          answer: firstAnswer,
          at: _seconds(firstAt),
        );
  for (final (answer, at) in history.skip(1)) {
    scheduled = await reviewCard(
      state: scheduled.state,
      answer: answer,
      at: _seconds(at),
    );
  }
  return scheduled;
}

void _expectStored(CardState? stored, Scheduled expected) {
  expect(stored, isNotNull);
  expect(stored!.stability, expected.state.stability);
  expect(stored.difficulty, expected.state.difficulty);
  expect(_seconds(stored.lastReview), expected.state.lastReview);
  expect(_seconds(stored.due), expected.due);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Scheduler scheduler;
  setUpAll(() async => scheduler = await Scheduler.load());

  test('a toggled answer, either way and repeatedly, reschedules its card by replaying its session answers from its state before the session', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final firstSeen = DateTime.utc(2026, 10, 1, 9);
    var now = DateTime.utc(2026, 10, 14, 9);
    var ids = 0;
    final cards = DeckRepository(
      db,
      clock: () => firstSeen,
      newId: () => 'id${ids++}',
    );
    final repository = StudyRepository(db, newId: () => 'review${ids++}');
    final deck = await cards.createDeck('French');
    final added = <CardId>[];
    for (final word in ['chat', 'chien', 'oiseau', 'poisson']) {
      final saved = await cards.addCard(
        deck.id,
        front: [TextContent(word)],
        back: [TextContent(word)],
      );
      added.add(switch (saved) {
        CardSaved(:final card) => card.id,
        DuplicateFront() => fail('the deck held no duplicate'),
      });
    }
    final due = added.first;
    await repository.record(due, [
      Review(
        id: repository.newReviewId(),
        cardId: due,
        answer: Answer.know,
        reviewedAt: firstSeen,
        duration: const Duration(seconds: 2),
      ),
    ], await scheduler.review(null, Answer.know, firstSeen));
    final before = (await repository.statesOf([due]))[due]!;
    expect(before.due.isAfter(now), isFalse, reason: 'the card must be due');

    final failures = <Object>[];
    final session = StudySession(
      decks: DeckSelection(deck.id),
      cards: cards,
      repository: repository,
      scheduler: scheduler,
      clock: () => now,
      random: FirstDraw(),
      onFailure: failures.add,
    );
    addTearDown(session.dispose);
    await untilLoaded(session);

    // The due card first, then the new cards; its Don't know brings it back
    // after the three new cards.
    final times = <DateTime>[];
    for (final answer in [
      Answer.dontKnow,
      Answer.know,
      Answer.know,
      Answer.know,
      Answer.know,
    ]) {
      now = now.add(const Duration(minutes: 1));
      times.add(now);
      session.answer(answer);
    }
    await session.settled;
    final finished = session.state as SessionFinished;
    expect(
      [for (final card in finished.previous) card.card.id],
      [due, added[1], added[2], added[3], due],
    );
    final others = await repository.statesOf(added.sublist(1));

    // Control: the stored state before any toggle is the same replay.
    _expectStored(
      (await repository.statesOf([due]))[due],
      await _engine(before, [
        (Answer.dontKnow, times[0]),
        (Answer.know, times[4]),
      ]),
    );

    final toggles = [
      // The first answer, which a re-show follows.
      (0, [(Answer.know, times[0]), (Answer.know, times[4])]),
      (0, [(Answer.dontKnow, times[0]), (Answer.know, times[4])]),
      // The last answer, which reopens the session.
      (4, [(Answer.dontKnow, times[0]), (Answer.dontKnow, times[4])]),
      (0, [(Answer.know, times[0]), (Answer.dontKnow, times[4])]),
    ];
    for (final (position, history) in toggles) {
      session.toggle(position);
      await session.settled;
      _expectStored(
        (await repository.statesOf([due]))[due],
        await _engine(before, history),
      );
    }

    // Each of the card's session reviews holds its current answer, at its
    // original time; no review was added.
    final reviews =
        await (db.select(db.reviews)
              ..where((review) => review.cardId.equals(due.value))
              ..orderBy([(review) => OrderingTerm.asc(review.reviewedAt)]))
            .get();
    expect(
      [
        for (final review in reviews)
          (review.rating, _seconds(review.reviewedAt)),
      ],
      [
        ('good', _seconds(firstSeen)),
        ('good', _seconds(times[0])),
        ('again', _seconds(times[4])),
      ],
    );
    // No other card changed.
    expect(await repository.statesOf(added.sublist(1)), others);

    // A new card's toggle replays from no state.
    session.toggle(1);
    await session.settled;
    _expectStored(
      (await repository.statesOf([added[1]]))[added[1]],
      await _engine(null, [(Answer.dontKnow, times[1])]),
    );
    expect(failures, isEmpty);
  });
}
