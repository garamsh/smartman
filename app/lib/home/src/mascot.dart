import 'package:flutter/material.dart';

import '../../design/theme.dart';

/// The brand's mascot on its cream circle, [size] across, decorative and
/// hidden from screen readers.
class Mascot extends StatelessWidget {
  const Mascot({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Image.asset(AppBrand.circle, width: size, height: size),
  );
}
