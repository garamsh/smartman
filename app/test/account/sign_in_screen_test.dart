import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/account/account.dart';
import 'package:smartman/account/src/google_button.dart';
import 'package:smartman/account/src/legal.dart';
import 'package:smartman/account/src/sign_in_screen.dart';
import 'package:smartman/shared/l10n/app_localizations.dart';
import 'package:smartman/shared/theme.dart';

import 'fake_account_service.dart';

/// The stacked logo, read as the app's name.
final _logo = find.bySemanticsLabel('smartman');

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    AccountService service, {
    Locale locale = const Locale('en'),
    ThemeMode themeMode = ThemeMode.light,
    LegalLinks legal = const LegalLinks(),
    LinkOpener? opener,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountServiceProvider.overrideWithValue(service),
          legalLinksProvider.overrideWithValue(legal),
          if (opener != null) linkOpenerProvider.overrideWithValue(opener),
        ],
        child: MaterialApp(
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeMode,
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

      expect(_logo, findsOneWidget);
      expect(
        find.text(
          'Swipe to answer,\nand meet each card again just before you forget',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('without an account'), findsNothing);
      expect(
        find.bySemanticsLabel('smartman'),
        findsOneWidget,
        reason: 'the stacked logo is read as the app name',
      );
      expect(
        tester.getSemantics(_logo).flagsCollection.isHeader,
        isTrue,
        reason: 'the app name is the screen heading',
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

      await tester.tap(find.text('Continue with Google'));
      await tester.pump();
      expect(find.bySemanticsLabel('Signing in'), findsOneWidget);
      expect(find.text('Continue with Google'), findsNothing);
      pending.complete();
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Signing in'), findsNothing);
      expect(find.text('Continue with Google'), findsOneWidget);
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

      await tapAndSettle(tester, 'Continue with Google');

      expect(find.text(message), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
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

      final apple = find.widgetWithText(TextButton, 'Apple로 계속하기 · 준비 중');
      expect(tester.widget<TextButton>(apple).onPressed, isNull);
      expect(
        tester.getSemantics(apple),
        matchesSemantics(
          label: 'Apple로 계속하기 · 준비 중',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      expect(
        tester
            .widget<GoogleSignInButton>(
              find.widgetWithText(GoogleSignInButton, 'Google로 계속하기'),
            )
            .onPressed,
        isNotNull,
      );
      // Subordinate to Google's button: shorter, and a text button.
      expect(
        tester.getSize(apple).height,
        lessThan(tester.getSize(find.byType(GoogleSignInButton)).height),
      );
    },
  );

  for (final (mode, style) in [
    (ThemeMode.light, GoogleButtonStyle.light),
    (ThemeMode.dark, GoogleButtonStyle.dark),
  ]) {
    testWidgets(
      "in the ${mode.name} theme the Google button is Google's ${mode.name} button, with the G mark and the label, and the screen meets the tap target and contrast guidelines",
      (tester) async {
        final service = FakeAccountService();
        await pumpScreen(tester, service, themeMode: mode);

        final button = find.byType(GoogleSignInButton);
        final mark = find.descendant(
          of: button,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Image &&
                widget.image == AssetImage(style.mark) &&
                widget.width == GoogleButtonStyle.markSize,
          ),
        );
        expect(mark, findsOneWidget);
        expect(
          find.descendant(
            of: button,
            matching: find.text('Continue with Google'),
          ),
          findsOneWidget,
        );
        // The mark sits before the label.
        expect(
          tester.getRect(mark).right,
          lessThan(tester.getRect(find.text('Continue with Google')).left),
        );
        final surface = tester.widget<Material>(
          find.descendant(of: button, matching: find.byType(Material)).first,
        );
        expect(surface.color, style.fill);
        expect(
          (surface.shape! as RoundedRectangleBorder).side.color,
          style.stroke,
        );
        expect(tester.getSemantics(button).flagsCollection.isButton, isTrue);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(service.state, isA<SignedIn>());
      },
    );
  }

  testWidgets('the logo sits in the upper part and the buttons at the bottom', (
    tester,
  ) async {
    await pumpScreen(tester, FakeAccountService());
    final screen = tester.getSize(find.byType(Scaffold));

    final wordmark = tester.getCenter(_logo);
    expect(wordmark.dy, greaterThan(screen.height / 6));
    expect(wordmark.dy, lessThan(screen.height / 2));
    expect(
      tester.getRect(find.byType(GoogleSignInButton)).top,
      greaterThan(screen.height / 2),
    );
  });

  testWidgets('tap targets carry labels', (tester) async {
    await pumpScreen(tester, FakeAccountService());

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  testWidgets(
    'the terms the user agrees to are named under the buttons, and a link without a document opens the coming-soon page',
    (tester) async {
      final opened = <Uri>[];
      await pumpScreen(
        tester,
        FakeAccountService(),
        opener: (uri) async {
          opened.add(uri);
          return true;
        },
      );

      expect(
        find.text(
          'By continuing, you agree to the Terms of Service and the Privacy Policy.',
        ),
        findsOneWidget,
      );
      await tapAndSettle(tester, 'Terms of Service');

      expect(find.byType(ComingSoonScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Terms of Service'), findsOneWidget);
      expect(
        find.text("This isn't ready yet. It will open here soon."),
        findsOneWidget,
      );
      expect(opened, isEmpty);
    },
  );

  testWidgets(
    'a link with a document opens it outside the app, and one that does not open says so',
    (tester) async {
      final privacy = Uri.parse('https://example.test/privacy');
      final opened = <Uri>[];
      var opens = true;
      await pumpScreen(
        tester,
        FakeAccountService(),
        legal: LegalLinks(privacy: privacy),
        opener: (uri) async {
          opened.add(uri);
          return opens;
        },
      );

      await tapAndSettle(tester, 'Privacy Policy');
      expect(opened, [privacy]);
      // Control: an opened link says nothing and leaves the screen.
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(ComingSoonScreen), findsNothing);

      opens = false;
      await tapAndSettle(tester, 'Privacy Policy');
      expect(opened, [privacy, privacy]);
      expect(
        find.text("Couldn't open the link. Please try again."),
        findsOneWidget,
      );
    },
  );
}
