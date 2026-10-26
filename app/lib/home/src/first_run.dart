import 'package:flutter/material.dart';

import '../../design/mascot.dart';
import '../../design/theme.dart';
import '../../design/word_break.dart';

/// How to start, where there is nothing to study yet: the mascot in a white
/// circle, [title] read as a heading, one [body] line, and the [actions]
/// that start, stacked.
class FirstRun extends StatelessWidget {
  const FirstRun({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
  });

  final String title;
  final String body;
  final List<Widget> actions;

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
        Center(
          child: Mascot(size: AppSize.mascotLarge, fill: colors.surface),
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
