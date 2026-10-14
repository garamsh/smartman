import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/shared/database.dart';
import 'package:smartman/shared/l10n/app_localizations.dart';
import 'package:smartman/study/src/model.dart';
import 'package:smartman/study/src/providers.dart';
import 'package:smartman/study/src/queue.dart';
import 'package:smartman/study/src/rust/api/engine.dart';
import 'package:smartman/study/src/scheduler.dart';
import 'package:smartman/study/src/study_repository.dart';
import 'package:smartman/study/src/study_screen.dart';

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

/// Reads no state and never finishes a write.
class _StalledRepository implements StudyRepository {
  var _ids = 0;
  final records = <Review>[];

  @override
  ReviewId newReviewId() => ReviewId('review${_ids++}');

  @override
  Future<Map<CardId, CardState>> statesOf(List<CardId> cards) async => {};

  @override
  Future<void> record(Review review, CardState state) {
    records.add(review);
    return Completer<void>().future;
  }
}

class _Study {
  _Study(this.tester, this.db, this.repository);

  final WidgetTester tester;
  final AppDatabase db;
  final StudyRepository repository;
  DateTime now = DateTime.utc(2026, 10, 14, 9);

  /// Advances the clock by [elapsed], then taps [button].
  Future<void> answer(String button, {Duration elapsed = Duration.zero}) async {
    now = now.add(elapsed);
    await tester.tap(
      find.ancestor(
        of: find.text(button),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    await tester.pump();
  }

  /// The front of the card under study, or null when none is.
  String? get current {
    final fronts = find.descendant(
      of: find.byType(Expanded),
      matching: find.textContaining(RegExp(r'^\w+ front$')),
    );
    return fronts.evaluate().isEmpty
        ? null
        : (fronts.evaluate().last.widget as Text).data;
  }
}

/// Opens a study session over a deck holding [cards], created oldest first.
/// [states] seeds stored scheduling state by card name.
Future<_Study> _open(
  WidgetTester tester,
  List<String> cards, {
  StudyRepository Function(AppDatabase db)? repository,
  Scheduler? scheduler,
  Map<String, CardState> states = const {},
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  var created = DateTime.utc(2026, 9, 1);
  var ids = 0;
  final deckRepository = DeckRepository(
    db,
    clock: () => created = created.add(const Duration(minutes: 1)),
    newId: () => 'id${ids++}',
  );
  final studyRepository =
      (repository ??
      (db) => StudyRepository(db, newId: () => 'review${ids++}'))(db);
  final seeding = StudyRepository(db, newId: () => 'seed${ids++}');
  final deck = (await tester.runAsync(() async {
    final deck = await deckRepository.createDeck('French');
    for (final name in cards) {
      final saved = await deckRepository.addCard(
        deck.id,
        front: [TextContent('$name front')],
        back: [TextContent('$name back')],
      );
      if (saved case CardSaved(:final card) when states.containsKey(name)) {
        await seeding.record(
          Review(
            id: seeding.newReviewId(),
            cardId: card.id,
            answer: Answer.know,
            reviewedAt: states[name]!.lastReview,
            duration: Duration.zero,
          ),
          states[name]!,
        );
      }
    }
    return deck;
  }))!;
  final study = _Study(tester, db, studyRepository);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deckRepositoryProvider.overrideWithValue(deckRepository),
        studyRepositoryProvider.overrideWithValue(studyRepository),
        schedulerProvider.overrideWithValue(scheduler ?? _InstantScheduler()),
        studyClockProvider.overrideWithValue(() => study.now),
      ],
      child: MaterialApp(
        navigatorKey: navigator,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(),
      ),
    ),
  );
  unawaited(
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => StudyScreen(deck: deck)),
    ),
  );
  await tester.pumpAndSettle();
  return study;
}

final _previousPanel = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label?.startsWith('Previous card.') ?? false),
);

String? _previousLabel(WidgetTester tester) => _previousPanel.evaluate().isEmpty
    ? null
    : (tester.widget<Semantics>(_previousPanel)).properties.label;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
    'the next card is on screen in the frame after a tap while the answer is still being written',
    (tester) async {
      final stalled = _StalledRepository();
      final study = await _open(tester, [
        'a',
        'b',
        'c',
      ], repository: (_) => stalled);
      expect(study.current, 'a front');

      await study.answer('Know');

      expect(study.current, 'b front');
      // The write for "a" started and has not finished.
      expect(
        [for (final review in stalled.records) review.cardId],
        [const CardId('id1')],
      );

      await study.answer('Know');
      expect(study.current, 'c front');
    },
  );

  testWidgets(
    'the previous-card panel shows the front and back of the card answered last',
    (tester) async {
      final study = await _open(tester, ['a', 'b']);
      expect(_previousPanel, findsNothing);

      await study.answer('Know');

      expect(
        _previousLabel(tester),
        'Previous card. Front: a front. Back: a back. Answer: Know',
      );
      expect(
        find.descendant(of: _previousPanel, matching: find.text('a front')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _previousPanel, matching: find.text('a back')),
        findsOneWidget,
      );
      expect(study.current, 'b front');
    },
  );

  testWidgets(
    "tapping the previous card turns its Know into Don't know and shows it again after the gap",
    (tester) async {
      final study = await _open(tester, ['a', 'b', 'c', 'd', 'e']);
      await study.answer('Know');

      await tester.tap(_previousPanel);
      await tester.pump();

      expect(
        _previousLabel(tester),
        "Previous card. Front: a front. Back: a back. Answer: Don't know",
      );
      expect(find.text("Tap to change to Don't know"), findsNothing);
      final shown = <String?>[study.current];
      for (var i = 0; i < reshowGap; i++) {
        await study.answer('Know');
        shown.add(study.current);
      }
      // "b" was already on screen when "a" was corrected.
      expect(shown, ['b front', 'c front', 'd front', 'a front']);
    },
  );

  testWidgets("a Don't know card comes back after reshowGap other cards", (
    tester,
  ) async {
    final study = await _open(tester, ['a', 'b', 'c', 'd', 'e']);

    await study.answer("Don't know");
    final shown = <String?>[study.current];
    for (var i = 0; i < reshowGap; i++) {
      await study.answer('Know');
      shown.add(study.current);
    }

    expect(shown, ['b front', 'c front', 'd front', 'a front']);
  });

  testWidgets('the summary counts cards, answers, and the time spent', (
    tester,
  ) async {
    final study = await _open(tester, ['a', 'b']);

    await study.answer("Don't know", elapsed: const Duration(seconds: 10));
    await study.answer('Know', elapsed: const Duration(seconds: 10));
    expect(study.current, 'a front');
    await study.answer('Know', elapsed: const Duration(seconds: 45));

    expect(find.text('Session complete'), findsOneWidget);
    expect(find.text('2 cards studied'), findsOneWidget);
    expect(find.text('Know: 2'), findsOneWidget);
    expect(find.text("Don't know: 1"), findsOneWidget);
    expect(find.text('Time spent: 1 min 5 s'), findsOneWidget);
  });

  testWidgets('correcting the last card from the summary studies it again', (
    tester,
  ) async {
    final study = await _open(tester, ['a']);
    await study.answer('Know');
    expect(find.text('Session complete'), findsOneWidget);

    await tester.tap(_previousPanel);
    await tester.pump();

    expect(find.text('Session complete'), findsNothing);
    expect(study.current, 'a front');
  });

  testWidgets('a deck with nothing due and no new card opens on the summary', (
    tester,
  ) async {
    final study = await _open(
      tester,
      ['later'],
      states: {'later': dueTomorrow},
    );

    // The card exists and was left out because it is not due.
    final stored = await tester.runAsync(
      () => study.db.select(study.db.cardStates).get(),
    );
    expect(stored, hasLength(1));
    expect(find.text('Session complete'), findsOneWidget);
    expect(find.text('Nothing to study right now.'), findsOneWidget);
    expect(find.text('0 cards studied'), findsOneWidget);
    expect(study.current, isNull);
  });

  testWidgets('an answer the storage fails to write is reported to the user', (
    tester,
  ) async {
    final study = await _open(tester, ['a', 'b']);
    // Deleting the card makes the review's foreign key fail on write.
    final deleted = await tester.runAsync(
      () => (study.db.delete(
        study.db.cards,
      )..where((card) => card.id.equals('id1'))).go(),
    );
    expect(deleted, 1);

    await study.answer('Know');
    expect(study.current, 'b front');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(
      find.text(
        "Couldn't save your answer on this device. This card's schedule did not change.",
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'going back mid-session shows the summary, and tap targets carry labels',
    (tester) async {
      final study = await _open(tester, ['a', 'b', 'c']);
      await study.answer('Know');
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Session complete'), findsOneWidget);
      expect(find.text('1 card studied'), findsOneWidget);
      expect(_previousPanel, findsNothing);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(StudyScreen), findsNothing);
    },
  );
}

final dueTomorrow = CardState(
  stability: 3,
  difficulty: 5,
  lastReview: DateTime.utc(2026, 10, 12),
  due: DateTime.utc(2026, 10, 15),
);
