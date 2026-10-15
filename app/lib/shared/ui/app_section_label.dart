import 'package:flutter/material.dart';

import '../theme.dart';

/// A label over a group of rows, read as a heading, with an optional
/// [trailing] widget at its end.
class AppSectionLabel extends StatelessWidget {
  const AppSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpace.s4,
      0,
      AppSpace.s4,
      AppSpace.s8,
    ),
    child: Row(
      spacing: AppSpace.s8,
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              text,
              style: AppType.section.copyWith(
                color: AppColors.of(context).muted,
              ),
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}
