import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:smartman/account/account.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/shared/database.dart';
import 'package:smartman/study/study.dart';
import 'package:smartman/sync/sync.dart';
import 'package:uuid/uuid.dart';

/// One device: its own in-memory database, the repositories that write it,
/// and the synchronizer that syncs it through [server].
class Device {
  Device(this.name, SyncServer server, this.scheduler, {int pageSize = 500})
    : db = AppDatabase(NativeDatabase.memory()) {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    deck = DeckRepository(db, clock: () => now, newId: _newId);
    study = StudyRepository(db, newId: _newId);
    store = SyncStore(db, scheduler, clock: () => now);
    synchronizer = Synchronizer(store, server, pageSize: pageSize);
  }

  final String name;
  final AppDatabase db;
  final Scheduler scheduler;
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

  Future<void> close() => db.close();
}
