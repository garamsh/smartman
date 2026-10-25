import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smartman/account/account.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/design/app_text_field.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/design/theme_choice.dart';
import 'package:smartman/home/home.dart';
import 'package:smartman/l10n/app_localizations.dart';
import 'package:smartman/main.dart';
import 'package:smartman/photo_import/photo_import.dart';
import 'package:smartman/sharing/sharing.dart';
import 'package:smartman/study/study.dart';
import 'package:smartman/sync/sync.dart';

import '../account/fake_account_service.dart';
import '../home/home_data.dart';
import '../photo_import/fakes.dart';
import '../sharing/fakes.dart';
import '../sharing/sharing_service_test.dart' show publicCard, publicDeck;
import '../sync/fake_sync_server.dart';
import '../study/minutes_sheet.dart';
import '../study/study_storage.dart';

/// Screenshots of every screen and sheet in both themes, for review. They are
/// written, not compared, and only when asked for:
///
/// `flutter test --update-goldens --dart-define=SCREENSHOTS=true --dart-define-from-file=config/dev.json test/screenshots`
///
/// run in `app/`, writes them to `app/build/screenshots/<theme>/`.
const _capture = bool.fromEnvironment('SCREENSHOTS');

const _ada = UserId('00000000-0000-4000-8000-00000000000a');

/// A phone's screen: 390 × 844 logical pixels at twice the density.
const _phone = Size(780, 1688);
const _density = 2.0;

/// Loads the bundled font, Lucide's icons and Material's, which tests
/// otherwise draw as boxes.
Future<void> _loadFonts() async {
  Future<ByteData> bytes(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());
  final pretendard = FontLoader(appFontFamily);
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    pretendard.addFont(bytes('assets/fonts/Pretendard-$weight.otf'));
  }
  await pretendard.load();
  await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      ))
      .load();
  await (FontLoader('MaterialIcons')..addFont(
        bytes(
          '${_flutterRoot()}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ),
      ))
      .load();
}

/// The Flutter SDK running this test, found above the test runner.
String _flutterRoot() {
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.parent.path != dir.path) {
    if (Directory('${dir.path}/bin/cache/artifacts/material_fonts')
        .existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }
  throw StateError('no Flutter SDK above ${Platform.resolvedExecutable}');
}

void main() {
  late Scheduler scheduler;
  setUpAll(() async {
    if (!_capture) return;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await _loadFonts();
    scheduler = await Scheduler.load();
  });

  final ko = lookupAppLocalizations(const Locale('ko'));

  for (final mode in ['light', 'dark']) {
    /// Decodes the images on screen, which a test otherwise draws blank.
    Future<void> loadImages(WidgetTester tester) async {
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          await precacheImage((element.widget as Image).image, element);
        }
      });
      await tester.pump();
    }

    Future<void> shot(WidgetTester tester, String name) async {
      await loadImages(tester);
      await expectLater(
        find.byType(MaterialApp).first,
        matchesGoldenFile('../../build/screenshots/$mode/$name.png'),
      );
    }

    void phone(WidgetTester tester) {
      // Release builds draw neither the debug banner nor flat shadows;
      // [unmount] restores both before the test's own checks run.
      WidgetsApp.debugAllowBannerOverride = false;
      debugDisableShadows = false;
      tester.view.physicalSize = _phone;
      tester.view.devicePixelRatio = _density;
      tester.platformDispatcher.localesTestValue = const [Locale('ko')];
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      WidgetsApp.debugAllowBannerOverride = true;
      debugDisableShadows = true;
    }

    Future<void> tap(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    /// Shows the 기록 tab once its read is done: the read awaits the
    /// engine call by call, each finishing in real time and resuming on a
    /// pump.
    Future<void> showRecord(WidgetTester tester) async {
      await tester.tap(find.text(ko.tabRecord));
      for (
        var tries = 0;
        tries < 20000 && find.text(ko.retentionTitle).evaluate().isEmpty;
        tries++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
        await tester.pump();
      }
      expect(find.text(ko.retentionTitle), findsOneWidget);
      await tester.pumpAndSettle();
    }

    Future<void> dismissSheet(WidgetTester tester) =>
        tap(tester, find.byType(ModalBarrier).last);

    testWidgets('the app in $mode', skip: !_capture, (tester) async {
      phone(tester);
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({'themeMode': mode});
      final storage = (await tester.runAsync(
        () => SharedPreferencesWithCache.create(
          cacheOptions: const SharedPreferencesWithCacheOptions(
            allowList: {
              ...themeStorageKeys,
              ...photoImportStorageKeys,
              ...studyStorageKeys,
              ...deckStorageKeys,
            },
          ),
        ),
      ))!;
      final server = FakeSyncServer(_ada);
      final account = FakeAccountService();
      await tester.pumpWidget(
        composeApp(
          NativeDatabase.memory(),
          scheduler,
          account,
          server,
          storage,
          // The first-run home shows every way to start.
          FakeExtractionClient(),
          FakeSharingServer(),
          FakeReachability(),
          '1.0.0',
        ),
      );
      await tester.pumpAndSettle();
      await shot(tester, '01-sign-in');

      await tap(tester, find.text(ko.signInWithGoogle));
      await shot(tester, '02-deck-list-empty');

      Future<void> enter(String label, String text) async {
        await tester.enterText(
          find.descendant(
            of: find
                .ancestor(of: find.text(label), matching: find.byType(Column))
                .first,
            matching: find.byType(EditableText),
          ),
          text,
        );
        await tester.pumpAndSettle();
      }

      // The first-run home's one primary opens the new-deck sheet.
      await tap(tester, find.text(ko.makeDeck));
      await shot(tester, '03b-new-deck-options');
      await tap(tester, find.text(ko.createManually));
      await shot(tester, '03-new-deck-sheet');
      await enter(ko.deckName, '영단어 기본');
      // Creating the deck opens it, empty, adding a card its one primary.
      await tap(tester, find.text(ko.create));
      await shot(tester, '04-card-list-empty');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      // The 오늘 tab while no deck holds a card: how to start.
      await shot(tester, '16-today-no-cards');
      await tap(tester, find.text(ko.tabDecks));
      await tap(tester, find.text(ko.newDeckTitle));
      await tap(tester, find.text(ko.createManually));
      await enter(ko.deckName, '일본어 N3 한자');
      await tap(tester, find.text(ko.create));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tap(tester, find.text('영단어 기본'));
      const cards = {
        'ephemeral': '덧없는, 순간적인',
        'meticulous': '꼼꼼한, 세심한',
        'ubiquitous': '어디에나 있는',
        'resilient': '회복력 있는',
      };
      for (final (index, MapEntry(key: front, value: back))
          in cards.entries.indexed) {
        await tap(tester, find.text(ko.newCard));
        if (index == 0) await shot(tester, '04b-add-card-sheet');
        await tap(tester, find.text(ko.createManually));
        await enter(ko.cardFront, front);
        await enter(ko.cardBack, back);
        if (index == 0) await shot(tester, '05-card-editor');
        await tap(tester, find.text(ko.save));
      }
      await tap(tester, find.text(ko.newCard));
      await tap(tester, find.text(ko.createManually));
      await enter(ko.cardFront, 'Ephemeral');
      await enter(ko.cardBack, '순간의');
      await tap(tester, find.text(ko.save));
      await shot(tester, '06-duplicate-sheet');
      // Above a tall sheet, where the barrier's centre is not.
      await tester.tapAt(const Offset(20, 100));
      await tester.pumpAndSettle();
      // Leaving the typed card asks first.
      await tap(tester, find.byTooltip(ko.close));
      await tap(tester, find.text(ko.discardCard));
      await shot(tester, '07-card-list');
      await tap(tester, find.text('ubiquitous'));
      await shot(tester, '07b-card-answer-shown');
      await tap(tester, find.byTooltip(ko.searchCardsAction));
      await tester.enterText(find.byType(EditableText), 'ent');
      await tester.pumpAndSettle();
      await shot(tester, '07c-card-search');
      await tap(tester, find.byTooltip(ko.closeSearch));
      await tap(tester, find.byType(Switch));
      await shot(tester, '07d-card-list-answers-shown');
      await tap(tester, find.byType(Switch));

      await tap(tester, find.byTooltip(ko.deckActions));
      await tap(tester, find.text(ko.rename));
      await shot(tester, '08-rename-sheet');
      await dismissSheet(tester);
      await tap(tester, find.byTooltip(ko.deckActions));
      await tap(tester, find.text(ko.deleteDeck));
      await shot(tester, '09-delete-deck-confirm');
      await tap(tester, find.text(ko.cancel));

      await tester.longPress(find.text('meticulous'));
      await tester.pumpAndSettle();
      await shot(tester, '10-card-editor-existing');
      await tap(tester, find.byTooltip(ko.deleteCard));
      await shot(tester, '11-delete-card-confirm');
      await tap(tester, find.text(ko.cancel));
      await tap(tester, find.byTooltip(ko.close));

      // The tabs before any study: four new cards for today.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tap(tester, find.text(ko.tabToday));
      // Once a deck has cards, the first-run step asks for the daily minutes.
      await waitForPicker(tester, more: ko.dailyMinutesMore);
      await shot(tester, '16a0-daily-minutes-first');
      await tap(tester, find.text(ko.dailyMinutesSkip));
      await shot(tester, '16a-today');
      await tap(tester, find.text(ko.tabDecks));
      await tap(tester, find.text('영단어 기본'));

      await tester.tap(find.text(ko.studyDeck));
      // The device's first session: the coach. Its demonstration repeats, so
      // the screen is pumped a fixed time into its cycle rather than settled.
      for (
        var tries = 0;
        tries < 20 && find.text(ko.coachSkip).evaluate().isEmpty;
        tries++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 1500));
      await shot(tester, '12-study-coach');
      for (var step = 0; step < 2; step++) {
        await tester.tap(find.text(ko.coachNext));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 2800));
      await shot(tester, '12b-study-coach-change');
      await tap(tester, find.text(ko.coachSkip));
      // A day's first session: the empty previous card's place.
      await shot(tester, '12c-study-start');
      Future<void> answer(String label) =>
          tap(tester, find.widgetWithText(TextButton, label));
      for (final label in [ko.know, ko.dontKnow, ko.know, ko.know]) {
        await answer(label);
      }
      // At rest: the previous card above the current one.
      await shot(tester, '13-study-session');
      // The previous card, above the current one.
      final previous = find
          .bySemanticsLabel(
            RegExp('^앞면: (ephemeral|meticulous|ubiquitous|resilient)\\. '),
          )
          .first;
      final gesture = await tester.startGesture(tester.getCenter(previous));
      for (var moved = 0; moved < 8; moved++) {
        await gesture.moveBy(const Offset(-15, 0));
        await tester.pump(const Duration(milliseconds: 50));
      }
      // Re-deciding the previous card, its new answer shown behind it.
      await shot(tester, '13c-study-redecide');
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(previous);
      await tester.pumpAndSettle();
      await shot(tester, '14-whole-card-sheet');
      await dismissSheet(tester);
      // The today card once some of the day's cards are done.
      await tap(tester, find.byTooltip(ko.close));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tap(tester, find.text(ko.tabToday));
      await shot(tester, '16a1-today-started');
      await tap(tester, find.text(ko.tabDecks));
      await tap(tester, find.text('영단어 기본'));
      // Reopened the same day: the day's last card from the earlier session,
      // and for a moment the notice that the session goes on with the day.
      await tap(tester, find.text(ko.studyDeck));
      await shot(tester, '13d-study-resumed');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      for (
        var tries = 0;
        tries < 10 && find.text(ko.studyComplete).evaluate().isEmpty;
        tries++
      ) {
        await answer(ko.know);
      }
      // No new card is left past today's, so the card says so.
      await shot(tester, '15-study-complete');
      await tap(tester, find.byTooltip(ko.close));

      // The empty deck has nothing to study today.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Navigator).first),
      );
      final decks = (await tester.runAsync(
        () => container.read(deckRepositoryProvider).watchDecks().first,
      ))!;
      final empty = decks.firstWhere((deck) => deck.name == '일본어 N3 한자');
      unawaited(
        Navigator.of(tester.element(find.byType(Navigator).first)).push(
          MaterialPageRoute<void>(
            builder: (_) => StudyScreen(decks: DeckSelection(empty.id)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await shot(tester, '15c-study-nothing-today');
      await tap(tester, find.byTooltip(ko.close));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await shot(tester, '16-deck-list');
      await showRecord(tester);
      await shot(tester, '16c-record');
      // Today's cards done: the done card and the next seven days.
      await tap(tester, find.text(ko.tabToday));
      await shot(tester, '16b-today-done');

      await tap(tester, find.byTooltip(ko.account));
      await shot(tester, '18-account');
      // Its 하루 공부 시간 row opens the minutes picker as a screen; + moves
      // the number and the tiles follow.
      await tap(tester, find.text(ko.dailyMinutesTitle));
      await waitForPicker(tester, more: ko.dailyMinutesMore);
      await tap(tester, find.byTooltip(ko.dailyMinutesMore));
      await shot(tester, '18c-daily-minutes-screen');
      // The number typed in place, out of range, above the keypad's space:
      // the test renderer draws no system keyboard, so its inset stands in.
      await tap(
        tester,
        find.bySemanticsLabel(ko.dailyMinutesNumberSemantics(25)),
      );
      await tester.enterText(find.byType(TextField), '200');
      tester.view.viewInsets = const FakeViewPadding(bottom: 690);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await shot(tester, '18d-daily-minutes-keypad');
      tester.view.resetViewInsets();
      await tester.enterText(find.byType(TextField), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(ko.termsOfService),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await shot(tester, '18b-account-footer');
      server.failure = const SyncOffline('no route to host');
      await tester.tap(find.text(ko.signOut));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await shot(tester, '19-sign-out-warning');
      await tester.tap(find.text(ko.cancel));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text(ko.deleteAccount));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await shot(tester, '19b-delete-account-confirm');
      await tester.tap(find.text(ko.cancel));
      await tester.pump(const Duration(seconds: 1));

      // Disposing sync cancels the run a write scheduled.
      ProviderScope.containerOf(
        tester.element(find.byType(AccountGate, skipOffstage: false)),
      ).read(syncControllerProvider).dispose();
      await unmount(tester);
    });

    testWidgets('the today tab in a backlog in $mode', skip: !_capture, (
      tester,
    ) async {
      phone(tester);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var ids = 0;
      final repository = DeckRepository(
        db,
        clock: () => homeNow.subtract(const Duration(days: 90)),
        newId: () => 'id${ids++}',
      );
      await tester.runAsync(() async {
        for (final (name, count) in [('영단어 기본', 52), ('토익 빈출', 32)]) {
          final deck = await repository.createDeck(name);
          for (var i = 0; i < count; i++) {
            final saved = await repository.addCard(
              deck.id,
              front: [TextContent('$name $i')],
              back: [TextContent('$i')],
            );
            if (saved case CardSaved(:final card)) {
              // Overdue after a month's interval: far more than three days'
              // load.
              await storeState(db, card.id, due: homeNow, days: 30);
            }
          }
        }
      });
      final storage = await openStudyStorage(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deckRepositoryProvider.overrideWithValue(repository),
            ...homeOverrides(db, storage: storage),
          ],
          child: MaterialApp(
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: ThemeMode.values.byName(mode),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await shot(tester, '16d-today-backlog');
      await unmount(tester);
    });

    testWidgets(
      'the today tab at twice the text size in $mode',
      skip: !_capture,
      (tester) async {
        phone(tester);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        var ids = 0;
        final repository = DeckRepository(
          db,
          clock: () => homeNow.subtract(const Duration(days: 2)),
          newId: () => 'id${ids++}',
        );
        await tester.runAsync(() async {
          final deck = await repository.createDeck('영단어 기본');
          for (var i = 0; i < 30; i++) {
            final saved = await repository.addCard(
              deck.id,
              front: [TextContent('word $i')],
              back: [TextContent('$i')],
            );
            if (saved case CardSaved(:final card) when i < 12) {
              // Due today after a day's interval, answered the day before.
              await storeState(db, card.id, due: homeNow);
              await storeAnswers(db, card.id, 1, const Duration(seconds: 10));
            }
          }
        });
        final storage = await openStudyStorage(tester);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              deckRepositoryProvider.overrideWithValue(repository),
              ...homeOverrides(db, storage: storage),
            ],
            child: MaterialApp(
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: ThemeMode.values.byName(mode),
              locale: const Locale('ko'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const HomeScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await shot(tester, '16j-today-text-2x');
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
        await tester.pumpAndSettle();
        await shot(tester, '16k-today-text-2x-below');
        await unmount(tester);
      },
    );

    testWidgets('study past the day\'s plan in $mode', skip: !_capture, (
      tester,
    ) async {
      phone(tester);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var ids = 0;
      final repository = DeckRepository(
        db,
        clock: () => homeNow.subtract(const Duration(days: 1)),
        newId: () => 'id${ids++}',
      );
      await tester.runAsync(() async {
        // 5 minutes a day at 10 s: 30 new cards, so of the 35 answered today
        // five are past the plan, and five more are left to study on.
        await StudyRepository(
          db,
          newId: () => 'setting',
        ).setDailyMinutes(5, at: homeNow);
        final deck = await repository.createDeck('영단어 기본');
        for (var i = 0; i < 40; i++) {
          final saved = await repository.addCard(
            deck.id,
            front: [TextContent('word $i')],
            back: [TextContent('$i')],
          );
          if (saved case CardSaved(:final card) when i < 35) {
            await storeState(
              db,
              card.id,
              due: homeNow.add(const Duration(days: 1)),
            );
            await storeAnswerAt(
              db,
              card.id,
              homeNow.subtract(Duration(minutes: 60 - i)),
            );
          }
        }
      });
      final storage = await openStudyStorage(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deckRepositoryProvider.overrideWithValue(repository),
            ...homeOverrides(db, storage: storage),
          ],
          child: MaterialApp(
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: ThemeMode.values.byName(mode),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await shot(tester, '16i-today-done-extra');
      await tester.scrollUntilVisible(
        find.text(ko.todayStudy),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, find.text(ko.todayStudy));
      await shot(tester, '15d-study-extra');
      await unmount(tester);
    });

    testWidgets('whole cards in $mode', skip: !_capture, (tester) async {
      phone(tester);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var ids = 0;
      final repository = DeckRepository(
        db,
        clock: () => homeNow.subtract(const Duration(days: 1)),
        newId: () => 'id${ids++}',
      );
      await tester.runAsync(() async {
        final deck = await repository.createDeck('국어 문법');
        for (final front in [
          [
            const ClozeContent('3인칭 재귀칭: 높임 ___ · 예사 ___ · 낮춤 저', ['당신', '자기']),
          ],
          [
            const TextContent('불규칙 활용'),
            const TableContent(
              columns: ['불규칙', '기본형', '활용'],
              rows: [
                ['ㄷ 불규칙', '듣다', '들어'],
                ['ㅂ 불규칙', '돕다', '도와'],
                ['ㅅ 불규칙', '낫다', '나아'],
              ],
              blanks: [
                (row: 0, column: 2),
                (row: 1, column: 2),
                (row: 2, column: 2),
              ],
            ),
          ],
        ]) {
          await repository.addCard(
            deck.id,
            front: front,
            back: [TextContent(plainText(front))],
          );
        }
      });
      final storage = await openStudyStorage(tester);
      await tester.pumpWidget(
        ProviderScope(
          // The real scheduler, as answering a card reviews it.
          overrides: [
            deckRepositoryProvider.overrideWithValue(repository),
            accountServiceProvider.overrideWithValue(
              FakeAccountService(
                const SignedIn(userId: _ada, email: 'ada@example.com'),
              ),
            ),
            studyRepositoryProvider.overrideWithValue(
              StudyRepository(db, newId: () => 'review${ids++}'),
            ),
            schedulerProvider.overrideWithValue(scheduler),
            studyClockProvider.overrideWithValue(() => homeNow),
            studyZoneProvider.overrideWithValue((_) => Duration.zero),
            studyRandomProvider.overrideWithValue((_) => Random(0)),
            studyStorageProvider.overrideWithValue(storage),
          ],
          child: MaterialApp(
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: ThemeMode.values.byName(mode),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text(ko.tabDecks));
      await tap(tester, find.text('국어 문법'));
      await shot(tester, '31-whole-card-list');
      await tap(tester, find.byType(Switch));
      await shot(tester, '31b-whole-card-list-shown');

      await tap(tester, find.text(ko.studyDeck));
      await shot(tester, '32-whole-card-study');
      for (final name in [
        '32b-whole-card-answered',
        '32c-whole-card-answered',
      ]) {
        await tap(tester, find.widgetWithText(TextButton, ko.know));
        await shot(tester, name);
      }
      // The answers' writes land before the database closes.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await unmount(tester);
    });

    testWidgets('the word form in $mode', skip: !_capture, (tester) async {
      phone(tester);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var ids = 0;
      final repository = DeckRepository(
        db,
        clock: () => homeNow,
        newId: () => 'id${ids++}',
      );
      final deck = (await tester.runAsync(
        () => repository.createDeck('영단어 기본'),
      ))!;
      final storage = await openStudyStorage(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deckRepositoryProvider.overrideWithValue(repository),
            deckStorageProvider.overrideWithValue(storage),
          ],
          child: MaterialApp(
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: ThemeMode.values.byName(mode),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: CardEditorScreen(deck: deck),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> reveal(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
      }

      Future<void> fill(String label, String text, [int index = 0]) async {
        final field = find.widgetWithText(AppTextField, label).at(index);
        await reveal(field);
        await tester.enterText(field, text);
        await tester.pumpAndSettle();
      }

      await tap(tester, find.text(ko.cardKindWord));
      await tap(tester, find.text(ko.save));
      await shot(tester, '05b-card-editor-word-errors');

      await fill(ko.cardFront, 'present');
      await tap(tester, find.text(ko.addLabel));
      await shot(tester, '05c-card-editor-label-sheet');
      await tap(tester, find.text(ko.partOfSpeechChoice('명', '명사')));
      await fill(ko.senseMeaning, '선물');
      await fill(ko.senseExamples, 'a birthday present');
      await reveal(find.text(ko.addSense));
      await tap(tester, find.text(ko.addSense));
      await reveal(find.text(ko.addLabel).at(1));
      await tap(tester, find.text(ko.addLabel).at(1));
      await tap(tester, find.text(ko.partOfSpeechChoice('동', '동사')));
      await fill(ko.senseMeaning, '주다, 제시하다', 1);
      await reveal(find.text(ko.cardKindWord));
      await shot(tester, '05d-card-editor-word');
      await reveal(find.text(ko.addSense));
      await shot(tester, '05e-card-editor-word-senses');
      await unmount(tester);
    });

    testWidgets(
      'the card editor with the keyboard up in $mode',
      skip: !_capture,
      (tester) async {
        phone(tester);
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        var ids = 0;
        final repository = DeckRepository(
          db,
          clock: () => homeNow,
          newId: () => 'id${ids++}',
        );
        final deck = (await tester.runAsync(
          () => repository.createDeck('영단어 기본'),
        ))!;
        final storage = await openStudyStorage(tester);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              deckRepositoryProvider.overrideWithValue(repository),
              deckStorageProvider.overrideWithValue(storage),
            ],
            child: MaterialApp(
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: ThemeMode.values.byName(mode),
              locale: const Locale('ko'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: CardEditorScreen(deck: deck),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, find.text(ko.cardKindBasic));
        // A phone keyboard 336 points high, given in physical pixels.
        tester.view.viewInsets = const FakeViewPadding(bottom: 336 * _density);
        addTearDown(tester.view.resetViewInsets);
        await tester.enterText(
          find.widgetWithText(AppTextField, ko.cardFront),
          'ephemeral',
        );
        await tester.pumpAndSettle();
        await shot(tester, '05k-card-editor-keyboard');
        tester.view.resetViewInsets();
        await tap(tester, find.byTooltip(ko.close));
        await shot(tester, '05l-card-editor-discard');
        await unmount(tester);
      },
    );

    testWidgets('the cloze form in $mode', skip: !_capture, (tester) async {
      phone(tester);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var ids = 0;
      final repository = DeckRepository(
        db,
        clock: () => homeNow,
        newId: () => 'id${ids++}',
      );
      final deck = (await tester.runAsync(
        () => repository.createDeck('영단어 기본'),
      ))!;
      final storage = await openStudyStorage(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deckRepositoryProvider.overrideWithValue(repository),
            deckStorageProvider.overrideWithValue(storage),
          ],
          child: MaterialApp(
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: ThemeMode.values.byName(mode),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: CardEditorScreen(deck: deck),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text(ko.cardKindCloze));
      await tester.enterText(
        find.widgetWithText(AppTextField, ko.cardFront),
        'She gave me a present for my birthday',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(ko.save));
      await tap(tester, find.text(ko.save));
      await shot(tester, '05f-card-editor-cloze-error');
      for (final word in ['a', 'present']) {
        final chip = find.widgetWithText(FilterChip, word);
        await tester.ensureVisible(chip);
        await tap(tester, chip);
      }
      await tester.ensureVisible(find.text(ko.cardKindCloze));
      await tester.pumpAndSettle();
      await shot(tester, '05g-card-editor-cloze');
      final pick = find.text(ko.clozePickLetters).last;
      await tester.ensureVisible(pick);
      await tap(tester, pick);
      await tap(tester, find.text('p'));
      await tap(tester, find.text('s'));
      await shot(tester, '05m-card-editor-cloze-letters');
      await unmount(tester);
    });

    testWidgets('the table form in $mode', skip: !_capture, (tester) async {
      phone(tester);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var ids = 0;
      final repository = DeckRepository(
        db,
        clock: () => homeNow,
        newId: () => 'id${ids++}',
      );
      final deck = (await tester.runAsync(
        () => repository.createDeck('영단어 기본'),
      ))!;
      final storage = await openStudyStorage(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deckRepositoryProvider.overrideWithValue(repository),
            deckStorageProvider.overrideWithValue(storage),
          ],
          child: MaterialApp(
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: ThemeMode.values.byName(mode),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: CardEditorScreen(deck: deck),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text(ko.cardKindTable));
      await tester.enterText(
        find.widgetWithText(AppTextField, ko.cardFront),
        '불규칙 동사',
      );
      // The table's fields follow the front's: its headers, then its cells.
      Finder cell(int index) => find.byType(TextField).at(index + 1);
      for (final (index, text) in [
        '원형',
        '과거형',
        'go',
        'went',
        'see',
        'saw',
      ].indexed) {
        await tester.ensureVisible(cell(index));
        await tester.enterText(cell(index), text);
      }
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(ko.addRow));
      await tester.pumpAndSettle();
      await shot(tester, '05h-card-editor-table');
      await tester.ensureVisible(find.text(ko.tableModeBlanks));
      await tap(tester, find.text(ko.tableModeBlanks));
      await tap(tester, find.widgetWithText(InkWell, 'went'));
      await tap(tester, find.widgetWithText(InkWell, 'saw'));
      await tester.ensureVisible(find.text(ko.cardKindTable));
      await tester.pumpAndSettle();
      await shot(tester, '05i-card-editor-table-blanks');
      await unmount(tester);
    });

    testWidgets('the record tab over twelve weeks in $mode', skip: !_capture, (
      tester,
    ) async {
      phone(tester);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var ids = 0;
      final repository = DeckRepository(
        db,
        clock: () => homeNow.subtract(const Duration(days: 90)),
        newId: () => 'id${ids++}',
      );
      final study = StudyRepository(db, newId: () => 'review${ids++}');
      await tester.runAsync(() async {
        final deck = await repository.createDeck('영단어 기본');
        final cards = <CardId>[];
        for (var i = 0; i < 60; i++) {
          if (await repository.addCard(
                deck.id,
                front: [TextContent('word $i')],
                back: [TextContent('$i')],
              )
              case CardSaved(:final card)) {
            cards.add(card.id);
          }
        }
        // Four new cards a study day and every card due, answered "Don't
        // know" one time in nine, over 84 days with a few rest days.
        final states = <CardId, CardState>{};
        final random = Random(7);
        var next = 0;
        for (var day = 83; day >= 0; day--) {
          if (day > 6 && day % 9 == 4) continue;
          final at = DateTime.utc(
            2026,
            10,
            15,
            6,
          ).subtract(Duration(days: day));
          final end = at.add(const Duration(hours: 22));
          final today = [
            for (final card in cards)
              if (states[card]?.due.isBefore(end) ?? false) card,
            ...cards.skip(next).take(4),
          ];
          next = min(cards.length, next + 4);
          for (final (index, card) in today.indexed) {
            final answer = (index * 7 + day) % 9 == 0
                ? Answer.dontKnow
                : Answer.know;
            final time = at.add(Duration(minutes: index));
            final fuzz = FuzzFactor.draw(random);
            final state = await scheduler.review(
              states[card],
              answer,
              time,
              fuzz: fuzz,
            );
            states[card] = state;
            await study.record(
              card,
              [
                Review(
                  id: study.newReviewId(),
                  cardId: card,
                  answer: answer,
                  reviewedAt: time,
                  duration: const Duration(seconds: 6),
                  fuzzFactor: fuzz,
                ),
              ],
              state,
              at: time,
            );
          }
        }
      });
      // The 오늘 tab behind 기록 reads whether the minutes' step has shown.
      final storage = await openStudyStorage(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deckRepositoryProvider.overrideWithValue(repository),
            accountServiceProvider.overrideWithValue(
              FakeAccountService(
                const SignedIn(userId: _ada, email: 'ada@example.com'),
              ),
            ),
            studyStorageProvider.overrideWithValue(storage),
            studyRepositoryProvider.overrideWithValue(study),
            schedulerProvider.overrideWithValue(scheduler),
            studyClockProvider.overrideWithValue(() => homeNow),
            studyZoneProvider.overrideWithValue((_) => Duration.zero),
            studyRandomProvider.overrideWithValue((_) => Random(0)),
          ],
          child: MaterialApp(
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: ThemeMode.values.byName(mode),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await showRecord(tester);
      await shot(tester, '16e-record-history');
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      await shot(tester, '16f-record-history-scrolled');
      await unmount(tester);
    });

    testWidgets('photo import in $mode', skip: !_capture, (tester) async {
      final semantics = tester.ensureSemantics();
      phone(tester);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var ids = 0;
      final repository = DeckRepository(
        db,
        clock: DateTime.now,
        newId: () => 'id${ids++}',
      );
      final deck = (await tester.runAsync(() async {
        final deck = await repository.createDeck('영단어 기본');
        await repository.createDeck('일본어 N3 한자');
        await repository.addCard(
          deck.id,
          front: [const TextContent('lucid')],
          back: [const TextContent('명쾌한')],
        );
        return deck;
      }))!;
      final client = FakeExtractionClient();
      final photos = FakePhotoSource();
      final preferences = await openPreferences(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [deckRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: ThemeMode.values.byName(mode),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => importFromPhoto(
                      context,
                      deck: deck.id,
                      origin: PhotoOrigin.camera,
                      client: client,
                      photos: photos,
                      preferences: preferences,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      /// The text that reads [text] once its word joiners are left out.
      Finder shown(String text) => find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data ?? widget.textSpan?.toPlainText())?.replaceAll(
                  '\u2060',
                  '',
                ) ==
                text,
      );

      /// Taps [finder], which takes a photo with the camera, through to the
      /// extraction.
      Future<void> shoot(Finder finder) async {
        await tester.tap(finder);
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
      }

      await shoot(find.text('open'));
      await shot(tester, '22-photo-extracting');
      client.answerCards([
        const CandidateCard(
          front: 'face',
          answer: '[동] 직면하다, 마주하다\n[명] 표면, 겉면\n[명] 얼굴, 생김새',
          kind: CardKind.vocabulary,
          senses: [
            CardSense(
              labels: [PartOfSpeechLabel(PartOfSpeech.verb, '동')],
              meaning: '직면하다, 마주하다',
            ),
            CardSense(
              labels: [PartOfSpeechLabel(PartOfSpeech.noun, '명')],
              meaning: '표면, 겉면',
            ),
            CardSense(
              labels: [PartOfSpeechLabel(PartOfSpeech.noun, '명')],
              meaning: '얼굴, 생김새',
            ),
          ],
          pronunciation: "['feis]",
          extras: [Extra(label: '유의어', text: 'confront')],
          topic: '최빈출 단어',
        ),
        word(
          front: 'include',
          meaning: '포함하다, 포괄하다',
          partOfSpeech: '[동]',
          topic: '최빈출 단어',
        ),
        word(
          front: 'strategy',
          meaning: '전략, 계획',
          partOfSpeech: '[명]',
          topic: '최빈출 단어',
        ),
        word(
          front: 'lucid',
          meaning: '맑은, 또렷한',
          partOfSpeech: '[형]',
          topic: '최빈출 단어',
        ),
        word(front: 'in addition', meaning: '~뿐만 아니라, 또한', topic: '빈출 숙어'),
        word(front: 'be ready to', meaning: '~할 준비가 되다', topic: '빈출 숙어'),
      ]);
      await tester.pumpAndSettle();
      await shot(tester, '22a-photo-list');
      await tap(tester, find.bySemanticsLabel(RegExp('^최빈출 단어 카드 모양')));
      await shot(tester, '22b-photo-list-menu');
      await tap(tester, find.widgetWithText(MenuItemButton, ko.importBoth));
      await tap(tester, shown('face'));
      await shot(tester, '22c-photo-edit');
      await tap(tester, find.text(ko.editDone));
      await tap(tester, find.text('영단어 기본'));
      await shot(tester, '21-photo-deck-sheet');
      await dismissSheet(tester);

      await tap(tester, find.text(ko.retake));
      await shot(tester, '22d-photo-discard');
      await shoot(find.text(ko.discardImport));
      client.answerCards(const [
        CandidateCard(
          front: '양성모음',
          answer: 'ㅏ ㅗ ㅑ ㅛ. 밝고 가벼운 느낌의 모음',
          topic: '모음조화',
        ),
        CandidateCard(
          front: '음성모음',
          answer: 'ㅓ ㅜ ㅡ ㅕ ㅠ. 어둡고 무거운 느낌의 모음',
          topic: '모음조화',
        ),
        CandidateCard(
          front: 'ㅗ + ㅏ 축약',
          answer: 'ㅗ와 ㅏ가 만나면 ㅘ로 줄어듦',
          topic: '축약·탈락',
        ),
        CandidateCard(
          front: "'잡아라'의 '아'",
          answer: '양성모음 어간 뒤 — ㅏ',
          type: CardType.identify,
          topic: '모음조화',
        ),
      ]);
      await tester.pumpAndSettle();
      await shot(tester, '23-photo-notes');

      await tap(tester, find.text(ko.retake));
      await shoot(find.text(ko.discardImport));
      client.fail(const ModelFailed());
      await tester.pumpAndSettle();
      await shot(tester, '24-photo-failure');

      photos.cameraFailure = const PhotoAccessDenied('denied');
      await tap(tester, find.text(ko.retake));
      await shot(tester, '25-photo-refused');

      await unmount(tester);
      semantics.dispose();
    });

    testWidgets('several photos in $mode', skip: !_capture, (tester) async {
      final semantics = tester.ensureSemantics();
      phone(tester);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var ids = 0;
      final repository = DeckRepository(
        db,
        clock: DateTime.now,
        newId: () => 'id${ids++}',
      );
      final deck = (await tester.runAsync(
        () => repository.createDeck('영단어 기본'),
      ))!;
      final client = FakeExtractionClient()
        ..todayAllowance = (dailyLimit: 30, used: 27);
      final photos = FakePhotoSource()
        ..libraryPhotos = [for (var i = 0; i < 4; i++) Future.value(testPhoto)];
      final preferences = await openPreferences(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [deckRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: ThemeMode.values.byName(mode),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => importFromPhoto(
                      context,
                      deck: deck.id,
                      origin: PhotoOrigin.album,
                      client: client,
                      photos: photos,
                      preferences: preferences,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      /// Pumps frames past what a read changes, as the bar never settles.
      Future<void> frames() async {
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
      }

      await tester.tap(find.text('open'));
      await frames();
      client.calls[0].answer.complete([
        word(front: 'face', meaning: '직면하다', partOfSpeech: '[동]'),
        word(front: 'include', meaning: '포함하다', partOfSpeech: '[동]'),
      ]);
      await frames();
      client.calls[1].answer.completeError(const ModelFailed());
      await frames();
      await shot(tester, '26-photo-reading');

      client.calls[2].answer.complete([
        word(front: 'strategy', meaning: '전략, 계획', partOfSpeech: '[명]'),
        word(front: 'in addition', meaning: '~뿐만 아니라', topic: '빈출 숙어'),
      ]);
      await frames();
      await tester.tap(find.text(ko.photoDrop));
      await tester.pumpAndSettle();
      await shot(tester, '26a-photo-groups');

      await unmount(tester);
      semantics.dispose();
    });

    testWidgets('sharing in $mode', skip: !_capture, (tester) async {
      phone(tester);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var ids = 0;
      final repository = DeckRepository(
        db,
        clock: DateTime.now,
        newId: () => 'id${ids++}',
      );
      await tester.runAsync(() async {
        final deck = await repository.createDeck('영단어 기본');
        await repository.addCard(
          deck.id,
          front: [const TextContent('lucid')],
          back: [const TextContent('명쾌한')],
        );
      });
      final spanish = publicDeck(
        'spanish',
        name: '스페인어 동물',
        ownerName: '보라',
        description: '자주 쓰는 동물 이름',
        cards: 3,
        copies: 12,
      );
      final server = FakeSharingServer(
        decks: [
          spanish,
          publicDeck(
            'jlpt',
            name: 'JLPT N3 한자',
            ownerName: '민준',
            owner: '00000000-0000-4000-8000-00000000000c',
            cards: 240,
            copies: 3,
            publishedAt: DateTime.utc(2026, 10, 14),
          ),
        ],
        cards: {
          spanish.id: [
            publicCard('perro', '개'),
            publicCard('gato', '고양이'),
            publicCard('pez', '물고기'),
          ],
        },
      );
      final sharing = SharingService(
        server: server,
        decks: repository,
        reachability: FakeReachability(),
        clock: DateTime.now,
      );
      final storage = await openStudyStorage(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deckRepositoryProvider.overrideWithValue(repository),
            sharingServiceProvider.overrideWithValue(sharing),
            ...homeOverrides(db, storage: storage),
          ],
          child: MaterialApp(
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: ThemeMode.values.byName(mode),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tap(tester, find.text(ko.tabDecks));
      await tap(tester, find.text('영단어 기본'));
      await tap(tester, find.byTooltip(ko.deckActions));
      await shot(tester, '25-deck-menu-publish');
      await tap(tester, find.text(ko.publish));
      await shot(tester, '26-publish-sheet');
      await tester.enterText(
        find.widgetWithText(AppTextField, ko.displayName),
        '아다',
      );
      await tap(tester, find.text(ko.publishAgreement));
      await tap(tester, find.text(ko.publishConfirm));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await shot(tester, '27-card-list-public');
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await shot(tester, '28-deck-list-public');

      await tap(tester, find.text(ko.browsePublicDecks));
      await shot(tester, '29-browse');
      await tap(tester, find.text('스페인어 동물'));
      await shot(tester, '30-public-deck');
      await tap(tester, find.text(ko.copyToMyDecks));
      await tap(tester, find.text(ko.copyIntoExistingDeck));
      await shot(tester, '31-import-sheet');
      // Above a tall sheet, where the barrier's centre is not.
      await tester.tapAt(const Offset(20, 100));
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip(ko.deckActions));
      await tap(tester, find.text(ko.reportDeck));
      await shot(tester, '32-report-sheet');
      // Above a tall sheet, where the barrier's centre is not.
      await tester.tapAt(const Offset(20, 100));
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip(ko.deckActions));
      await tap(tester, find.text(ko.blockUser));
      await shot(tester, '33-block-confirm');
      // Above a tall sheet, where the barrier's centre is not.
      await tester.tapAt(const Offset(20, 100));
      await tester.pumpAndSettle();

      await unmount(tester);
    });
  }
}
