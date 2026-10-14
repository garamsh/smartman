import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smartman/account/account.dart';
import 'package:smartman/shared/l10n/app_localizations.dart';
import 'package:smartman/shared/theme.dart';

import 'fake_account_service.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    AccountService service, {
    Locale locale = const Locale('en'),
  }) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final storage = (await tester.runAsync(
      () => SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(
          allowList: themeStorageKeys,
        ),
      ),
    ))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountServiceProvider.overrideWithValue(service),
          themeStorageProvider.overrideWithValue(storage),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: ref.watch(themeModeProvider),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AccountScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('signed out, it offers Google sign-in, in Korean', (
    tester,
  ) async {
    await pumpScreen(tester, FakeAccountService(), locale: const Locale('ko'));

    expect(find.text('Google로 로그인'), findsOneWidget);
    expect(find.text('로그인하지 않아도 모든 기능을 쓸 수 있습니다.'), findsOneWidget);
    expect(find.text('로그아웃'), findsNothing);
  });

  testWidgets('signing in shows the account email and a sign-out action', (
    tester,
  ) async {
    final service = FakeAccountService();
    await pumpScreen(tester, service);
    expect(service.state, isA<SignedOut>());

    await tapAndSettle(tester, 'Sign in with Google');

    expect(find.text('Signed in as ada@example.com'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsNothing);
  });

  testWidgets('a restored session opens signed in', (tester) async {
    await pumpScreen(
      tester,
      FakeAccountService(const SignedIn(email: 'grace@example.com')),
    );

    expect(find.text('Signed in as grace@example.com'), findsOneWidget);
  });

  testWidgets('signing out returns to the signed-out state', (tester) async {
    await pumpScreen(
      tester,
      FakeAccountService(const SignedIn(email: 'ada@example.com')),
    );

    await tapAndSettle(tester, 'Sign out');

    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Signed in as ada@example.com'), findsNothing);
  });

  testWidgets('a cancelled sign-in shows nothing and stays signed out', (
    tester,
  ) async {
    final service = FakeAccountService()..cancelSignIn = true;
    await pumpScreen(tester, service);

    await tapAndSettle(tester, 'Sign in with Google');

    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Sign in with Google'), findsOneWidget);
    // The control: the same tap with a failure does show a snack bar.
    service.failure = const AccountRejected(FormatException('refused'));
    await tapAndSettle(tester, 'Sign in with Google');
    expect(find.byType(SnackBar), findsOneWidget);
  });

  final failures = <String, AccountFailure>{
    "Couldn't reach the server. Check your internet connection.":
        const AccountOffline(FormatException('offline')),
    "Sign-in isn't set up correctly in this app, so you can't sign in.":
        const AccountMisconfigured(FormatException('bad client')),
    'Google sign-in was refused. Please try again.': const AccountRejected(
      FormatException('refused'),
    ),
  };
  for (final MapEntry(key: message, value: failure) in failures.entries) {
    testWidgets('${failure.runtimeType} on sign-in is shown as "$message"', (
      tester,
    ) async {
      await pumpScreen(tester, FakeAccountService()..failure = failure);

      await tapAndSettle(tester, 'Sign in with Google');

      expect(find.text(message), findsOneWidget);
      expect(find.text('Sign in with Google'), findsOneWidget);
    });
  }

  testWidgets(
    'an offline sign-out signs out and reports the server out of reach',
    (tester) async {
      await pumpScreen(
        tester,
        FakeAccountService(const SignedIn(email: 'ada@example.com'))
          ..failure = const AccountOffline(FormatException('offline')),
      );

      await tapAndSettle(tester, 'Sign out');

      expect(
        find.text("Couldn't reach the server. Check your internet connection."),
        findsOneWidget,
      );
      expect(find.text('Sign in with Google'), findsOneWidget);
    },
  );

  testWidgets('a build without configuration says so and offers no sign-in', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      FakeAccountService(
        const AccountUnavailable(
          AccountMisconfigured(FormatException('SUPABASE_URL is missing')),
        ),
      ),
    );

    expect(
      find.text(
        "Sign-in isn't set up correctly in this app, so you can't sign in.",
      ),
      findsOneWidget,
    );
    expect(find.text('Sign in with Google'), findsNothing);
  });

  testWidgets('tap targets carry labels in both states', (tester) async {
    await pumpScreen(tester, FakeAccountService());
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    await tapAndSettle(tester, 'Sign in with Google');
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  testWidgets(
    'the display section offers system, light and dark, in Korean, and applies a choice at once',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpScreen(
        tester,
        FakeAccountService(),
        locale: const Locale('ko'),
      );
      Brightness brightness() =>
          Theme.of(tester.element(find.text('화면'))).brightness;
      SegmentedButton<ThemeMode> control() =>
          tester.widget(find.byType(SegmentedButton<ThemeMode>));
      expect(control().selected, {ThemeMode.system});
      expect(brightness(), Brightness.light);

      await tapAndSettle(tester, '다크');

      expect(control().selected, {ThemeMode.dark});
      expect(brightness(), Brightness.dark);

      await tapAndSettle(tester, '라이트');
      expect(brightness(), Brightness.light);

      await tapAndSettle(tester, '시스템');
      expect(control().selected, {ThemeMode.system});
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    },
  );
}
