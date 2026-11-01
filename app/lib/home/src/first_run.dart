import 'package:flutter/material.dart';

import 'mascot.dart';
import '../../design/theme.dart';
import '../../design/word_break.dart';

/// How to start, where there is nothing to study yet: the mascot where [mascot] is true, as on the first run alone, [title] read as
/// a heading, one [body] line, and the [actions] that start, stacked.
class FirstRun extends StatelessWidget {
  const FirstRun({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
    this.mascot = true,
  });

  final String title;
  final String body;
  final List<Widget> actions;
  final bool mascot;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.s40,
        AppSpace.gutter,
        AppSpace.s24,
      ),
      children: [
        if (mascot) ...[
          const Center(child: Mascot(size: AppSize.mascotLarge)),
          const SizedBox(height: AppSpace.s24),
        ],
        Semantics(
          header: true,
          child: Text(
            keepWords(title),
            semanticsLabel: title,
            textAlign: TextAlign.center,
            style: AppType.title,
          ),
        ),
        const SizedBox(height: AppSpace.s8),
        Text(
          keepWords(body),
          semanticsLabel: body,
          textAlign: TextAlign.center,
          style: AppType.secondary.copyWith(color: colors.muted),
        ),
        const SizedBox(height: AppSpace.s32),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpace.s8,
          children: actions,
        ),
      ],
    );
  }
}
