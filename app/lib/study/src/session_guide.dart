import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/theme.dart';
import '../../design/word_break.dart';
import '../../l10n/app_localizations.dart';
import 'session.dart';
import 'study_style.dart';

/// In the previous card's place from a session's start until its first
/// answer: a panel with a dashed outline and no fill, so it never reads as a
/// card, holding the session's [size], or that today's cards are done where it
/// holds none, and two lines on how to study. It is read as one block.
class SessionGuide extends StatelessWidget {
  const SessionGuide({super.key, required this.size});

  final SessionSize size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final heading = size.cards == 0
        ? l10n.guideDone
        : l10n.guideSize(size.cards, size.minutes);
    final lines = [
      (LucideIcons.moveHorizontal, l10n.guideSwipe),
      (LucideIcons.arrowUp, l10n.guideRise),
    ];
    return Semantics(
      container: true,
      label: [heading, for (final (_, text) in lines) text].join('\n'),
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: _DashedOutline(colors.outline),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.s20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: AppSpace.s12,
                children: [
                  Text(
                    keepWords(heading),
                    style: AppType.body.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  for (final (icon, text) in lines)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: AppSpace.s12,
                      children: [
                        Icon(icon, size: AppSize.smallIcon, color: colors.ink2),
                        Expanded(
                          child: Text(
                            keepWords(text),
                            style: AppType.secondary.copyWith(
                              color: colors.ink2,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dashed outline around its child's box, rounded as the previous card is.
class _DashedOutline extends CustomPainter {
  const _DashedOutline(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = StudyStyle.guideOutline;
    final inset = StudyStyle.guideOutline / 2;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            inset,
            inset,
            size.width - 2 * inset,
            size.height - 2 * inset,
          ),
          const Radius.circular(StudyStyle.previousRadius),
        ),
      );
    for (final PathMetric metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 2 * StudyStyle.guideDash) {
        canvas.drawPath(
          metric.extractPath(at, at + StudyStyle.guideDash),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline oldDelegate) => oldDelegate.color != color;
}
