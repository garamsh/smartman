import 'dart:io';

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
import 'package:smartman/deck/deck.dart';
import 'package:smartman/main.dart';
import 'package:smartman/photo_import/photo_import.dart';
import 'package:smartman/shared/database.dart';
import 'package:smartman/shared/l10n/app_localizations.dart';
import 'package:smartman/shared/theme.dart';
import 'package:smartman/shared/ui/app_text_field.dart';
import 'package:smartman/sharing/sharing.dart';
import 'package:smartman/study/study.dart';
import 'package:smartman/sync/sync.dart';

import '../account/fake_account_service.dart';
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
    Future<void> shot(WidgetTester tester, String name) => expectLater(
      find.byType(MaterialApp).first,
      matchesGoldenFile('../../build/screenshots/$mode/$name.png'),
    );

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

    /// Decodes the images on screen, which a test otherwise draws blank.
    Future<void> loadImages(WidgetTester tester) async {
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          await precacheImage((element.widget as Image).image, element);
        }
      });
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
            allowList: themeStorageKeys,
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
          null,
          null,
          FakeReachability(),
        ),
      );
      await tester.pumpAndSettle();
      await loadImages(tester);
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

      await tap(tester, find.text(ko.newDeck));
      await shot(tester, '03-new-deck-sheet');
      await enter(ko.deckName, '영단어 기본');
      await tap(tester, find.text(ko.create));
      await tap(tester, find.text(ko.newDeck));
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
        await enter(ko.cardFront, front);
        await enter(ko.cardBack, back);
        if (index == 0) await shot(tester, '05-card-editor');
        await tap(tester, find.text(ko.save));
      }
      await tap(tester, find.text(ko.newCard));
      await enter(ko.cardFront, 'Ephemeral');
      await enter(ko.cardBack, '순간의');
      await tap(tester, find.text(ko.save));
      await shot(tester, '06-duplicate-sheet');
      // Above a tall sheet, where the barrier's centre is not.
      await tester.tapAt(const Offset(20, 100));
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip(ko.close));
      await shot(tester, '07-card-list');

      await tap(tester, find.byTooltip(ko.deckActions));
      await tap(tester, find.text(ko.rename));
      await shot(tester, '08-rename-sheet');
      await dismissSheet(tester);
      await tap(tester, find.byTooltip(ko.deckActions));
      await tap(tester, find.text(ko.deleteDeck));
      await shot(tester, '09-delete-deck-confirm');
      await tap(tester, find.text(ko.cancel));

      await tap(tester, find.text('meticulous'));
      await shot(tester, '10-card-editor-existing');
      await tap(tester, find.byTooltip(ko.deleteCard));
      await shot(tester, '11-delete-card-confirm');
      await tap(tester, find.text(ko.cancel));
      await tap(tester, find.byTooltip(ko.close));

      await tap(tester, find.text(ko.studyCount(4)));
      await shot(tester, '12-study-start');
      // The current card's centre, where StudyStyle places it at rest.
      final current = Offset(
        _phone.width / _density / 2,
        _phone.height / _density * 0.57,
      );
      for (final offset in [400.0, -400.0, 400.0, 400.0]) {
        await tester.dragFrom(current, Offset(offset, 0));
        await tester.pumpAndSettle();
      }
      await shot(tester, '13-study-session');
      await tester.dragFrom(current, const Offset(0, 400));
      await tester.pumpAndSettle();
      await shot(tester, '13b-study-scrolled-back');
      await tester.longPress(
        find
            .bySemanticsLabel(
              RegExp('^앞면: (ephemeral|meticulous|ubiquitous|resilient)\\.'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await shot(tester, '14-whole-card-sheet');
      await dismissSheet(tester);
      await tap(tester, find.byTooltip(ko.close));
      await shot(tester, '15-study-summary');
      await tap(tester, find.text(ko.done));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await shot(tester, '16-deck-list');
      await tester.longPress(find.text('영단어 기본'));
      await tester.pumpAndSettle();
      await shot(tester, '17-deck-list-selection');
      await tap(tester, find.byTooltip(ko.clearSelection));

      await tap(tester, find.byTooltip(ko.account));
      await shot(tester, '18-account');
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
      client.answer({
        'serendipity': '뜻밖의 행운',
        'candid': '솔직한',
        'lucid': '맑은, 또렷한',
      });
      await tester.pumpAndSettle();
      await shot(tester, '23-photo-review');

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
            deckSharingProvider.overrideWithValue(sharing),
            studyScreenProvider.overrideWithValue((decks) => const Scaffold()),
            todayProvider.overrideWithValue(
              (decks, builder) => Builder(
                builder: (context) =>
                    builder(context, const TodayCounted(review: 0, fresh: 1)),
              ),
            ),
            accountScreenProvider.overrideWithValue(Scaffold.new),
          ],
          child: MaterialApp(
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: ThemeMode.values.byName(mode),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const DeckListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

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

      await tap(tester, find.byTooltip(ko.browse));
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
