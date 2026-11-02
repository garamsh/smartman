import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:knowno/account/account.dart';
import 'package:knowno/database/database.dart';
import 'package:knowno/deck/deck.dart';
import 'package:knowno/media/media.dart';
import 'package:knowno/study/study.dart';
import 'package:knowno/sync/sync.dart';
import 'package:uuid/uuid.dart';

import '../media/fakes.dart';

/// One device: its own in-memory database and media directory, the
/// repositories that write them, and the synchronizer that syncs it through
/// [server], its media through [mediaServer].
class Device {
  Device(
    this.name,
    SyncServer server,
    this.scheduler, {
    int pageSize = 500,
    MediaServer? mediaServer,
  }) : db = AppDatabase(NativeDatabase.memory()),
       mediaDirectory = newMediaDirectory() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    media = MediaStore(
      db,
      mediaServer ?? FakeMediaServer(),
      directory: mediaDirectory,
      clock: () => now,
      newId: _newId,
    );
    deck = DeckRepository(db, clock: () => now, newId: _newId, media: media);
    study = StudyRepository(db, newId: _newId);
    store = SyncStore(db, scheduler, clock: () => now);
    synchronizer = Synchronizer(store, server, pageSize: pageSize);
  }

  final String name;
  final AppDatabase db;
  final Scheduler scheduler;
  final Directory mediaDirectory;
  late final MediaStore media;
  late final DeckRepository deck;
  late final StudyRepository study;
  late final SyncStore store;
  late final Synchronizer synchronizer;

  /// The device's clock, which every write reads.
  DateTime now = DateTime.utc(2026, 10, 15, 9);

  /// Ids are UUIDs as the app's are, so no two devices or runs share one.
  String _newId() => const Uuid().v4();

  Future<void> sync(UserId account) => synchronizer.run(account);

  /// The deck names the deck list shows.
  Future<List<String>> deckNames() async => [
    for (final deck in await deck.watchDecks().first) deck.name,
  ];

  /// Rates [card] at [now] (`good` or `again`) and stores the review and the
  /// state the engine folds the card's reviews into, unsynced, as a study
  /// session leaves them.
  Future<void> answer(CardId card, String rating, {double fuzz = 0.5}) async {
    await db
        .into(db.reviews)
        .insert(
          ReviewsCompanion.insert(
            id: _newId(),
            cardId: card.value,
            rating: rating,
            reviewedAt: now,
            durationMs: 2000,
            fuzzFactor: Value(fuzz),
            updatedAt: now,
          ),
        );
    final state = (await foldOf(card))!;
    await db
        .into(db.cardStates)
        .insertOnConflictUpdate(
          CardStatesCompanion.insert(
            cardId: card.value,
            stability: state.stability,
            difficulty: state.difficulty,
            lastReview: state.lastReview,
            due: state.due,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
  }

  /// The stored state of [card], as the engine's parts.
  Future<CardStateRow?> stateOf(CardId card) => (db.select(
    db.cardStates,
  )..where((row) => row.cardId.equals(card.value))).getSingleOrNull();

  /// The state the engine reaches folding every stored review of [card].
  Future<
    ({double stability, double difficulty, DateTime lastReview, DateTime due})?
  >
  foldOf(CardId card) async {
    final reviews = await (db.select(
      db.reviews,
    )..where((row) => row.cardId.equals(card.value))).get();
    final state = await scheduler.fold(reviews);
    return state == null
        ? null
        : (
            stability: state.stability,
            difficulty: state.difficulty,
            lastReview: state.lastReview,
            due: state.due,
          );
  }

  Future<void> close() async {
    await db.close();
    await deleteMediaDirectory(mediaDirectory);
  }
}
