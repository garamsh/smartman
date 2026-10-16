import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/l10n/app_localizations.dart';

/// The light and dark themes, with the tokens each must draw in.
const themeModes = {
  ThemeMode.light: AppColors.light,
  ThemeMode.dark: AppColors.dark,
};

/// Pumps [child] in a screen of the app's [themeMode] theme, in English, and
/// lets it settle unless it shows endless progress.
Future<void> pumpComponent(
  WidgetTester tester,
  Widget child, {
  ThemeMode themeMode = ThemeMode.light,
  bool disableAnimations = false,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.gutter),
            child: child,
          ),
        ),
      ),
    ),
  );
  settle ? await tester.pumpAndSettle() : await tester.pump();
}

/// Checks the tap target and contrast guidelines on what is on screen.
Future<void> meetsGuidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}
