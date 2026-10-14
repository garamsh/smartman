import 'package:flutter/material.dart';

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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          spacing: 12,
          children: [
            Expanded(child: secondary),
            if (primary != null) Expanded(child: primary),
          ],
        ),
      ),
    );
  }
}
