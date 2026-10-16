import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/src/card_preview.dart';
import 'package:smartman/design/theme.dart';

void main() {
  testWidgets('a short side sits vertically centred in its half', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: CardPreview(
              front: 'cat',
              back:
                  'a small domesticated carnivorous mammal with soft fur, '
                  'a short snout and retractable claws',
            ),
          ),
        ),
      ),
    );

    final front = find.text('cat');
    final half = find.ancestor(of: front, matching: find.byType(Expanded));
    expect(
      tester.getRect(half).height,
      greaterThan(CardPreview.minHeight),
      reason: 'the longer back grows the card',
    );
    expect(tester.getCenter(front).dy, closeTo(tester.getCenter(half).dy, 1));
  });
}
