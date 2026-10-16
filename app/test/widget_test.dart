import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:smartman/account/account.dart';
import 'package:smartman/deck/deck.dart' show deckRepositoryProvider;
import 'package:smartman/design/app_text_field.dart';
import 'package:smartman/design/theme_choice.dart';
import 'package:smartman/home/home.dart';
import 'package:smartman/main.dart';
import 'package:smartman/photo_import/photo_import.dart';
import 'package:smartman/sharing/sharing.dart';
import 'package:smartman/study/study.dart';
import 'package:smartman/sync/sync.dart';

import 'account/fake_account_service.dart';
import 'sharing/fakes.dart';
import 'sync/fake_sync_server.dart';

const _ada = UserId('00000000-0000-4000-8000-00000000000a');

/// An extraction client the test never calls.
final class _NoExtraction implements ExtractionClient {
  @override
  Future<List<CandidateCard>?> extract(
    JpegPhoto photo, {
    required Future<void> cancel,
  }) => throw UnimplementedError('not called');
}

void main() {
  late Scheduler scheduler;
  late QueryExecutor executor;
  setUpAll(() async => scheduler = await Scheduler.load());

  /// Composes the app over an in-memory database and theme storage holding
  /// [themeMode] when given, signed in through [account] when given and as a
  /// restored session otherwise, extracting cards through [extraction], and
  /// sharing decks through [sharing].
  Future<void> pumpApp(
    WidgetTester tester, {
    String? themeMode,
    AccountService? account,
    ExtractionClient? extraction,
    SharingServer? sharing,
  }) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({'themeMode': ?themeMode});
    final themeStorage = (await tester.runAsync(
      () => SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(
          allowList: {...themeStorageKeys, ...detailLevelStorageKeys},
        ),
      ),
    ))!;
    executor = NativeDatabase.memory();
    await tester.pumpWidget(
      composeApp(
        executor,
        scheduler,
        account ??
            FakeAccountService(
              const SignedIn(userId: _ada, email: 'ada@example.com'),
            ),
        FakeSyncServer(_ada),
        themeStorage,
        extraction,
        sharing,
        FakeReachability(),
        '1.0.0',
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The brightness the deck list is drawn in.
  Brightness brightness(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(HomeScreen))).brightness;

  // Unmounting the scope cancels drift's stream queries, whose cleanup timer
  // must fire before the test body ends; disposing sync cancels the run a
  // write scheduled.
  Future<void> unmountApp(WidgetTester tester) async {
    ProviderScope.containerOf(
      tester.element(find.byType(AccountGate, skipOffstage: false)),
    ).read(syncControllerProvider).dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> enterText(WidgetTester tester, String label, String text) =>
      tester.enterText(find.widgetWithText(AppTextField, label), text);

  /// Shows the tab named [label].
  Future<void> showTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> createDeckAndOpen(WidgetTester tester, String name) async {
    // The first deck is made from the first-run home, later ones from the
    // decks tab's new-deck sheet.
    if (find.text('Create by hand').evaluate().isEmpty) {
      await showTab(tester, 'Decks');
      await tester.tap(find.text('New deck'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Create by hand'));
    await tester.pumpAndSettle();
    await enterText(tester, 'Deck name', name);
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await showTab(tester, 'Decks');
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  Future<void> addCard(WidgetTester tester, String front, String back) async {
    await tester.tap(find.text('Add card'));
    await tester.pumpAndSettle();
    await enterText(tester, 'Question', front);
    await enterText(tester, 'Answer', back);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('photo import is offered only with an extraction client', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('Create by hand'), findsOneWidget);
    expect(find.text('Create from photo'), findsNothing);
    await unmountApp(tester);

    await pumpApp(tester, extraction: _NoExtraction());
    expect(find.text('Create from photo'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets(
    'the composed app gives every new row a version 7 uuid in canonical lowercase form',
    (tester) async {
      final version7 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      await pumpApp(tester);
      await createDeckAndOpen(tester, 'French');
      await addCard(tester, 'chat', 'cat');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AccountGate, skipOffstage: false)),
      );
      final decks = container.read(deckRepositoryProvider);

      final ids = (await tester.runAsync(() async {
        final deck = (await decks.watchDecks().first).single;
        final card = (await decks.listCards(deck.id)).single;
        return [
          deck.id.value,
          card.id.value,
          container.read(studyRepositoryProvider).newReviewId().value,
        ];
      }))!;

      expect(ids, everyElement(matches(version7)));
      expect(ids.toSet(), hasLength(3));
      await unmountApp(tester);
    },
  );

  testWidgets('sharing is offered only with a sharing server', (tester) async {
    await pumpApp(tester);
    expect(find.byTooltip('Account'), findsOneWidget);
    expect(find.text('Browse public decks'), findsNothing);
    await createDeckAndOpen(tester, 'French');
    await tester.tap(find.byTooltip('Deck actions'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Publish'), findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Browse public decks'), findsNothing);
    await tester.tap(find.text('New deck'));
    await tester.pumpAndSettle();
    expect(find.text('Copy a public deck'), findsNothing);
    await unmountApp(tester);

    await pumpApp(tester, sharing: FakeSharingServer());
    await tester.tap(find.text('Browse public decks'));
    await tester.pumpAndSettle();
    expect(
      find.text('No public decks yet. Publish one of yours to be the first.'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await createDeckAndOpen(tester, 'French');
    await tester.tap(find.byTooltip('Deck actions'));
    await tester.pumpAndSettle();
    expect(find.text('Publish'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Browse public decks'), findsOneWidget);
    await tester.tap(find.text('New deck'));
    await tester.pumpAndSettle();
    expect(find.text('Copy a public deck'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets(
    'opens on the first-run home, which offers only the ways to start this build has',
    (tester) async {
      await pumpApp(tester);

      expect(find.bySemanticsLabel('smartman'), findsOneWidget);
      expect(find.text('Shall we make your first deck?'), findsOneWidget);
      expect(
        find.text(
          "Take a photo of a vocabulary page and we'll make the cards for you. You can also type them in.",
        ),
        findsOneWidget,
      );
      expect(find.text('Create by hand'), findsOneWidget);
      expect(find.text('Browse public decks'), findsNothing);
      // The bottom bar waits for the first deck.
      expect(find.text('New deck'), findsNothing);
      await unmountApp(tester);

      await pumpApp(
        tester,
        extraction: _NoExtraction(),
        sharing: FakeSharingServer(),
      );
      expect(find.text('Create from photo'), findsOneWidget);
      await tester.tap(find.text('Browse public decks'));
      await tester.pumpAndSettle();
      expect(
        find.text('No public decks yet. Publish one of yours to be the first.'),
        findsOneWidget,
      );
      await unmountApp(tester);
    },
  );

  testWidgets('shows Korean when the device locale is not supported', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await pumpApp(tester);

    expect(find.text('첫 덱을 만들어 볼까요?'), findsOneWidget);
    expect(find.text('직접 만들기'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets(
    'a duplicate front offers open existing and add anyway, and add anyway stores it',
    (tester) async {
      await pumpApp(tester);
      await createDeckAndOpen(tester, 'French');

      await addCard(tester, 'Chat', 'cat');
      await addCard(tester, 'Chat', 'chat (talk)');

      expect(find.text('This deck already has this card'), findsOneWidget);
      expect(find.text('Open existing card'), findsOneWidget);
      await tester.tap(find.text('Add anyway'));
      await tester.pumpAndSettle();

      // The deck holds both cards; their answers show once tapped.
      expect(find.text('Chat'), findsNWidgets(2));
      for (final row in find.text('Chat').evaluate().toList()) {
        await tester.tap(find.byWidget(row.widget));
      }
      await tester.pumpAndSettle();
      expect(find.text('cat'), findsOneWidget);
      expect(find.text('chat (talk)'), findsOneWidget);
      await unmountApp(tester);
    },
  );

  testWidgets('a card with an empty side is not saved and says why', (
    tester,
  ) async {
    await pumpApp(tester);
    await createDeckAndOpen(tester, 'French');

    await addCard(tester, 'Chat', '');

    expect(find.text('Enter some text'), findsOneWidget);
    expect(find.text('Edit card'), findsNothing);
    expect(find.widgetWithText(AppBar, 'Add card'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('a storage failure is shown to the user', (tester) async {
    await pumpApp(tester);
    await createDeckAndOpen(tester, 'French');
    // The database now refuses every write.
    await tester.runAsync(() => executor.runCustom('PRAGMA query_only = ON'));

    await addCard(tester, 'Chat', 'cat');

    expect(
      find.text(
        "Couldn't read or write the device's storage. Please try again.",
      ),
      findsOneWidget,
    );
    await unmountApp(tester);
  });

  testWidgets("a deck's Study button opens a session on its cards", (
    tester,
  ) async {
    await pumpApp(tester);
    await createDeckAndOpen(tester, 'French');
    await addCard(tester, 'Chat', 'cat');

    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();

    expect(find.text('Chat'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.text('0/1'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets(
    "the today card counts today's cards across every deck, and Study all studies them in one session",
    (tester) async {
      await pumpApp(tester);
      await createDeckAndOpen(tester, 'French');
      await addCard(tester, 'Chat', 'cat');
      await addCard(tester, 'Chien', 'dog');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await createDeckAndOpen(tester, 'German');
      await addCard(tester, 'Hund', 'dog');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await showTab(tester, 'Today');

      expect(find.bySemanticsLabel('3 cards for today'), findsOneWidget);
      await tester.tap(find.text('Study all'));
      await tester.pumpAndSettle();

      expect(find.text('0/3'), findsOneWidget);
      await unmountApp(tester);
    },
  );

  testWidgets(
    'with no card left and none answered today, Keep studying and the deck\'s Study open a session with nothing to study',
    (tester) async {
      await pumpApp(tester);
      await createDeckAndOpen(tester, 'French');

      await tester.tap(find.text('Study'));
      await tester.pumpAndSettle();
      expect(find.text('No cards to study today'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await showTab(tester, 'Today');

      expect(find.text("You've done today's cards"), findsOneWidget);
      await tester.tap(find.text('Keep studying'));
      await tester.pumpAndSettle();
      expect(find.text('No cards to study today'), findsOneWidget);
      await unmountApp(tester);
    },
  );

  testWidgets(
    'with no card left and one answered today, Keep studying and the deck\'s Study open the completion card',
    (tester) async {
      await pumpApp(tester);
      await createDeckAndOpen(tester, 'French');
      await addCard(tester, 'Chat', 'cat');
      await tester.tap(find.text('Study'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Know'));
      await tester.pumpAndSettle();
      // The deck page reads its count again when the session closes, so wait
      // until the answer's review row is stored: its write runs on real time,
      // and its continuations on frames.
      for (var tries = 0; ; tries++) {
        final rows = await tester.runAsync(
          () => executor.runSelect('SELECT COUNT(*) AS n FROM reviews', []),
        );
        if (rows!.single['n'] == 1) break;
        if (tries == 100) fail('the answer was never stored');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Study'));
      await tester.pumpAndSettle();
      expect(find.text('Done for today'), findsOneWidget);
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await showTab(tester, 'Today');

      expect(find.text("You've done today's cards"), findsOneWidget);
      await tester.tap(find.text('Keep studying'));
      await tester.pumpAndSettle();
      expect(find.text('Done for today'), findsOneWidget);
      await unmountApp(tester);
    },
  );

  testWidgets('the deck list opens the account screen, signed in', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountScreen), findsOneWidget);
    expect(find.text('ada@example.com'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('the theme follows the system until a choice overrides it', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpApp(tester);
    expect(brightness(tester), Brightness.dark);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(brightness(tester), Brightness.light);

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(brightness(tester), Brightness.dark);

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(brightness(tester), Brightness.light);
    await unmountApp(tester);
  });

  testWidgets('a stored choice applies from the first frame', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await pumpApp(tester, themeMode: 'dark');

    expect(brightness(tester), Brightness.dark);
    await unmountApp(tester);
  });

  for (final mode in ['light', 'dark']) {
    testWidgets(
      'in the $mode theme the sign-in screen, every tab, every deck screen and the account screen meet the tap target and contrast guidelines',
      (tester) async {
        Future<void> meetsGuidelines() async {
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        }

        await pumpApp(tester, themeMode: mode, account: FakeAccountService());
        expect(
          Theme.of(tester.element(find.text('Continue with Google')))
              .brightness,
          Brightness.values.byName(mode),
        );
        await meetsGuidelines();
        await tester.tap(find.text('Continue with Google'));
        await tester.pumpAndSettle();
        expect(brightness(tester).name, mode);
        await meetsGuidelines();
        await tester.tap(find.text('Create by hand'));
        await tester.pumpAndSettle();
        expect(find.text('Create a deck'), findsOneWidget);
        expect(find.text('You can change the name later.'), findsOneWidget);
        await meetsGuidelines();
        await enterText(tester, 'Deck name', 'French');
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();
        // The 오늘 tab with its done card, and the 기록 and 덱 tabs.
        await meetsGuidelines();
        await showTab(tester, 'Record');
        await meetsGuidelines();
        await showTab(tester, 'Decks');
        await meetsGuidelines();
        await tester.tap(find.text('New deck'));
        await tester.pumpAndSettle();
        await meetsGuidelines();
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();
        await tester.tap(find.text('French'));
        await tester.pumpAndSettle();
        await meetsGuidelines();
        await addCard(tester, 'Chat', 'cat');
        await meetsGuidelines();

        await tester.tap(find.byTooltip('Deck actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rename'));
        await tester.pumpAndSettle();
        expect(find.text('Rename deck'), findsOneWidget);
        await meetsGuidelines();
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Deck actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete deck'));
        await tester.pumpAndSettle();
        expect(find.text('Delete "French"?'), findsOneWidget);
        await meetsGuidelines();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Add card'));
        await tester.pumpAndSettle();
        await enterText(tester, 'Question', 'Chien');
        await meetsGuidelines();
        await enterText(tester, 'Question', 'chat');
        await enterText(tester, 'Answer', 'chat (talk)');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('This deck already has this card'), findsOneWidget);
        await meetsGuidelines();
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Chat'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Search cards'));
        await tester.pumpAndSettle();
        // The answer shown, and the search open in the top bar.
        await meetsGuidelines();
        await tester.tap(find.byTooltip('Close search'));
        await tester.pumpAndSettle();
        await tester.longPress(find.text('Chat'));
        await tester.pumpAndSettle();
        await meetsGuidelines();
        await tester.tap(find.byTooltip('Delete card'));
        await tester.pumpAndSettle();
        expect(find.text('Delete this card?'), findsOneWidget);
        await meetsGuidelines();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        // The decks tab with a deck row and its progress.
        await meetsGuidelines();

        await tester.tap(find.text('Select'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('French'));
        await tester.pumpAndSettle();
        await meetsGuidelines();
        await tester.tap(find.byTooltip('Clear selection'));
        await tester.pumpAndSettle();
        // The 오늘 tab with its today card, the next seven days and a deck.
        await showTab(tester, 'Today');
        await meetsGuidelines();

        await tester.tap(find.byTooltip('Account'));
        await tester.pumpAndSettle();
        await meetsGuidelines();
        await tester.ensureVisible(find.text('Terms of Service'));
        await tester.pumpAndSettle();
        await meetsGuidelines();
        await unmountApp(tester);
      },
    );
  }
}
