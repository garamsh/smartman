import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/shared/database.dart';
import 'package:smartman/shared/l10n/app_localizations.dart';
import 'package:smartman/study/src/failure.dart';
import 'package:smartman/study/src/model.dart';
import 'package:smartman/study/src/providers.dart';
import 'package:smartman/study/src/rust/api/engine.dart';
import 'package:smartman/study/src/scheduler.dart';
import 'package:smartman/study/src/study_repository.dart';
import 'package:smartman/study/src/today_card.dart';

import 'fixtures.dart';

/// Schedules every review one day out, at once.
class _InstantScheduler implements Scheduler {
  @override
  Future<CardState> review(
    CardState? state,
    Answer answer,
    DateTime at,
  ) async => CardState(
    stability: 1,
    difficulty: 5,
    lastReview: at,
    due: at.add(const Duration(days: 1)),
  );
}

/// Fails every read of the stored states.
class _UnreadableStates implements StudyRepository {
  @override
  ReviewId newReviewId() => const ReviewId('unused');

  @override
  Future<Map<CardId, CardState>> statesOf(List<CardId> cards) async =>
      throw const StudyStorageFailure(FormatException('unreadable'));

  @override
  Future<void> record(CardId card, List<Review> reviews, CardState state) =>
      throw UnimplementedError();
}

final _now = DateTime.utc(2026, 10, 14, 9);

/// Two decks: "a" holds a card due now, one due tomorrow and two new ones;
/// "b" holds a card due yesterday and a new one. A session over both takes
/// five cards.
class _Decks {
  _Decks(this.db);

  final AppDatabase db;
  var _ids = 0;
  late final cards = DeckRepository(
    db,
    clock: () => _now,
    newId: () => 'id${_ids++}',
  );
  late final study = StudyRepository(db, newId: () => 'review${_ids++}');
  late final DeckId a;
  late final DeckId b;

  Future<void> seed() async {
    a = (await cards.createDeck('a')).id;
    b = (await cards.createDeck('b')).id;
    await add(a, 'a due', due: _now);
    await add(a, 'a later', due: _now.add(const Duration(days: 1)));
    await add(a, 'a new 1');
    await add(a, 'a new 2');
    await add(b, 'b due', due: _now.subtract(const Duration(days: 1)));
    await add(b, 'b new');
  }

  Future<void> add(DeckId deck, String front, {DateTime? due}) async {
    final saved = await cards.addCard(
      deck,
      front: [TextContent(front)],
      back: [TextContent(front)],
    );
    final card = switch (saved) {
      CardSaved(:final card) => card,
      DuplicateFront() => fail('the deck held no duplicate'),
    };
    if (due == null) return;
    final state = dueAt(due);
    await study.record(card.id, [
      Review(
        id: study.newReviewId(),
        cardId: card.id,
        answer: Answer.know,
        reviewedAt: state.lastReview,
        duration: Duration.zero,
      ),
    ], state);
  }
}

/// Shows a [TodayCard] over both decks of [decks].
Future<GlobalKey<NavigatorState>> _pump(
  WidgetTester tester,
  _Decks decks, {
  StudyRepository? study,
}) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deckRepositoryProvider.overrideWithValue(decks.cards),
        studyRepositoryProvider.overrideWithValue(study ?? decks.study),
        schedulerProvider.overrideWithValue(_InstantScheduler()),
        studyClockProvider.overrideWithValue(() => _now),
        studyRandomProvider.overrideWithValue((_) => FirstDraw()),
      ],
      child: MaterialApp(
        navigatorKey: navigator,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TodayCard(decks: DeckSelection(decks.a, [decks.b])),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return navigator;
}

Future<_Decks> _seed(WidgetTester tester) async {
  final decks = _Decks(AppDatabase(NativeDatabase.memory()));
  addTearDown(decks.db.close);
  await tester.runAsync(decks.seed);
  return decks;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
    'the count is the length of the queue Study all opens over every deck',
    (tester) async {
      final decks = await _seed(tester);
      await _pump(tester, decks);

      expect(find.text('5 cards for today'), findsOneWidget);

      await tester.tap(find.text('Study all'));
      await tester.pumpAndSettle();

      expect(find.text('0 / 5'), findsOneWidget);
    },
  );

  testWidgets('the count is read again when its route comes back on top', (
    tester,
  ) async {
    final decks = await _seed(tester);
    final navigator = await _pump(tester, decks);
    expect(find.text('5 cards for today'), findsOneWidget);

    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => decks.add(decks.b, 'b new 2'));
    await tester.pumpAndSettle();
    // Control: nothing reads the count while another route covers it.
    expect(find.text('5 cards for today', skipOffstage: false), findsOneWidget);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    expect(find.text('6 cards for today'), findsOneWidget);
  });

  testWidgets('a count that cannot be read says why', (tester) async {
    final decks = await _seed(tester);
    await _pump(tester, decks, study: _UnreadableStates());

    expect(
      find.text(
        "Couldn't read or write the device's storage. Please try again.",
      ),
      findsOneWidget,
    );
    expect(find.text('Study all'), findsOneWidget);
  });
}
