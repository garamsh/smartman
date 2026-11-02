import 'package:drift/drift.dart' show OrderingTerm, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowno/database/database.dart';
import 'package:knowno/deck/deck.dart';
import 'package:knowno/design/theme.dart';
import 'package:knowno/l10n/app_localizations.dart';
import 'package:knowno/study/src/current_card.dart';
import 'package:knowno/study/src/model.dart';
import 'package:knowno/study/src/providers.dart';
import 'package:knowno/study/src/rust/api/engine.dart';
import 'package:knowno/study/src/scheduler.dart';
import 'package:knowno/study/src/session.dart';
import 'package:knowno/study/src/study_repository.dart';
import 'package:knowno/study/src/study_screen.dart';

import 'fixtures.dart';
import 'study_storage.dart';

/// Schedules every review one day out, at once.
class _InstantScheduler implements Scheduler {
  @override
  Future<CardState?> fold(List<ReviewRow> reviews) =>
      throw UnimplementedError('sessions do not fold');

  @override
  Future<List<CardState>> history(List<ReviewRow> reviews) =>
      throw UnimplementedError('sessions do not fold');

  @override
  Future<double> retrievability(CardState state, DateTime at) =>
      throw UnimplementedError('sessions read no recall');

  @override
  Future<CardState> review(
    CardState? state,
    Answer answer,
    DateTime at, {
    required FuzzFactor fuzz,
  }) async => CardState(
    stability: 1,
    difficulty: 5,
    lastReview: at,
    due: at.add(const Duration(days: 1)),
  );
}

/// UTC as the device's time zone.
Duration _utc(DateTime _) => Duration.zero;

/// A deck of two new cards in a database of its own, and a clock the test
/// moves.
class _Deck {
  _Deck(this.db);

  final AppDatabase db;
  var now = DateTime.utc(2026, 10, 14, 9);
  var _ids = 0;
  late final cards = DeckRepository(
    db,
    clock: () => now,
    newId: () => 'id${_ids++}',
  );
  late final study = StudyRepository(db, newId: () => 'review${_ids++}');
  late final DeckId id;

  static Future<_Deck> open() async {
    final deck = _Deck(AppDatabase(NativeDatabase.memory()));
    addTearDown(deck.db.close);
    deck.id = (await deck.cards.createDeck('French')).id;
    for (final name in ['a', 'b']) {
      await deck.cards.addCard(
        deck.id,
        front: [TextContent(name)],
        back: [TextContent(name)],
      );
    }
    return deck;
  }

  void wait(Duration duration) => now = now.add(duration);

  /// The stored durations, in the order answered.
  Future<List<Duration>> durations() async => [
    for (final row in await (db.select(
      db.reviews,
    )..orderBy([(row) => OrderingTerm(expression: row.reviewedAt)])).get())
      Duration(milliseconds: row.durationMs),
  ];
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'an answer counts only the time the app was in the foreground',
    () async {
      final deck = await _Deck.open();
      final session = StudySession(
        decks: DeckSelection(deck.id),
        cards: deck.cards,
        repository: deck.study,
        scheduler: _InstantScheduler(),
        clock: () => deck.now,
        random: FirstDraw(),
        onFailure: (failure) => fail('unexpected $failure'),
        offsetAt: _utc,
      );
      addTearDown(session.dispose);
      await untilLoaded(session);

      // 2 s, then an hour away, then 3 s more.
      deck.wait(const Duration(seconds: 2));
      session.pause();
      deck.wait(const Duration(hours: 1));
      session.pause();
      session.resume();
      deck.wait(const Duration(seconds: 3));
      session.answer(Answer.know);
      // Control: the next card, never paused, counts all its time.
      deck.wait(const Duration(seconds: 7));
      session.answer(Answer.know);
      await session.settled;

      expect(await deck.durations(), [
        const Duration(seconds: 5),
        const Duration(seconds: 7),
      ]);
    },
  );

  test('an answer given while away counts the time up to leaving, and the next card starts on return', () async {
    final deck = await _Deck.open();
    final session = StudySession(
      decks: DeckSelection(deck.id),
      cards: deck.cards,
      repository: deck.study,
      scheduler: _InstantScheduler(),
      clock: () => deck.now,
      random: FirstDraw(),
      onFailure: (failure) => fail('unexpected $failure'),
      offsetAt: _utc,
    );
    addTearDown(session.dispose);
    await untilLoaded(session);

    deck.wait(const Duration(seconds: 4));
    session.pause();
    deck.wait(const Duration(minutes: 5));
    session.answer(Answer.know);
    deck.wait(const Duration(minutes: 5));
    session.resume();
    deck.wait(const Duration(seconds: 6));
    session.answer(Answer.know);
    await session.settled;

    expect(await deck.durations(), [
      const Duration(seconds: 4),
      const Duration(seconds: 6),
    ]);
  });

  testWidgets(
    'the study screen stops the answer clock while the app is not resumed',
    (tester) async {
      final deck = (await tester.runAsync(_Deck.open))!;
      final storage = await openStudyStorage(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studyStorageProvider.overrideWithValue(storage),
            deckRepositoryProvider.overrideWithValue(deck.cards),
            studyRepositoryProvider.overrideWithValue(deck.study),
            schedulerProvider.overrideWithValue(_InstantScheduler()),
            studyClockProvider.overrideWithValue(() => deck.now),
            studyZoneProvider.overrideWithValue(_utc),
            studyRandomProvider.overrideWithValue((_) => FirstDraw()),
          ],
          child: MaterialApp(
            theme: lightTheme,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: StudyScreen(decks: DeckSelection(deck.id)),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      deck.wait(const Duration(seconds: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      deck.wait(const Duration(hours: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      deck.wait(const Duration(seconds: 3));
      await tester.timedDrag(
        find.byType(CurrentCard),
        const Offset(200, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(await tester.runAsync(deck.durations), [
        const Duration(seconds: 5),
      ]);
    },
  );
}
