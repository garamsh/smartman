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
import 'package:smartman/study/src/model.dart';
import 'package:smartman/study/src/rust/api/engine.dart' show Answer;
import 'package:smartman/study/study.dart';
import 'package:smartman/sync/sync.dart';

import '../account/fake_account_service.dart';
import '../home/home_data.dart';
import '../photo_import/fakes.dart';
import '../sharing/fakes.dart';
import '../sharing/sharing_service_test.dart' show publicCard, publicDeck;
import '../sync/fake_sync_server.dart';

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
            allowList: {...themeStorageKeys, ...detailStepStorageKeys},
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

      await tap(tester, find.text(ko.createManually));
      await shot(tester, '03-new-deck-sheet');
      await enter(ko.deckName, '영단어 기본');
      await tap(tester, find.text(ko.create));
      await tap(tester, find.text(ko.tabDecks));
      await tap(tester, find.text(ko.newDeckTitle));
      await shot(tester, '03b-new-deck-options');
      await tap(tester, find.text(ko.createManually));
      await enter(ko.deckName, '일본어 N3 한자');
      await tap(tester, find.text(ko.create));

      await tap(tester, find.text('영단어 기본'));
      await shot(tester, '04-card-list-empty');
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
        await tap(tester, find.text(ko.addCardManually));
        await enter(ko.cardFront, front);
        await enter(ko.cardBack, back);
        if (index == 0) await shot(tester, '05-card-editor');
        await tap(tester, find.text(ko.save));
      }
      await tap(tester, find.text(ko.newCard));
      await tap(tester, find.text(ko.addCardManually));
      await enter(ko.cardFront, 'Ephemeral');
      await enter(ko.cardBack, '순간의');
      await tap(tester, find.text(ko.save));
      await shot(tester, '06-duplicate-sheet');
      // Above a tall sheet, where the barrier's centre is not.
      await tester.tapAt(const Offset(20, 100));
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip(ko.close));
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
      await shot(tester, '16a-today');
      await tap(tester, find.text(ko.tabDecks));
      await tap(tester, find.text('영단어 기본'));

      await tap(tester, find.text(ko.studyDeck));
      // The session's start, with its guide above the card.
      await shot(tester, '12-study-start');
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
      await tester.ensureVisible(find.text(ko.termsOfService));
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
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deckRepositoryProvider.overrideWithValue(repository),
            ...homeOverrides(db),
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
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deckRepositoryProvider.overrideWithValue(repository),
            accountServiceProvider.overrideWithValue(
              FakeAccountService(
                const SignedIn(userId: _ada, email: 'ada@example.com'),
              ),
            ),
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
            home: PhotoImportScreen(
              deck: deck.id,
              client: client,
              photos: FakePhotoSource(),
              preferences: preferences,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await shot(tester, '20-photo-capture');
      await tap(tester, find.text(ko.photoTarget('영단어 기본')));
      await shot(tester, '21-photo-deck-sheet');
      await dismissSheet(tester);

      await tester.tap(find.byTooltip(ko.photoShutter));
      await tester.pump();
      await tester.pump();
      await shot(tester, '22-photo-extracting');
      client.answerCards(const [
        CandidateCard(
          front: 'serendipity',
          answer: '뜻밖의 행운',
          partOfSpeech: '[명]',
        ),
        CandidateCard(front: 'candid', answer: '솔직한', partOfSpeech: '[형]'),
        CandidateCard(front: 'lucid', answer: '맑은, 또렷한'),
      ]);
      await tester.pumpAndSettle();
      await shot(tester, '23-photo-review');

      await tap(tester, find.text(ko.retake));
      await tester.tap(find.byTooltip(ko.photoShutter));
      await tester.pump();
      await tester.pump();
      client.answerCards(const [
        CandidateCard(
          kind: CandidateKind.note,
          front: '논증이란?',
          answer: '전제와 결론으로 이루어진 문장들의 집합',
          short: '전제와 결론의 집합',
        ),
        CandidateCard(
          kind: CandidateKind.note,
          front: '연역 논증과 귀납 논증의 차이는?',
          answer: '연역은 전제에 담긴 내용만 말하고, 귀납은 새로운 정보를 준다',
          short: '귀납만 새로운 정보를 준다',
          step: DetailStep.keyPoints,
        ),
        CandidateCard(
          kind: CandidateKind.note,
          front: '전제 지시어는?',
          answer: '왜냐하면, ~이므로, ~때문에',
          step: DetailStep.detailed,
        ),
      ]);
      await tester.pumpAndSettle();
      await shot(tester, '23-photo-review-notes');

      await tap(tester, find.text(ko.retake));
      await tester.tap(find.byTooltip(ko.photoShutter));
      await tester.pump();
      await tester.pump();
      client.fail(const ModelFailed());
      await tester.pumpAndSettle();
      await shot(tester, '24-photo-failure');

      await unmount(tester);
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
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deckRepositoryProvider.overrideWithValue(repository),
            sharingServiceProvider.overrideWithValue(sharing),
            ...homeOverrides(db),
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
      await tap(tester, find.text(ko.importToMyDecks));
      await tap(tester, find.text(ko.importIntoExistingDeck));
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
