import 'dart:math';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../deck/deck.dart';
import '../../design/app_section_label.dart';
import '../../design/app_sheet.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'rust/api/engine.dart';
import 'session.dart';
import 'study_style.dart';

/// Every card answered in the session, oldest at the top and newest at the
/// bottom, as the sliver above the current card in its scroll view, each in
/// a slot [slot] high. Only the cards near the viewport are built.
///
/// While the column is scrolled back, the card nearest its centre is at full
/// size and opacity and the others smaller and dimmed; that card alone can be
/// dragged left or right to change its answer.
///
/// The list runs oldest first, not reversed, because a list paints its
/// children in index order and each card must paint over the one above it.
class PreviousCards extends StatelessWidget {
  const PreviousCards({
    super.key,
    required this.cards,
    required this.slot,
    required this.onRedecide,
  });

  /// Oldest first.
  final List<PreviousCard> cards;
  final double slot;
  final void Function(int position, Answer answer) onRedecide;

  @override
  Widget build(BuildContext context) => SliverFixedExtentList.builder(
    itemCount: cards.length,
    itemExtent: slot,
    findChildIndexCallback: (key) => switch (key) {
      ValueKey<int>(:final value) when value < cards.length => value,
      _ => null,
    },
    itemBuilder: (context, index) {
      final card = cards[index];
      return _Emphasis(
        key: ValueKey(card.position),
        slot: slot,
        child: _Entrance(
          rising: index == cards.length - 1,
          child: _PreviousCardView(
            card: card,
            slot: slot,
            onRedecide: (answer) => onRedecide(card.position, answer),
          ),
        ),
      );
    },
  );
}

/// How far the column is scrolled back from its end, from 0 at the end to 1
/// half a [slot] or more away, short of where the newest card is centred.
double scrolledBack(ScrollPosition position, double slot) =>
    position.hasContentDimensions && position.hasPixels
    ? ((position.maxScrollExtent - position.pixels) / (slot / 2)).clamp(
        0.0,
        1.0,
      )
    : 0;

/// How near the box of [context] is to the centre of its scroll view, from 1
/// centred to 0 a [slot] or more away.
double _centred(BuildContext context, double slot) {
  final box = context.findRenderObject();
  final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
  if (box is! RenderBox || viewport is! RenderBox || !box.hasSize) return 0;
  final centre = box
      .localToGlobal(box.size.center(Offset.zero), ancestor: viewport)
      .dy;
  final distance = (centre - viewport.size.height / 2).abs();
  return (1 - distance / slot).clamp(0.0, 1.0);
}

/// Scales and dims a previous card by where it stands, as the column scrolls:
/// at rest every card is a little smaller than the current card; scrolled
/// back, the card nearest the centre grows to full size and opacity and the
/// others shrink and dim. It is painted, not laid out, so a scroll rebuilds
/// nothing.
class _Emphasis extends StatelessWidget {
  const _Emphasis({super.key, required this.slot, required this.child});

  final double slot;
  final Widget child;

  @override
  Widget build(BuildContext context) => Flow(
    clipBehavior: Clip.none,
    delegate: _EmphasisDelegate(
      position: Scrollable.of(context).position,
      slotContext: context,
      slot: slot,
    ),
    children: [child],
  );
}

class _EmphasisDelegate extends FlowDelegate {
  _EmphasisDelegate({
    required this.position,
    required this.slotContext,
    required this.slot,
  }) : super(repaint: position);

  final ScrollPosition position;
  final BuildContext slotContext;
  final double slot;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints.tightFor(
        width: max(0, constraints.maxWidth - StudyStyle.previousMargin * 2),
        height: StudyStyle.previousHeight,
      );

  @override
  void paintChildren(FlowPaintingContext context) {
    final child = context.getChildSize(0);
    if (child == null) return;
    final back = scrolledBack(position, slot);
    final centred = _centred(slotContext, slot);
    final scrolled =
        StudyStyle.previousSideScale +
        (1 - StudyStyle.previousSideScale) * centred;
    final scale =
        StudyStyle.previousRestScale +
        (scrolled - StudyStyle.previousRestScale) * back;
    final opacity =
        1 - (1 - StudyStyle.previousSideOpacity) * (1 - centred) * back;
    final dx = (context.size.width - child.width) / 2;
    final dy = (context.size.height - child.height) / 2;
    context.paintChild(
      0,
      transform: Matrix4.identity()
        ..translateByDouble(dx + child.width / 2, dy + child.height / 2, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-child.width / 2, -child.height / 2, 0, 1),
      opacity: opacity,
    );
  }

  @override
  bool shouldRepaint(_EmphasisDelegate oldDelegate) =>
      oldDelegate.position != position || oldDelegate.slot != slot;
}

/// Rises the card answered just now into the column, or fades it in under
/// reduce motion. A card built while [rising] is false, as one scrolled into
/// view is, appears in place.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.rising, required this.child});

  final bool rising;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: rising ? 0 : 1, end: 1),
        duration: StudyStyle.fadeDuration,
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity, child: child),
        child: child,
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: rising ? StudyStyle.emergeOffset : 0, end: 0),
      duration: StudyStyle.settleDuration,
      curve: Curves.easeOutCubic,
      builder: (context, offset, child) =>
          Transform.translate(offset: Offset(0, offset), child: child),
      child: child,
    );
  }
}

/// The other answer.
Answer _other(Answer answer) => switch (answer) {
  Answer.know => Answer.dontKnow,
  Answer.dontKnow => Answer.know,
};

/// A card answered earlier: front and back, both always shown, on its grade's
/// fill and line, with the grade's chip on its top edge.
///
/// Dragged left or right while it is the card nearest the column's centre, it
/// shows the answer the drag would give behind it, and released past
/// [StudyStyle.commitDistance] toward the other answer it changes to that
/// answer. A screen reader changes it by its action instead.
class _PreviousCardView extends StatefulWidget {
  const _PreviousCardView({
    required this.card,
    required this.slot,
    required this.onRedecide,
  });

  final PreviousCard card;
  final double slot;
  final void Function(Answer answer) onRedecide;

  @override
  State<_PreviousCardView> createState() => _PreviousCardViewState();
}

class _PreviousCardViewState extends State<_PreviousCardView>
    with SingleTickerProviderStateMixin {
  /// The card's horizontal offset from its place.
  late final _drag = AnimationController.unbounded(vsync: this);

  /// Whether the drag under way started on the centred card.
  var _dragging = false;

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  /// The answer a drag by [offset] points to.
  Answer _target(double offset) => offset > 0 ? Answer.know : Answer.dontKnow;

  void _onDragStart(DragStartDetails details) {
    // Only the card the column is centred on, and not the one at rest above
    // the current card, is re-decided by a drag.
    final position = Scrollable.of(context).position;
    _dragging =
        scrolledBack(position, widget.slot) > 0.5 &&
        _centred(context, widget.slot) > 0.5;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    final next = _drag.value + details.delta.dx;
    // A drag toward the answer the card already has follows the finger only
    // a little, and shows nothing behind it.
    _drag.value = _target(next) == widget.card.answer
        ? next * StudyStyle.sameAnswerResistance
        : next;
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    final offset = _drag.value;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final target = _target(offset);
    final committed =
        target != widget.card.answer &&
        (offset.abs() >= StudyStyle.commitDistance ||
            (velocity.abs() >= StudyStyle.commitVelocity &&
                velocity.sign == offset.sign));
    if (committed) {
      HapticFeedback.lightImpact();
      widget.onRedecide(target);
    }
    _springBack();
  }

  void _springBack() {
    _dragging = false;
    if (MediaQuery.disableAnimationsOf(context)) {
      _drag.value = 0;
    } else {
      _drag.animateTo(
        0,
        duration: StudyStyle.springBackDuration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final card = widget.card;
    final other = _other(card.answer);
    return Semantics(
      container: true,
      label: l10n.previousCardSemantics(
        describeContent(l10n, card.card.front),
        describeContent(l10n, card.card.back),
        _answerName(l10n, card.answer),
        card.changed ? 'yes' : 'no',
      ),
      customSemanticsActions: {
        CustomSemanticsAction(label: _changeTo(l10n, other)): () =>
            widget.onRedecide(other),
      },
      onLongPressHint: l10n.showWholeCard,
      onLongPress: () => _showWholeCard(context, card.card),
      excludeSemantics: true,
      child: GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: _springBack,
        onLongPress: () => _showWholeCard(context, card.card),
        child: AnimatedBuilder(
          animation: _drag,
          builder: (context, child) {
            final offset = _drag.value;
            final target = _target(offset);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                if (offset != 0 && target != card.answer)
                  Positioned.fill(child: _Reveal(answer: target)),
                Transform.translate(
                  offset: Offset(offset, 0),
                  child: Transform.rotate(
                    angle: offset * StudyStyle.tiltPerPixel,
                    child: child,
                  ),
                ),
              ],
            );
          },
          child: _GradedCard(card: card),
        ),
      ),
    );
  }
}

String _answerName(AppLocalizations l10n, Answer answer) => switch (answer) {
  Answer.know => l10n.know,
  Answer.dontKnow => l10n.dontKnow,
};

String _changeTo(AppLocalizations l10n, Answer answer) => switch (answer) {
  Answer.know => l10n.changeToKnow,
  Answer.dontKnow => l10n.changeToDontKnow,
};

/// What a drag toward [answer] shows behind the card: the answer's tint and
/// the change it would make.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.answer});

  final Answer answer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final (fill, text, icon, label, alignment) = switch (answer) {
      Answer.know => (
        colors.tintGreen,
        colors.onKnowTint,
        LucideIcons.check,
        l10n.changingToKnow,
        Alignment.centerLeft,
      ),
      Answer.dontKnow => (
        colors.tintRed,
        colors.onDontKnowTint,
        LucideIcons.x,
        l10n.changingToDontKnow,
        Alignment.centerRight,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(StudyStyle.cardRadius),
      ),
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: AppSpace.s8,
            children: [
              Icon(icon, size: AppSize.smallIcon, color: text),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.secondary.copyWith(
                    color: text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A previous card's face: its sides on the grade's fill inside the grade's
/// line, and the grade's chip on its top edge.
class _GradedCard extends StatelessWidget {
  const _GradedCard({required this.card});

  final PreviousCard card;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final (fill, line) = switch (card.answer) {
      Answer.know => (colors.knowCard, colors.knowLine),
      Answer.dontKnow => (colors.dontKnowCard, colors.dontKnowLine),
    };
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(StudyStyle.previousRadius),
              border: Border.all(color: line, width: StudyStyle.previousLine),
            ),
            child: SplitCard(
              padding: StudyStyle.cardPadding,
              dividerInset: StudyStyle.previousDividerInset,
              dividerColor: line,
              front: (context, width) => ContentView(
                card.card.front,
                style: AppType.headline.copyWith(color: colors.ink),
                maxLines: StudyStyle.previousLines,
                fit: (minFontSize: AppType.compactFloor, width: width),
              ),
              back: (context, width) => ContentView(
                card.card.back,
                style: AppType.body.copyWith(color: colors.ink2),
                maxLines: StudyStyle.previousLines,
                fit: (minFontSize: AppType.compactFloor, width: width),
              ),
            ),
          ),
        ),
        Positioned(
          top: -StudyStyle.chipHeight / 2,
          right: StudyStyle.chipInset,
          child: _GradeChip(answer: card.answer),
        ),
      ],
    );
  }
}

/// A grade's chip: its icon and its word, white on the grade's colour, so the
/// grade never rests on colour alone.
class _GradeChip extends StatelessWidget {
  const _GradeChip({required this.answer});

  final Answer answer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final (fill, text, icon) = switch (answer) {
      Answer.know => (colors.know, colors.onKnow, LucideIcons.check),
      Answer.dontKnow => (
        colors.dontKnowText,
        colors.onDontKnowText,
        LucideIcons.x,
      ),
    };
    return Container(
      height: StudyStyle.chipHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s8),
      decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpace.s4,
        children: [
          Icon(icon, size: StudyStyle.chipIcon, color: text),
          Text(
            _answerName(l10n, answer),
            style: AppType.micro.copyWith(
              color: text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens [card]'s whole front and back in a sheet.
void _showWholeCard(BuildContext context, Card card) {
  final l10n = AppLocalizations.of(context);
  showAppSheet<void>(
    context,
    builder: (context) => AppSheet(
      title: l10n.cardFront,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ContentView(card.front, style: AppType.body),
          const Divider(height: AppSpace.s32),
          AppSectionLabel(l10n.cardBack),
          ContentView(card.back, style: AppType.body),
        ],
      ),
    ),
  );
}
