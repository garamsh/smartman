import 'package:flutter/material.dart';

import '../../design/theme.dart';

/// The brand's mascot, decorative and hidden from screen readers: the symbol
/// navy on a light theme and white on a dark one, centred in a circle of
/// [fill] [size] across, or filling [size] alone when [fill] is null.
class Mascot extends StatelessWidget {
  const Mascot({super.key, required this.size, this.fill});

  final double size;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final fill = this.fill;
    final symbol = Image.asset(
      AppBrand.symbol(Theme.of(context).brightness),
      width: fill == null ? size : size * _inCircle,
      height: fill == null ? size : size * _inCircle,
    );
    return ExcludeSemantics(
      child: fill == null
          ? symbol
          : Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: fill,
                shape: const CircleBorder(),
              ),
              child: symbol,
            ),
    );
  }

  /// How much of the circle's width the symbol takes.
  static const _inCircle = 0.68;
}
