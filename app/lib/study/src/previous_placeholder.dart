import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/theme.dart';
import '../../design/word_break.dart';
import '../../l10n/app_localizations.dart';
import 'study_style.dart';

/// The previous card's place while it holds no card: a dashed outline with no
/// fill, so it never reads as a card, around an up arrow and a line saying
/// that answered cards stack here.
class PreviousPlaceholder extends StatelessWidget {
  const PreviousPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      container: true,
      label: l10n.previousPlaceholder,
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: _DashedOutline(colors.outline),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.s20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: AppSpace.s8,
                children: [
                  Icon(LucideIcons.arrowUp, color: colors.muted),
                  Text(
                    keepWords(l10n.previousPlaceholder),
                    textAlign: TextAlign.center,
                    style: AppType.secondary.copyWith(color: colors.muted),
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
      ..strokeWidth = StudyStyle.placeholderOutline;
    final inset = StudyStyle.placeholderOutline / 2;
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
      for (
        var at = 0.0;
        at < metric.length;
        at += 2 * StudyStyle.placeholderDash
      ) {
        canvas.drawPath(
          metric.extractPath(at, at + StudyStyle.placeholderDash),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline oldDelegate) => oldDelegate.color != color;
}
