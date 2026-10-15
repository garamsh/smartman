import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smartman/account/account.dart';
import 'package:smartman/shared/l10n/app_localizations.dart';
import 'package:smartman/shared/theme.dart';
import 'package:smartman/shared/ui/app_button.dart';
import 'package:smartman/shared/ui/app_list_row.dart';

import 'fake_account_data.dart';
import 'fake_account_service.dart';

const _ada = UserId('00000000-0000-4000-8000-00000000000a');

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    AccountService service, {
    Locale locale = const Locale('en'),
    AccountData? data,
    String? themeMode,
  }) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({'themeMode': ?themeMode});
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
          accountDataProvider.overrideWithValue(data ?? FakeAccountData()),
          syncStatusProvider.overrideWithValue(() => const Text('sync status')),
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

  /// Taps [text] and lets a dialog open over the sign-out progress
  /// indicator, which never settles.
  Future<void> tapAndOpen(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tapAndSettle(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('a restored session opens signed in', (tester) async {
    await pumpScreen(
      tester,
      FakeAccountService(
        const SignedIn(userId: _ada, email: 'grace@example.com'),
      ),
    );

    expect(find.text('grace@example.com'), findsOneWidget);
  });

  testWidgets(
    'a profile header with the initial, the email and the sync status, then the display and account sections, in Korean',
    (tester) async {
      await pumpScreen(
        tester,
        FakeAccountService(
          const SignedIn(userId: _ada, email: 'grace@example.com'),
        ),
        locale: const Locale('ko'),
      );

      double top(Finder finder) => tester.getRect(finder).top;
      final initial = find.text('G');
      expect(initial, findsOneWidget);
      expect(find.bySemanticsLabel('G'), findsNothing);
      final email = find.text('grace@example.com');
      expect(
        tester.getRect(initial).right,
        lessThan(tester.getRect(email).left),
      );
      expect(top(email), lessThan(top(find.text('sync status'))));
      // Display, then account with sign-out, each heading over rows.
      final display = find.text('화면');
      final account = find.descendant(
        of: find.byType(ListView),
        matching: find.text('계정'),
      );
      final signOut = find.text('로그아웃');
      expect(top(find.text('sync status')), lessThan(top(display)));
      expect(top(display), lessThan(top(find.text('다크'))));
      expect(top(find.text('다크')), lessThan(top(account)));
      expect(top(account), lessThan(top(signOut)));
      expect(tester.getSemantics(account).flagsCollection.isHeader, isTrue);
      expect(
        find.ancestor(of: signOut, matching: find.byType(AppListRow)),
        findsOneWidget,
      );
    },
  );

  testWidgets('signing out returns to the signed-out state', (tester) async {
    await pumpScreen(
      tester,
      FakeAccountService(
        const SignedIn(userId: _ada, email: 'ada@example.com'),
      ),
    );

    await tapAndSettle(tester, 'Sign out');

    expect(find.text('ada@example.com'), findsNothing);
  });

  testWidgets('signing out pushes, then clears the device\'s data', (
    tester,
  ) async {
    final data = FakeAccountData();
    await pumpScreen(
      tester,
      FakeAccountService(
        const SignedIn(userId: _ada, email: 'ada@example.com'),
      ),
      data: data,
    );

    await tapAndSettle(tester, 'Sign out');

    expect([data.pushes, data.clears], [1, 1]);
    expect(find.text("Some changes aren't synced"), findsNothing);
    expect(find.text('ada@example.com'), findsNothing);
  });

  testWidgets(
    'unsynced changes warn before signing out, in Korean, and cancelling keeps the account and its data',
    (tester) async {
      final data = FakeAccountData()..pushSucceeds = false;
      final service = FakeAccountService(
        const SignedIn(userId: _ada, email: 'ada@example.com'),
      );
      await pumpScreen(tester, service, data: data, locale: const Locale('ko'));

      await tapAndOpen(tester, '로그아웃');

      expect(find.text('동기화되지 않은 변경이 있어요'), findsOneWidget);
      await tapAndSettle(tester, '취소');
      expect(service.state, isA<SignedIn>());
      expect(data.clears, 0);
      expect(find.text('ada@example.com'), findsOneWidget);
    },
  );

  testWidgets('signing out anyway signs out and clears the device\'s data', (
    tester,
  ) async {
    final data = FakeAccountData()..pushSucceeds = false;
    final service = FakeAccountService(
      const SignedIn(userId: _ada, email: 'ada@example.com'),
    );
    await pumpScreen(tester, service, data: data);

    await tapAndOpen(tester, 'Sign out');
    await tapAndSettle(tester, 'Sign out anyway');

    expect(service.state, isA<SignedOut>());
    expect(data.clears, 1);
  });

  for (final mode in ['light', 'dark']) {
    testWidgets(
      'in the $mode theme the screen and the unsynced warning meet the tap target and contrast guidelines',
      (tester) async {
        Future<void> meetsGuidelines() async {
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        }

        await pumpScreen(
          tester,
          FakeAccountService(
            const SignedIn(userId: _ada, email: 'ada@example.com'),
          ),
          data: FakeAccountData()..pushSucceeds = false,
          themeMode: mode,
        );
        expect(
          Theme.of(tester.element(find.text('Display'))).brightness.name,
          mode,
        );
        await meetsGuidelines();

        await tapAndOpen(tester, 'Sign out');
        expect(find.text("Some changes aren't synced"), findsOneWidget);
        await meetsGuidelines();
      },
    );
  }

  testWidgets('data that cannot be cleared is reported after signing out', (
    tester,
  ) async {
    final data = FakeAccountData()
      ..clearFailure = const AccountDataNotCleared(FormatException('disk'));
    await pumpScreen(
      tester,
      FakeAccountService(
        const SignedIn(userId: _ada, email: 'ada@example.com'),
      ),
      data: data,
    );

    await tapAndSettle(tester, 'Sign out');

    expect(
      find.text(
        "Couldn't remove this device's data. It's removed when another account signs in.",
      ),
      findsOneWidget,
    );
    expect(find.text('ada@example.com'), findsNothing);
  });

  group('deleting the account', () {
    FakeAccountService signedIn() => FakeAccountService(
      const SignedIn(userId: _ada, email: 'ada@example.com'),
    );

    testWidgets(
      'is a red row with its note below sign-out, read as one node, in Korean',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpScreen(tester, signedIn(), locale: const Locale('ko'));

        final row = find.text('계정 삭제');
        expect(
          tester.getRect(find.text('로그아웃')).top,
          lessThan(tester.getRect(row).top),
        );
        expect(
          tester.widget<Text>(row).style?.color,
          AppColors.light.dontKnowText,
        );
        expect(
          tester.getSemantics(row),
          isSemantics(
            label: '계정 삭제\n계정을 삭제하면 서버와 이 기기에 있는 카드와 기록이 모두 지워져요. 되돌릴 수 없어요.',
            hasTapAction: true,
          ),
        );
        // The control: sign-out is drawn in ink, not red.
        expect(
          tester.widget<Text>(find.text('로그아웃')).style?.color,
          isNot(AppColors.light.dontKnowText),
        );
        semantics.dispose();
      },
    );

    testWidgets(
      'asks first, saying what goes and what stays, with cancel above a red delete, in Korean',
      (tester) async {
        await pumpScreen(tester, signedIn(), locale: const Locale('ko'));

        await tapAndSettle(tester, '계정 삭제');

        expect(find.text('계정을 삭제할까요?'), findsOneWidget);
        expect(
          find.text(
            '서버와 이 기기의 덱, 카드, 학습 기록이 모두 지워지고, 다른 사람이 복사한 덱과 Google 계정은 남아요.',
          ),
          findsOneWidget,
        );
        final cancel = find.widgetWithText(AppButton, '취소');
        final delete = find.widgetWithText(AppButton, '삭제');
        expect(
          tester.getRect(cancel).bottom,
          lessThanOrEqualTo(tester.getRect(delete).top),
        );
        expect(
          tester.widget<AppButton>(delete).variant,
          AppButtonVariant.destructiveFinal,
        );
      },
    );

    testWidgets('cancelling keeps the account and its data', (tester) async {
      final service = signedIn();
      final data = FakeAccountData();
      await pumpScreen(tester, service, data: data);

      await tapAndSettle(tester, 'Delete account');
      await tapAndSettle(tester, 'Cancel');

      expect(service.deletions, 0);
      expect(service.state, isA<SignedIn>());
      expect([data.pushes, data.clears], [0, 0]);
      expect(find.text('ada@example.com'), findsOneWidget);
    });

    testWidgets(
      'deleting signs out and clears the device\'s data without pushing first',
      (tester) async {
        final service = signedIn();
        final data = FakeAccountData();
        await pumpScreen(tester, service, data: data);

        await tapAndSettle(tester, 'Delete account');
        await tapAndSettle(tester, 'Delete');

        expect(service.deletions, 1);
        expect(service.state, isA<SignedOut>());
        expect([data.pushes, data.clears], [0, 1]);
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    for (final (failure, message) in [
      (
        const AccountOffline(FormatException('offline')),
        "Couldn't reach the server. Check your internet connection.",
      ),
      (
        const AccountRejected(FormatException('401')),
        "Couldn't delete your account. Try again.",
      ),
    ]) {
      testWidgets(
        'a deletion failing as ${failure.runtimeType} says so and keeps the account and its data',
        (tester) async {
          final service = signedIn()..deletionFailure = failure;
          final data = FakeAccountData();
          await pumpScreen(tester, service, data: data);

          await tapAndSettle(tester, 'Delete account');
          await tapAndSettle(tester, 'Delete');

          expect(find.text(message), findsOneWidget);
          expect(service.state, isA<SignedIn>());
          expect(data.clears, 0);
          expect(find.text('ada@example.com'), findsOneWidget);
        },
      );
    }

    testWidgets('data that cannot be cleared after deleting is reported', (
      tester,
    ) async {
      final service = signedIn();
      final data = FakeAccountData()
        ..clearFailure = const AccountDataNotCleared(FormatException('disk'));
      await pumpScreen(tester, service, data: data);

      await tapAndSettle(tester, 'Delete account');
      await tapAndSettle(tester, 'Delete');

      expect(service.deletions, 1);
      expect(
        find.text(
          "Couldn't remove this device's data. It's removed when another account signs in.",
        ),
        findsOneWidget,
      );
    });

    for (final mode in ['light', 'dark']) {
      testWidgets(
        'in the $mode theme the row and the confirmation meet the tap target and contrast guidelines',
        (tester) async {
          await pumpScreen(tester, signedIn(), themeMode: mode);
          await expectLater(tester, meetsGuideline(textContrastGuideline));

          await tapAndSettle(tester, 'Delete account');
          expect(find.text('Delete your account?'), findsOneWidget);
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        },
      );
    }
  });

  testWidgets('the sync status shows only while signed in', (tester) async {
    await pumpScreen(
      tester,
      FakeAccountService(
        const SignedIn(userId: _ada, email: 'ada@example.com'),
      ),
    );
    expect(find.text('sync status'), findsOneWidget);

    await tapAndSettle(tester, 'Sign out');

    expect(find.text('sync status'), findsNothing);
  });

  testWidgets(
    'an offline sign-out signs out and reports the server out of reach',
    (tester) async {
      await pumpScreen(
        tester,
        FakeAccountService(
          const SignedIn(userId: _ada, email: 'ada@example.com'),
        )..failure = const AccountOffline(FormatException('offline')),
      );

      await tapAndSettle(tester, 'Sign out');

      expect(
        find.text("Couldn't reach the server. Check your internet connection."),
        findsOneWidget,
      );
      expect(find.text('ada@example.com'), findsNothing);
    },
  );

  testWidgets('tap targets carry labels', (tester) async {
    await pumpScreen(
      tester,
      FakeAccountService(
        const SignedIn(userId: _ada, email: 'ada@example.com'),
      ),
    );

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  testWidgets(
    'the display section offers system, light and dark, in Korean, and applies a choice at once',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpScreen(
        tester,
        FakeAccountService(
          const SignedIn(userId: _ada, email: 'ada@example.com'),
        ),
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
