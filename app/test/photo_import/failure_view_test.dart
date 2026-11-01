import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/design/mascot.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/l10n/app_localizations.dart';
import 'package:smartman/photo_import/src/failure.dart';
import 'package:smartman/photo_import/src/failure_message.dart';
import 'package:smartman/photo_import/src/failure_view.dart';

import '../word_breaks.dart';

void main() {
  for (final failure in const [ModelFailed(), NoCardsFound()]) {
    testWidgets(
      '$failure draws the sad mascot over its words, none of it red',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: FailureView(
              failure: failure,
              onRetry: null,
              onRetake: () {},
              retakeLabel: 'Retake',
              onOpenSettings: null,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final mascot = find.byType(Mascot);
        expect(tester.widget<Mascot>(mascot).expression, MascotExpression.sad);
        for (final text in tester.widgetList<Text>(find.byType(Text))) {
          expect(text.style?.color, isNot(AppColors.light.dontKnowText));
        }
        expect(find.byType(Icon), findsOneWidget, reason: 'the close alone');
      },
    );
  }

  testWidgets(
    'the refused-access message breaks only between Korean words on a phone, '
    'and reads as written (#454)',
    (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FailureView(
            failure: const PhotoAccessDenied('denied'),
            onRetry: null,
            onRetake: () {},
            retakeLabel: '다시 찍기',
            onOpenSettings: () {},
          ),
        ),
      );
      final message = describePhotoImportFailure(
        lookupAppLocalizations(const Locale('ko')),
        const PhotoAccessDenied('denied'),
      );

      expectBreaksBetweenWords(tester, message);
      expect(find.bySemanticsLabel(message), findsOneWidget);
      semantics.dispose();
    },
  );
}
