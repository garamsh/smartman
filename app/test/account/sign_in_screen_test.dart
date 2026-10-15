import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/account/account.dart';
import 'package:smartman/account/src/sign_in_screen.dart';
import 'package:smartman/shared/l10n/app_localizations.dart';
import 'package:smartman/shared/theme.dart';

import 'fake_account_service.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    AccountService service, {
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          theme: lightTheme,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SignInScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'welcomes with the app name and what it does, and never says it works without an account',
    (tester) async {
      await pumpScreen(tester, FakeAccountService());

      expect(find.text('smartman'), findsOneWidget);
      expect(
        find.text(
          'Flashcards you answer with a swipe, shown again just before you forget.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('without an account'), findsNothing);
      expect(
        find.bySemanticsLabel('smartman'),
        findsOneWidget,
        reason: 'the app name is the screen heading',
      );
      expect(
        tester.getSemantics(find.text('smartman')).flagsCollection.isHeader,
        isTrue,
      );
    },
  );

  testWidgets(
    'shows progress while signing in, then nothing more for a cancelled picker',
    (tester) async {
      final pending = Completer<void>();
      final service = FakeAccountService()
        ..cancelSignIn = true
        ..pendingSignIn = pending;
      await pumpScreen(tester, service);

      await tester.tap(find.text('Sign in with Google'));
      await tester.pump();
      expect(find.bySemanticsLabel('Signing in'), findsOneWidget);
      expect(find.text('Sign in with Google'), findsNothing);
      pending.complete();
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Signing in'), findsNothing);
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

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
    'the Apple slot is a disabled button, read out as such, in Korean',
    (tester) async {
      await pumpScreen(
        tester,
        FakeAccountService(),
        locale: const Locale('ko'),
      );

      final apple = find.widgetWithText(FilledButton, 'Apple로 로그인 (준비 중)');
      expect(tester.widget<FilledButton>(apple).onPressed, isNull);
      expect(
        tester.getSemantics(apple),
        matchesSemantics(
          label: 'Apple로 로그인 (준비 중)',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Google로 로그인'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('tap targets carry labels', (tester) async {
    await pumpScreen(tester, FakeAccountService());

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });
}
