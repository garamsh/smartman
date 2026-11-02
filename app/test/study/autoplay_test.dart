import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:knowno/design/theme.dart';
import 'package:knowno/l10n/app_localizations.dart';
import 'package:knowno/study/study.dart';

import '../contrast.dart';
import 'study_storage.dart';

void main() {
  Future<void> drawRow(
    WidgetTester tester,
    SharedPreferencesWithCache storage, {
    ThemeMode themeMode = ThemeMode.light,
  }) => tester.pumpWidget(
    ProviderScope(
      overrides: [studyStorageProvider.overrideWithValue(storage)],
      child: MaterialApp(
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AutoplayAudioRow()),
      ),
    ),
  );

  bool switchOn(WidgetTester tester) =>
      tester.widget<Switch>(find.byType(Switch)).value;

  testWidgets(
    'the autoplay row starts on, and each tap turns it over and stores it on the device (ADR 0112)',
    (tester) async {
      final storage = await openStudyStorage(tester);
      expect(storage.getBool(autoplayAudioKey), isNull, reason: 'setup');
      await drawRow(tester, storage);
      expect(find.text('Play front sound automatically'), findsOneWidget);
      expect(switchOn(tester), isTrue, reason: 'on while unset');

      await tester.tap(find.byType(AutoplayAudioRow));
      await tester.pumpAndSettle();
      expect(switchOn(tester), isFalse);
      expect(storage.getBool(autoplayAudioKey), isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(switchOn(tester), isTrue);
      expect(storage.getBool(autoplayAudioKey), isTrue);
    },
  );

  testWidgets('the row shows the setting stored off', (tester) async {
    final storage = await openStudyStorage(tester, autoplay: false);
    await drawRow(tester, storage);

    expect(switchOn(tester), isFalse);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'in the ${mode.name} theme the row meets the tap target, label and contrast guidelines',
      (tester) async {
        await drawRow(tester, await openStudyStorage(tester), themeMode: mode);
        final handle = tester.ensureSemantics();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        expectScreenTextReadable(tester);
        handle.dispose();
      },
    );
  }
}
