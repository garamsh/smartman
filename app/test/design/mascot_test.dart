import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowno/design/mascot.dart';
import 'package:knowno/design/theme.dart';

void main() {
  for (final expression in MascotExpression.values) {
    testWidgets('${expression.name} draws its own file, unread by a screen '
        'reader', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Mascot(expression: expression, size: AppSize.mascotMedium),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as AssetImage).assetName,
        'assets/brand/knowno-${expression.name}.png',
      );
      expect(image.width, AppSize.mascotMedium);
      expect(
        find.descendant(
          of: find.byType(Mascot),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    test('${expression.name} is bundled at every density', () {
      for (final density in ['', '2.0x/', '3.0x/']) {
        final file = File(
          'assets/brand/${density}knowno-${expression.name}.png',
        );
        expect(file.existsSync(), isTrue, reason: file.path);
      }
    });
  }
}
