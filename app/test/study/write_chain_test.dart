import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/shared/database.dart';
import 'package:smartman/study/src/model.dart';
import 'package:smartman/study/src/rust/api/engine.dart';
import 'package:smartman/study/src/scheduler.dart';
import 'package:smartman/study/src/session.dart';
import 'package:smartman/study/src/study_repository.dart';

import 'fixtures.dart';

/// Schedules every review one day out, except the first, for which it
/// throws an error that is not a `StudyFailure`.
class _FirstCallBreaks implements Scheduler {
  final unexpected = StateError('engine state lost');
  var _calls = 0;

  @override
  Future<CardState> review(
    CardState? state,
    Answer answer,
    DateTime at, {
    required FuzzFactor fuzz,
  }) async {
    if (_calls++ == 0) throw unexpected;
    return CardState(
      stability: 1,
      difficulty: 5,
      lastReview: at,
      due: at.add(const Duration(days: 1)),
    );
  }
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

  test('an unexpected error in one write is reported, and later answers are still recorded', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var created = DateTime.utc(2026, 10, 1);
    var ids = 0;
    final cards = DeckRepository(
      db,
      clock: () => created = created.add(const Duration(minutes: 1)),
      newId: () => 'id${ids++}',
    );
    final deck = await cards.createDeck('French');
    final cardIds = <CardId>[];
    for (final name in ['a', 'b', 'c']) {
      final saved = await cards.addCard(
        deck.id,
        front: [TextContent(name)],
        back: [TextContent(name)],
      );
      cardIds.add(switch (saved) {
        CardSaved(:final card) => card.id,
        DuplicateFront() => fail('the deck held no duplicate'),
      });
    }
    final scheduler = _FirstCallBreaks();
    final repository = StudyRepository(db, newId: () => 'review${ids++}');

    final reported = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previousHandler);

    final failures = <Object>[];
    final session = StudySession(
      decks: DeckSelection(deck.id),
      cards: cards,
      repository: repository,
      scheduler: scheduler,
      clock: () => DateTime.utc(2026, 10, 14, 9),
      random: FirstDraw(),
      onFailure: failures.add,
    );
    addTearDown(session.dispose);
    await _untilLoaded(session);
    expect((session.state as SessionStudying).current.id, cardIds.first);

    session.answer(Answer.know);
    session.answer(Answer.know);
    session.answer(Answer.know);
    await session.settled;
    // The failing write was the first card's, so it alone has no state.

    expect(
      [for (final details in reported) details.exception],
      [scheduler.unexpected],
    );
    // Control: the answers after the failed one reached the database.
    final stored = await repository.statesOf(cardIds);
    expect(stored.keys, unorderedEquals([cardIds[1], cardIds[2]]));
    expect(failures, isEmpty);
  });
}
