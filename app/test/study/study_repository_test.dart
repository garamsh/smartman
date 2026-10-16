import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/study/src/study_repository.dart';

void main() {
  late AppDatabase db;
  late StudyRepository study;
  final day = DateTime.utc(2026, 10, 14, 4);

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    study = StudyRepository(db, newId: () => 'unused');
    await db
        .into(db.decks)
        .insert(
          DecksCompanion.insert(
            id: 'deck',
            name: 'French',
            createdAt: day,
            updatedAt: day,
          ),
        );
  });

  tearDown(() => db.close());

  var reviews = 0;

  /// Stores an answer to [card] at [at], creating the card on first use;
  /// tombstoned when [deleted].
  Future<void> answer(String card, DateTime at, {bool deleted = false}) async {
    await db
        .into(db.cards)
        .insertOnConflictUpdate(
          CardsCompanion.insert(
            id: card,
            deckId: 'deck',
            front: '[]',
            back: '[]',
            cardKey: card,
            source: 'manual',
            createdAt: day,
            updatedAt: day,
          ),
        );
    await db
        .into(db.reviews)
        .insert(
          ReviewsCompanion.insert(
            id: 'review ${reviews++}',
            cardId: card,
            rating: 'good',
            reviewedAt: at,
            durationMs: 1000,
            updatedAt: at,
            deletedAt: Value(deleted ? at : null),
          ),
        );
  }

  test('the first answers since a time are of the cards first answered then, live answers only', () async {
    await answer('new today', day.add(const Duration(hours: 2)));
    await answer('new today', day.add(const Duration(hours: 3)));
    await answer('answered before', day.subtract(const Duration(days: 1)));
    await answer('answered before', day.add(const Duration(hours: 1)));
    await answer(
      'deleted before',
      day.subtract(const Duration(days: 1)),
      deleted: true,
    );
    await answer('deleted before', day.add(const Duration(hours: 4)));
    await answer(
      'only deleted',
      day.add(const Duration(hours: 5)),
      deleted: true,
    );

    final first = await study.firstAnswersSince(day);

    expect(
      first,
      unorderedEquals([
        day.add(const Duration(hours: 2)),
        day.add(const Duration(hours: 4)),
      ]),
    );
    // Control: from a day earlier the card answered before counts too.
    expect(
      await study.firstAnswersSince(day.subtract(const Duration(days: 2))),
      hasLength(3),
    );
  });

  test('answers since a time come oldest first to the millisecond, from a time given in any zone', () async {
    final at = day.add(const Duration(minutes: 5));
    await answer('b', at.add(const Duration(milliseconds: 2)));
    await answer('a', at.add(const Duration(milliseconds: 1)));
    await answer('c', at.add(const Duration(milliseconds: 10)));
    await answer('before', at.subtract(const Duration(milliseconds: 1)));

    final since = await study.answersSince(at.toLocal());

    expect([for (final stored in since) stored.card.value], ['a', 'b', 'c']);
  });

  test(
    'the latest answer before a time is the last live one before it, or none',
    () async {
      await answer('a', day);
      await answer('b', day.add(const Duration(hours: 1)));
      await answer('c', day.add(const Duration(hours: 2)), deleted: true);

      expect(
        await study.latestAnswerBefore(day.add(const Duration(hours: 3))),
        day.add(const Duration(hours: 1)),
      );
      expect(
        await study.latestAnswerBefore(day.add(const Duration(hours: 1))),
        day,
      );
      expect(await study.latestAnswerBefore(day), isNull);
    },
  );
}
