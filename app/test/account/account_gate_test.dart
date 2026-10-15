import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smartman/account/account.dart';
import 'package:smartman/account/src/account_service.dart';
import 'package:smartman/account/src/sign_in_screen.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/main.dart';
import 'package:smartman/photo_import/photo_import.dart';
import 'package:smartman/shared/theme.dart';
import 'package:smartman/study/study.dart';
import 'package:smartman/sync/sync.dart';
import 'package:smartman/shared/ui/app_text_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/fake_sync_server.dart';
import 'fake_account_service.dart';
import 'fake_google_sign_in.dart';

const _ada = UserId('00000000-0000-4000-8000-00000000000a');

/// A session stored by an earlier run, whose access token expired an hour
/// ago, so the client refreshes it over the network before it is fresh again.
String _expiredSession() {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final expiredAt =
      DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch ~/
      1000;
  return jsonEncode({
    'access_token':
        '${part({'alg': 'HS256'})}.${part({'sub': _ada.value, 'exp': expiredAt})}.signature',
    'expires_in': 3600,
    'refresh_token': 'supabase-refresh-token',
    'token_type': 'bearer',
    'user': {
      'id': _ada.value,
      'aud': 'authenticated',
      'email': 'ada@example.com',
      'app_metadata': <String, Object?>{},
      'user_metadata': <String, Object?>{},
      'created_at': '2026-10-14T00:00:00Z',
    },
  });
}

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
  setUpAll(() async {
    scheduler = await Scheduler.load();
    GoogleSignInPlatform.instance = FakeGoogleSignIn();
  });

  /// Composes the app, signing in through [account], syncing with [server],
  /// and offering photo import.
  Future<void> pumpApp(
    WidgetTester tester,
    AccountService account, {
    FakeSyncServer? server,
  }) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final themeStorage = (await tester.runAsync(
      () => SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(
          allowList: themeStorageKeys,
        ),
      ),
    ))!;
    await tester.pumpWidget(
      composeApp(
        NativeDatabase.memory(),
        scheduler,
        account,
        server ?? FakeSyncServer(_ada),
        themeStorage,
        _NoExtraction(),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Unmounting the scope cancels drift's stream queries, whose cleanup timer
  // must fire before the test body ends.
  Future<void> unmountApp(WidgetTester tester) async {
    final sync = ProviderScope.containerOf(
      tester.element(find.byType(AccountGate, skipOffstage: false)),
    ).read(syncControllerProvider);
    sync.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// The buttons on screen that respond to a tap.
  List<String> enabledButtons(WidgetTester tester) => [
    for (final button in tester.widgetList<ButtonStyleButton>(
      find.byWidgetPredicate((w) => w is ButtonStyleButton),
    ))
      if (button.onPressed != null) (button.child! as Text).data!,
  ];

  testWidgets(
    'signed out, only the sign-in screen shows, in Korean, with Apple sign-in disabled',
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('ko')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await pumpApp(tester, FakeAccountService());

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.text('smartman'), findsOneWidget);
      expect(find.text('밀어서 답하고, 잊을 때쯤 다시 보여 주는 암기 카드.'), findsOneWidget);
      expect(find.text('Apple로 로그인 (준비 중)'), findsOneWidget);
      expect(enabledButtons(tester), ['Google로 로그인']);
      expect(find.byType(DeckListScreen), findsNothing);
      expect(find.byTooltip('계정'), findsNothing);
      await unmountApp(tester);
    },
  );

  testWidgets('signing in shows the deck list', (tester) async {
    final account = FakeAccountService();
    await pumpApp(tester, account);

    await tapAndSettle(tester, find.text('Sign in with Google'));

    expect(account.state, isA<SignedIn>());
    expect(find.byType(DeckListScreen), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
    await unmountApp(tester);
  });

  testWidgets(
    'a cancelled sign-in stays on the gate, and a failed one says why',
    (tester) async {
      final account = FakeAccountService()..cancelSignIn = true;
      await pumpApp(tester, account);

      await tapAndSettle(tester, find.text('Sign in with Google'));

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      // The control: the same tap with a failure does show a snack bar.
      account.failure = const AccountOffline(FormatException('offline'));
      await tapAndSettle(tester, find.text('Sign in with Google'));
      expect(
        find.text("Couldn't reach the server. Check your internet connection."),
        findsOneWidget,
      );
      expect(find.byType(SignInScreen), findsOneWidget);
      await unmountApp(tester);
    },
  );

  testWidgets('signing out from the account screen returns to the gate', (
    tester,
  ) async {
    final account = FakeAccountService(
      const SignedIn(userId: _ada, email: 'ada@example.com'),
    );
    await pumpApp(tester, account);

    await tapAndSettle(tester, find.byTooltip('Account'));
    await tapAndSettle(tester, find.text('Sign out'));

    expect(account.state, isA<SignedOut>());
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(AccountScreen), findsNothing);
    expect(find.byType(DeckListScreen), findsNothing);
    await unmountApp(tester);
  });

  group('no deck or study screen is reachable while signed out', () {
    /// Each screen the deck list leads to, and how to open it from there.
    final routes = <String, Future<void> Function(WidgetTester)>{
      'card list': (tester) => tapAndSettle(tester, find.text('French')),
      'card editor': (tester) async {
        await tapAndSettle(tester, find.text('French'));
        await tapAndSettle(tester, find.text('Add card'));
      },
      'study': (tester) async {
        await tapAndSettle(tester, find.text('French'));
        await tapAndSettle(tester, find.text('Study · 1'));
      },
      'photo import': (tester) =>
          tapAndSettle(tester, find.text('Create from photo')),
      'account': (tester) => tapAndSettle(tester, find.byTooltip('Account')),
    };
    for (final MapEntry(key: name, value: open) in routes.entries) {
      testWidgets('the $name screen closes when the session ends', (
        tester,
      ) async {
        final account = FakeAccountService(
          const SignedIn(userId: _ada, email: 'ada@example.com'),
        );
        await pumpApp(tester, account);
        await tapAndSettle(tester, find.text('New deck'));
        await tester.enterText(
          find.widgetWithText(AppTextField, 'Name'),
          'French',
        );
        await tapAndSettle(tester, find.text('Create'));
        await tapAndSettle(tester, find.text('French'));
        await tapAndSettle(tester, find.text('Add card'));
        await tester.enterText(
          find.widgetWithText(AppTextField, 'Question'),
          'Chat',
        );
        await tester.enterText(
          find.widgetWithText(AppTextField, 'Answer'),
          'cat',
        );
        await tapAndSettle(tester, find.text('Save'));
        await tester.pageBack();
        await tester.pumpAndSettle();
        await open(tester);
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        // The setup reached a screen over the deck list.
        expect(navigator.canPop(), isTrue);

        // The session ends outside the app, as an expired refresh token does.
        await account.signOut();
        await tester.pumpAndSettle();

        expect(navigator.canPop(), isFalse);
        expect(find.byType(SignInScreen), findsOneWidget);
        expect(enabledButtons(tester), ['Sign in with Google']);
        expect(find.byType(DeckListScreen), findsNothing);
        expect(find.byType(StudyScreen), findsNothing);
        expect(find.byType(AccountScreen), findsNothing);
        expect(find.byType(PhotoImportScreen), findsNothing);
        expect(find.text('French'), findsNothing);
        expect(find.text('Chat'), findsNothing);
        await unmountApp(tester);
      });
    }
  });

  group('with the network never answering', () {
    late GoTrueClient auth;
    final requests = <String>[];

    /// An account service over a Supabase Auth client whose server never
    /// answers, holding [storedSession] as the session an earlier run
    /// stored.
    Future<AccountService> offlineAccount(String? storedSession) async {
      auth = GoTrueClient(
        url: 'https://example.test/auth/v1',
        httpClient: MockClient((request) {
          requests.add(request.url.path);
          return Completer<http.Response>().future;
        }),
      );
      if (storedSession != null) {
        await auth.setInitialSession(storedSession);
        // The setup holds the expired session it asked for.
        expect(auth.currentSession?.isExpired, isTrue);
      }
      return GoogleAccountService.start(
        auth,
        GoogleSignIn.instance,
        clientId: null,
        serverClientId: 'web-client-id',
      );
    }

    testWidgets(
      'a restored session opens the deck list, and without one the gate stays',
      (tester) async {
        final server = FakeSyncServer(_ada)..stall = true;
        await pumpApp(
          tester,
          await offlineAccount(_expiredSession()),
          server: server,
        );

        expect(find.byType(DeckListScreen), findsOneWidget);
        expect(find.byType(SignInScreen), findsNothing);
        // The app opened while the session's refresh was still unanswered.
        expect(requests, ['/auth/v1/token']);
        await unmountApp(tester);
        auth.dispose();

        // The control: the same offline client with nothing stored.
        await pumpApp(tester, await offlineAccount(null), server: server);

        expect(find.byType(SignInScreen), findsOneWidget);
        expect(find.byType(DeckListScreen), findsNothing);
        await unmountApp(tester);
        auth.dispose();
      },
    );
  });

  testWidgets(
    'a build that cannot sign anyone in says so and shows no app, in Korean',
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('ko')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await pumpApp(
        tester,
        const UnavailableAccountService(
          AccountMisconfigured(FormatException('SUPABASE_URL is missing')),
        ),
      );

      expect(find.text('이 앱의 로그인 설정에 문제가 있어 로그인할 수 없습니다.'), findsOneWidget);
      expect(enabledButtons(tester), isEmpty);
      expect(find.text('Google로 로그인'), findsNothing);
      expect(find.byType(DeckListScreen), findsNothing);
      await unmountApp(tester);
    },
  );
}
