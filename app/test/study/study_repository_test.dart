import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart' show CardId;
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

  test('the answers between two times are the live ones from the first up to the second, each marked when it is its card\'s first live answer', () async {
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
    await answer('at the end', day.add(const Duration(days: 1)));

    final between = await study.answersBetween(
      day,
      day.add(const Duration(days: 1)),
    );

    expect(
      [for (final answer in between) (answer.at, answer.first)],
      [
        (day.add(const Duration(hours: 1)), false),
        (day.add(const Duration(hours: 2)), true),
        (day.add(const Duration(hours: 3)), false),
        (day.add(const Duration(hours: 4)), true),
      ],
    );
  });

  test('the latest answers before a time are each named card\'s last live one before it, for those that have one', () async {
    await answer('a', day.subtract(const Duration(days: 2)));
    await answer('a', day.subtract(const Duration(days: 1)));
    await answer('a', day.add(const Duration(hours: 1)));
    await answer('b', day.subtract(const Duration(hours: 1)), deleted: true);
    await answer('c', day.subtract(const Duration(hours: 3)));

    final latest = await study.latestAnswersBefore([
      const CardId('a'),
      const CardId('b'),
    ], day);

    expect(latest, {const CardId('a'): day.subtract(const Duration(days: 1))});
    expect(await study.latestAnswersBefore(const [], day), isEmpty);
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
