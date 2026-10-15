import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/shared/l10n/app_localizations.dart';
import 'package:smartman/shared/theme.dart';
import 'package:smartman/study/src/rust/api/engine.dart';
import 'package:smartman/study/src/session.dart';
import 'package:smartman/study/src/session_scroll.dart';

import 'fixtures.dart';

/// Every built previous card, on screen or not.
final _built = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label?.startsWith('Front: ') ?? false),
  skipOffstage: false,
);

Finder _card(int position) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label?.startsWith('Front: c$position front.') ??
          false),
);

void main() {
  testWidgets(
    'a stack of 300 answers above the current card builds only the cards near the view, and the first is still reached and toggled',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final created = DateTime.utc(2026, 9, 1);
      final cards = [
        for (var position = 0; position < 300; position++)
          PreviousCard(
            position: position,
            card: textCard('c$position', createdAt: created),
            answer: Answer.know,
            changed: false,
          ),
      ];
      final toggled = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: 360,
                child: SessionScroll(
                  cards: cards,
                  onToggle: toggled.add,
                  current: const SizedBox(height: 120),
                  currentCenter: 280,
                  currentMaxHeight: 120,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(cards, hasLength(300));
      expect(_card(299), findsOneWidget, reason: 'it opens at the newest');
      expect(_built.evaluate().length, lessThan(20));

      // Control: the oldest card is built once scrolled to, and toggles.
      await tester.scrollUntilVisible(
        _card(0),
        -2000,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
      await tester.tap(_card(0));
      expect(toggled, [0]);
      expect(_built.evaluate().length, lessThan(20));
    },
  );
}
