import 'package:flutter/material.dart';

import '../../design/mascot.dart';
import '../../design/theme.dart';
import '../../design/word_break.dart';

/// How to start, where there is nothing to study yet: the mascot in its
/// [mascot] expression, [title], the one sentence, read as a heading, and the
/// [actions] that start, stacked.
class FirstRun extends StatelessWidget {
  const FirstRun({
    super.key,
    required this.title,
    required this.actions,
    required this.mascot,
  });

  final String title;
  final List<Widget> actions;
  final MascotExpression mascot;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.s40,
        AppSpace.gutter,
        AppSpace.s24,
      ),
      children: [
        Center(
          child: Mascot(expression: mascot, size: AppSize.mascotLarge),
        ),
        const SizedBox(height: AppSpace.s24),
        Semantics(
          header: true,
          child: Text(
            keepWords(title),
            semanticsLabel: title,
            textAlign: TextAlign.center,
            style: AppType.title,
          ),
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
