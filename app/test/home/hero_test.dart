import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/home/src/hero.dart';

/// [colour] drawn over the opaque [ground].
Color _over(Color colour, Color ground) => Color.alphaBlend(colour, ground);

/// The WCAG 2.1 contrast ratio of two opaque colours.
double _contrast(Color a, Color b) {
  final (lighter, darker) = a.computeLuminance() > b.computeLuminance()
      ? (a, b)
      : (b, a);
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

void main() {
  for (final (name, colors) in [
    ('light', AppColors.light),
    ('dark', AppColors.dark),
  ]) {
    test(
      '$name: the shades derived from the tokens meet WCAG AA for text and 3:1 for marks and bars',
      () {
        final hero = colors.hero;
        // Text, at 4.5:1: the navy cards' quiet text on the navy.
        expect(
          _contrast(_over(heroQuiet(colors), hero), hero),
          greaterThanOrEqualTo(4.5),
        );
        // Marks and bars, at 3:1: the streak's flame on the navy, the today
        // card's bar in white on its track, and a quiet bar on the surface.
        for (final (mark, ground) in [
          (colors.streak, hero),
          (colors.onHero, _over(heroTrack(colors), hero)),
          (_over(AppColors.quiet(colors.ink), colors.surface), colors.surface),
        ]) {
          expect(
            _contrast(mark, ground),
            greaterThanOrEqualTo(3),
            reason: '$mark on $ground',
          );
        }
        // Control: the faint track itself is not a mark, and fails 3:1 on the
        // navy, so the check can fail.
        expect(_contrast(_over(heroTrack(colors), hero), hero), lessThan(3));
      },
    );
  }
}
