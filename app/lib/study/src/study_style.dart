import 'package:flutter/material.dart';

import '../../design/theme.dart';

/// The sizes and timings of the study screen, in one place; its colours are
/// the app theme's [AppColors].
abstract final class StudyStyle {
  /// Space between the current card and the screen's left and right edges.
  static const cardMargin = AppSpace.gutter;
  static const cardRadius = AppRadius.card;
  static const previousRadius = AppRadius.previous;
  static const cardPadding = AppSpace.s16;

  /// The completion card's least height.
  static const completionMinHeight = 200.0;

  /// Space above the previous card, which its grade chip stands into.
  static const topGap = AppSpace.s20;

  /// Space between the previous card and the current card.
  static const cardGap = AppSpace.s16;

  /// The space kept below the answer buttons, or below the completion card.
  static const currentBottomGap = AppSpace.s16;

  /// Space between the current card and the answer buttons under it.
  static const answerGap = AppSpace.s20;

  /// The answer buttons' height.
  static const answerHeight = AppSize.tapTarget;

  /// The answer buttons' row under the current card, with the space above
  /// it: each button's tap target is padded to Material's least interactive
  /// size.
  static const answerRow = answerGap + kMinInteractiveDimension;

  /// A card half narrower than this, in logical pixels at text scale 1, puts
  /// the answer under the question.
  static const minHalfWidth = 140.0;

  /// A previous card's line around it.
  static const previousLine = 1.5;

  /// The grade chip on a previous card's top edge: its height, its icon and
  /// how far it stands in from the card's right edge.
  static const chipHeight = AppSpace.s24;
  static const chipIcon = AppSpace.s12;
  static const chipInset = AppSpace.s16;

  static const topBarHeight = 56.0;
  static const progressHeight = AppSize.progress;

  /// How far the divider between a card's halves stops short of its edges.
  static const dividerInset = AppSpace.s28;

  /// The eye in the hidden answer's half.
  static const hiddenAnswerIcon = AppSpace.s24;

  /// The width of the session guide's dashed outline.
  static const guideOutline = 1.5;

  /// The length of each dash of the session guide's outline, and of each gap.
  static const guideDash = 6.0;

  /// The drag after which the answer chip and tint appear.
  static const dragFeedbackDistance = 40.0;

  /// The drag past which a release commits the answer.
  static const commitDistance = 100.0;

  /// The release speed, in logical pixels per second, that commits an answer
  /// in its direction whatever the distance.
  static const commitVelocity = 700.0;

  /// The card's tilt, in radians, per logical pixel of drag.
  static const tiltPerPixel = 0.0006;

  /// How far a previous card follows a drag toward the answer it already has.
  static const sameAnswerResistance = 0.25;

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
}
