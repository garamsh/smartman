import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/account/account.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/study/study.dart';

import '../account/fake_account_service.dart';

/// The time the home screens' study reads: 09:00 on 15 October 2026, in a
/// zone at UTC, so the study day runs from 04:00 that day to 04:00 the next.
final homeNow = DateTime.utc(2026, 10, 15, 9);

/// What the home screens read beside the decks: a signed-in account, and
/// study over [db] at [homeNow], whose count never finishes reading when
/// [stalled]. Counting and opening a session schedule nothing, so the
/// scheduler is never called.
List<Override> homeOverrides(AppDatabase db, {bool stalled = false}) => [
  accountServiceProvider.overrideWithValue(
    FakeAccountService(
      const SignedIn(
        userId: UserId('00000000-0000-4000-8000-00000000000a'),
        email: 'ada@example.com',
      ),
    ),
  ),
  studyRepositoryProvider.overrideWithValue(
    stalled
        ? _StalledPace(db, newId: () => 'review${_reviews++}')
        : StudyRepository(db, newId: () => 'review${_reviews++}'),
  ),
  schedulerProvider.overrideWithValue(_UnusedScheduler()),
  studyClockProvider.overrideWithValue(() => homeNow),
  studyZoneProvider.overrideWithValue((_) => Duration.zero),
  studyRandomProvider.overrideWithValue((_) => Random(0)),
];

var _reviews = 0;

class _UnusedScheduler extends Fake implements Scheduler {}

/// A study repository whose read of the user's pace never completes.
class _StalledPace extends StudyRepository {
  _StalledPace(super.db, {required super.newId});

  @override
  Future<Duration?> medianReviewDuration() => Completer<Duration?>().future;
}

/// Stores a reviewed state for [card] that falls due at [due], after an
/// interval of [days] days.
Future<void> storeState(
  AppDatabase db,
  CardId card, {
  required DateTime due,
  int days = 3,
}) => db
    .into(db.cardStates)
    .insert(
      CardStatesCompanion.insert(
        cardId: card.value,
        stability: days.toDouble(),
        difficulty: 5,
        lastReview: due.subtract(Duration(days: days)),
        due: due,
        updatedAt: homeNow,
      ),
    );

/// Stores [count] answers of [card], each taking [duration], on the day
/// before [homeNow]'s study day, so they set the user's pace without taking
/// any of today's new cards.
Future<void> storeAnswers(
  AppDatabase db,
  CardId card,
  int count,
  Duration duration,
) async {
  for (var i = 0; i < count; i++) {
    await db
        .into(db.reviews)
        .insert(
          ReviewsCompanion.insert(
            id: 'answer${_reviews++}',
            cardId: card.value,
            rating: 'good',
            reviewedAt: DateTime.utc(2026, 10, 14, 9, i),
            durationMs: duration.inMilliseconds,
            fuzzFactor: const Value(0),
            updatedAt: homeNow,
          ),
        );
  }
}

/// A deck repository whose list of a deck's cards fails for each deck in
/// [unreadable], as a failing local database does.
class UnreadableDecks extends DeckRepository {
  UnreadableDecks(super.db, {required super.clock, required super.newId});

  final unreadable = <DeckId>{};

  @override
  Future<List<Card>> listCards(DeckId deck) async {
    if (unreadable.contains(deck)) {
      throw const StorageFailure(FormatException('unreadable'));
    }
    return super.listCards(deck);
  }
}

/// Stores one answer of [card] at [at], recorded as "Know".
Future<void> storeAnswerAt(AppDatabase db, CardId card, DateTime at) => db
    .into(db.reviews)
    .insert(
      ReviewsCompanion.insert(
        id: 'answer${_reviews++}',
        cardId: card.value,
        rating: 'good',
        reviewedAt: at,
        durationMs: 3000,
        fuzzFactor: const Value(0),
        updatedAt: at,
      ),
    );
