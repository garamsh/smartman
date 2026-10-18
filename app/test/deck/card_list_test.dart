import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/l10n/app_localizations.dart';

import 'whole_cards.dart';

void main() {
  testWidgets(
    'a split row draws a whole card as its front with its blanks filled, where a plain card stays split',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(
            body: Column(
              children: [
                CardSplitRow(
                  key: Key('whole'),
                  front: 'The capital of France is {{c::Paris}}',
                  back: 'The capital of France is Paris',
                ),
                CardSplitRow(key: Key('plain'), front: 'Chat', back: 'cat'),
              ],
            ),
          ),
        ),
      );

      final whole = find.byKey(const Key('whole'));
      expect(blanksUnder(whole), {'Paris': true});
      expect(
        find.descendant(of: whole, matching: find.byType(VerticalDivider)),
        findsNothing,
      );
      // Control: the plain card keeps its two halves.
      final plain = find.byKey(const Key('plain'));
      expect(
        find.descendant(of: plain, matching: find.byType(VerticalDivider)),
        findsOneWidget,
      );
      expect(find.text('cat'), findsOneWidget);
    },
  );
}
