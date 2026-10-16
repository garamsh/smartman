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

  /// The current card's height before its content grows it.
  static const currentMinHeight = 200.0;

  /// The current card's tallest height, as a fraction of the screen height.
  static const currentMaxHeightFraction = 0.55;

  /// Where the current card's vertical centre sits, as a fraction of the
  /// screen height.
  static const currentCenterFraction = 0.57;

  /// The least space kept below the answer buttons.
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

  /// A previous card's height, and its space from the screen's edges.
  static const previousHeight = 120.0;
  static const previousMargin = AppSpace.s24;

  /// A previous card's line around it.
  static const previousLine = 1.5;

  /// The space each previous card takes in the column, as a fraction of the
  /// column's height: wide enough that the view at rest shows one previous
  /// card, and scrolled back three cards.
  static const previousSlotFraction = 0.36;

  /// Space between the nearest previous card and the current card.
  static const previousGap = AppSpace.s12;
  static const previousLines = 2;

  /// A previous card's scale at rest, and away from the centre while the
  /// column is scrolled back; the centred one is at full size.
  static const previousRestScale = 0.94;
  static const previousSideScale = 0.9;

  /// A previous card's opacity away from the centre while the column is
  /// scrolled back.
  static const previousSideOpacity = 0.72;

  /// The grade chip on a previous card's top edge: its height, its icon and
  /// how far it stands in from the card's right edge.
  static const chipHeight = AppSpace.s24;
  static const chipIcon = AppSpace.s12;
  static const chipInset = AppSpace.s16;

  static const topBarHeight = 56.0;
  static const progressHeight = AppSize.progress;

  /// How far the divider between a card's halves stops short of its edges.
  static const dividerInset = AppSpace.s28;

  /// How far a previous card's divider stops short of its edges.
  static const previousDividerInset = AppSpace.s20;

  /// The eye in the hidden answer's half.
  static const hiddenAnswerIcon = AppSpace.s24;

  /// The fade under the top bar, over cards scrolled beneath it.
  static const topFade = AppSpace.s40;

  /// The fade above "지금 카드로", over the cards behind it.
  static const bottomFade = AppSpace.s40;

  /// The first-run guide's icon tile.
  static const guideTile = AppSpace.s32;

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
