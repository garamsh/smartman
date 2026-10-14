import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/shared/database.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('a new database matches the latest exported schema', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(GeneratedHelper.versions.last, db.schemaVersion);

    await verifier.migrateAndValidate(db, db.schemaVersion);
  });

  group('every exported schema migrates to the current schema', () {
    const versions = GeneratedHelper.versions;
    for (final fromVersion in versions) {
      test('from $fromVersion', () async {
        final schema = await verifier.schemaAt(fromVersion);
        final db = AppDatabase(schema.newConnection());
        addTearDown(db.close);

        await verifier.migrateAndValidate(db, db.schemaVersion);
      });
    }
  });

  test('decks, cards and reviews survive the upgrade from 1 to 2, which adds empty card states', () async {
    // Schema helpers hold a date as drift stores it: seconds since the epoch.
    final created = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch ~/ 1000;
    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, old) {
        batch.insert(
          old.decks,
          v1.DecksData(
            id: 'deck',
            name: 'French',
            createdAt: created,
            updatedAt: created,
          ),
        );
        batch.insert(
          old.cards,
          v1.CardsData(
            id: 'card',
            deckId: 'deck',
            front: '[]',
            back: '[]',
            cardKey: 'chat',
            source: 'manual',
            createdAt: created,
            updatedAt: created,
          ),
        );
        batch.insert(
          old.reviews,
          v1.ReviewsData(
            id: 'review',
            cardId: 'card',
            rating: 'good',
            reviewedAt: created,
            durationMs: 1200,
          ),
        );
      },
      validateItems: (db) async {
        expect((await db.select(db.decks).getSingle()).name, 'French');
        expect((await db.select(db.cards).getSingle()).cardKey, 'chat');
        final review = await db.select(db.reviews).getSingle();
        expect(
          [review.id, review.rating, review.durationMs],
          ['review', 'good', 1200],
        );
        expect(await db.select(db.cardStates).get(), isEmpty);
      },
    );
  });

  test('reviews and card states survive the upgrade from 2 to 3, each review without a fuzz factor', () async {
    // Schema helpers hold a date as drift stores it: seconds since the epoch.
    final created = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch ~/ 1000;
    await verifier.testWithDataIntegrity(
      oldVersion: 2,
      newVersion: 3,
      createOld: v2.DatabaseAtV2.new,
      createNew: v3.DatabaseAtV3.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, old) {
        batch.insert(
          old.decks,
          v2.DecksData(
            id: 'deck',
            name: 'French',
            createdAt: created,
            updatedAt: created,
          ),
        );
        batch.insert(
          old.cards,
          v2.CardsData(
            id: 'card',
            deckId: 'deck',
            front: '[]',
            back: '[]',
            cardKey: 'chat',
            source: 'manual',
            createdAt: created,
            updatedAt: created,
          ),
        );
        batch.insert(
          old.reviews,
          v2.ReviewsData(
            id: 'review',
            cardId: 'card',
            rating: 'good',
            reviewedAt: created,
            durationMs: 1200,
          ),
        );
        batch.insert(
          old.cardStates,
          v2.CardStatesData(
            cardId: 'card',
            stability: 2.3065,
            difficulty: 2.118,
            lastReview: created,
            due: created + 2 * 86400,
          ),
        );
      },
      validateItems: (db) async {
        final review = await db.select(db.reviews).getSingle();
        expect(
          [review.id, review.rating, review.durationMs, review.fuzzFactor],
          ['review', 'good', 1200, null],
        );
        final state = await db.select(db.cardStates).getSingle();
        expect([state.cardId, state.stability], ['card', 2.3065]);
      },
    );
  });

  test('a review row refuses a fuzz factor outside 0 to 1', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final at = DateTime.utc(2026, 10, 1);
    await db
        .into(db.decks)
        .insert(
          DecksCompanion.insert(
            id: 'deck',
            name: 'French',
            createdAt: at,
            updatedAt: at,
          ),
        );
    await db
        .into(db.cards)
        .insert(
          CardsCompanion.insert(
            id: 'card',
            deckId: 'deck',
            front: '[]',
            back: '[]',
            cardKey: 'chat',
            source: 'manual',
            createdAt: at,
            updatedAt: at,
          ),
        );
    ReviewsCompanion review(String id, double factor) =>
        ReviewsCompanion.insert(
          id: id,
          cardId: 'card',
          rating: 'good',
          reviewedAt: at,
          durationMs: 1200,
          fuzzFactor: Value(factor),
        );

    for (final factor in [-0.1, 1.0]) {
      await expectLater(
        db.into(db.reviews).insert(review('refused $factor', factor)),
        throwsA(isA<SqliteException>()),
      );
    }
    // Control: the ends of the range a factor is drawn from are stored.
    await db.into(db.reviews).insert(review('least', 0));
    await db.into(db.reviews).insert(review('greatest', 0.9999));
    expect([
      for (final row in await db.select(db.reviews).get()) row.id,
    ], unorderedEquals(['least', 'greatest']));
  });
}
