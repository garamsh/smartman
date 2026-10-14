import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/shared/database.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

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
}
