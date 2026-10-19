import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/l10n/app_localizations.dart';
import 'package:smartman/study/src/daily_minutes.dart';
import 'package:smartman/study/src/daily_minutes_sheet.dart';
import 'package:smartman/study/src/study_repository.dart';
import 'package:smartman/study/src/study_time.dart';

import '../home/home_data.dart';
import 'minutes_sheet.dart';
import 'study_storage.dart';

/// 04:00 on 15 October 2026 at UTC: the start of a study day.
final _today = DateTime.utc(2026, 10, 15, 4);

Duration _utc(DateTime _) => Duration.zero;

/// A plan at the unknown pace of 10 s, with [unstarted] cards never answered.
MinutesPlan _plan({
  int due = 0,
  int started = 0,
  required int unstarted,
  bool backlog = false,
}) => MinutesPlan(
  minutes: null,
  due: due,
  started: started,
  unstarted: unstarted,
  reviews: due,
  backlog: backlog,
  pace: Pace.unknown,
  todayStart: _today,
  offsetAt: _utc,
);

/// Shows [DailyMinutesRow] over an in-memory database at [homeNow], on a
/// phone's screen.
Future<AppDatabase> _pumpRow(WidgetTester tester) async {
  // A phone's screen, so the sheet's choices are on it.
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
  final storage = await openStudyStorage(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deckRepositoryProvider.overrideWithValue(
          DeckRepository(db, clock: () => homeNow, newId: () => 'deck'),
        ),
        ...homeOverrides(db, storage: storage),
      ],
      child: MaterialApp(
        theme: lightTheme,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: DailyMinutesRow()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('what a choice of minutes means', () {
    test('today takes the new cards the minutes leave room for, less those started today', () {
      // 20 min at 10 s: 120 a day, of which 20 were started today.
      final (:fresh, :lastDay) = _plan(started: 20, unstarted: 500).at(20);
      expect(fresh, 100);
      // 400 left after today, 120 a day: four more days.
      expect(lastDay, DateTime.utc(2026, 10, 19, 4));
    });

    test('due reviews come first, so a backlog of them leaves no new card', () {
      // 60 due reviews at 10 s fill 10 minutes.
      expect(_plan(due: 60, unstarted: 50).at(10), (fresh: 0, lastDay: null));
      // Control: five more minutes leave room for 30.
      expect(_plan(due: 60, unstarted: 50).at(15).fresh, 30);
    });

    test('in a backlog no new card is taken, whatever the minutes', () {
      expect(_plan(unstarted: 50, backlog: true).at(60), (
        fresh: 0,
        lastDay: null,
      ));
    });

    test('today takes no more than the cards left, and with none left no day is named', () {
      expect(_plan(unstarted: 7).at(20), (fresh: 7, lastDay: _today));
      expect(_plan(unstarted: 0).at(20), (fresh: 0, lastDay: null));
    });
  });

  testWidgets(
    "the account screen's row shows the minutes, and opens the sheet, then shows those saved",
    (tester) async {
      final db = await _pumpRow(tester);

      expect(find.text('Daily study time'), findsOneWidget);
      expect(find.text('20 min'), findsOneWidget);

      await tester.tap(find.text('Daily study time'));
      await tester.pumpAndSettle();
      await waitForChoices(tester);
      await tester.tap(find.text('45 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(DailyMinutesSheet), findsNothing);
      expect(
        await tester.runAsync<int?>(
          () => StudyRepository(db, newId: () => 'unused').dailyMinutes(),
        ),
        45,
      );
      expect(find.text('45 min'), findsOneWidget);
    },
  );

  testWidgets(
    'at twice the text size the sheet and its custom steps lay out without overflow',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpRow(tester);

      await tester.tap(find.text('Daily study time'));
      await tester.pumpAndSettle();
      await waitForChoices(tester);
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      expect(find.text('Custom · 20 min'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
