import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/l10n/app_localizations.dart';
import 'package:smartman/photo_import/src/failure.dart';
import 'package:smartman/photo_import/src/failure_message.dart';
import 'package:smartman/photo_import/src/failure_view.dart';

import '../word_breaks.dart';

void main() {
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
