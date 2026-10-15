import 'package:flutter/material.dart';

import '../../shared/theme.dart';

/// The sizes and timings of the study screen, in one place; its colours are
/// the app theme's [AppColors].
abstract final class StudyStyle {
  /// Space between a card and the screen's left and right edges.
  static const cardMargin = AppSpace.gutter;
  static const cardRadius = AppRadius.card;
  static const cardPadding = AppSpace.s16;

  /// Space between two content blocks, and inside a block's placeholder.
  static const blockGap = AppSpace.s8;

  /// The current card's height before its content grows it.
  static const currentMinHeight = 200.0;

  /// The current card's tallest height, as a fraction of the screen height.
  static const currentMaxHeightFraction = 0.55;

  /// Where the current card's vertical centre sits, as a fraction of the
  /// screen height.
  static const currentCenterFraction = 0.57;

  /// The least space kept below the current card.
  static const currentBottomGap = AppSpace.s16;

  /// A card half narrower than this, in logical pixels at text scale 1, puts
  /// the answer under the question.
  static const minHalfWidth = 140.0;

  static const previousHeight = 150.0;

  /// How far each previous card overlaps the one above it.
  static const previousOverlap = 30.0;

  /// Space between the nearest previous card and the current card.
  static const previousGap = AppSpace.s12;
  static const previousLines = 2;

  /// How much each step away from the current card shrinks a previous card,
  /// down to [depthScaleFloor].
  static const depthScaleStep = 0.04;
  static const depthScaleFloor = 0.8;

  /// How many steps away a previous card reaches its greyest and blurriest.
  static const depthSteps = 5;
  static const depthMaxBlur = 1.2;

  static const dotSize = 7.0;
  static const topBarHeight = 56.0;
  static const progressHeight = 4.0;

  /// The drag after which the answer chip and tint appear.
  static const dragFeedbackDistance = 40.0;

  /// The drag past which a release commits the answer.
  static const commitDistance = 100.0;

  /// The release speed, in logical pixels per second, that commits an answer
  /// in its direction whatever the distance.
  static const commitVelocity = 700.0;

  /// The card's tilt, in radians, per logical pixel of drag.
  static const tiltPerPixel = 0.0006;

  static const flyDuration = Duration(milliseconds: 200);
  static const settleDuration = Duration(milliseconds: 300);
  static const springBackDuration = Duration(milliseconds: 250);

  /// The cross-fade that replaces every motion under reduce motion.
  static const fadeDuration = Duration(milliseconds: 150);

  /// How far below its place, and how much smaller, the next card starts.
  static const emergeOffset = 40.0;
  static const emergeScale = 0.92;

  /// The tint over a dragged card at full drag.
  static const tintOpacity = 0.12;

  /// The current card's shadow, in the theme's [AppColors.shadow].
  static List<BoxShadow> currentShadow(AppColors colors) =>
      AppShadow.raised(colors);

  /// A previous card's shadow, in the theme's [AppColors.shadow].
  static List<BoxShadow> previousShadow(AppColors colors) => [
    BoxShadow(
      color: colors.shadow.withValues(alpha: 0.12),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];
}
