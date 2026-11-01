import 'package:flutter/material.dart';

import 'theme.dart';

/// The moods of the mascot, each the same drawing (ADR 0140).
enum MascotExpression {
  /// Looking up, a hand at its chin: the mark itself, and a photo being read.
  thinking,

  /// Eyes shut in a smile, arms up: study done, and the first deck made.
  happy,

  /// Eyes wet, hands together: a failed photo, or a photo with no cards.
  sad,

  /// Dozing: nothing to study today, and an empty deck.
  sleepy,
}

/// The mascot, [size] across, on no ground of its own, decorative and hidden
/// from screen readers. A still image, so reduce motion asks nothing of it.
class Mascot extends StatelessWidget {
  const Mascot({super.key, required this.expression, required this.size});

  final MascotExpression expression;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Image.asset(
      AppBrand.mascot(expression.name),
      width: size,
      height: size,
    ),
  );
}
