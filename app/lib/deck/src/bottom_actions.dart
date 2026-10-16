import 'package:flutter/material.dart';

import '../../design/theme.dart';

/// A screen's bottom bar: a [secondary] action, and a [primary] one beside it
/// when the screen has one to offer.
class BottomActions extends StatelessWidget {
  const BottomActions({super.key, required this.secondary, this.primary});

  final Widget secondary;
  final Widget? primary;

  @override
  Widget build(BuildContext context) {
    final primary = this.primary;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.s8,
          AppSpace.gutter,
          AppSpace.s16,
        ),
        child: Row(
          spacing: AppSpace.s12,
          children: [
            Expanded(child: secondary),
            if (primary != null) Expanded(child: primary),
          ],
        ),
      ),
    );
  }
}
