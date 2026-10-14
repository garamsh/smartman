import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide Card;

import '../../deck/deck.dart';
import '../../shared/l10n/app_localizations.dart';
import 'content_view.dart';
import 'rust/api/engine.dart';
import 'session.dart';
import 'study_style.dart';

/// Every card answered in the session, newest at the bottom, in one scroll
/// view that opens at the newest.
class PreviousCards extends StatelessWidget {
  const PreviousCards({super.key, required this.cards, required this.onToggle});

  /// Oldest first.
  final List<PreviousCard> cards;
  final void Function(int position) onToggle;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      reverse: true,
      child: Column(
        children: [
          for (final (index, card) in cards.indexed)
            _Slot(
              key: ValueKey(card.position),
              depth: cards.length - index,
              last: index == cards.length - 1,
              child: _PreviousCardView(
                card: card,
                depth: cards.length - index,
                onTap: () => onToggle(card.position),
              ),
            ),
        ],
      ),
    );
  }
}

/// Where a previous card [depth] steps from the current one sits: scaled down
/// a step per card and overlapping the card above it by
/// [StudyStyle.previousOverlap].
class _Slot extends StatelessWidget {
  const _Slot({
    super.key,
    required this.depth,
    required this.last,
    required this.child,
  });

  final int depth;

  /// Whether this is the newest card, which nothing overlaps.
  final bool last;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = _settle(context);
    final scale = max(
      StudyStyle.depthScaleFloor,
      1 - StudyStyle.depthScaleStep * depth,
    );
    final height = StudyStyle.previousHeight * scale;
    return TweenAnimationBuilder<double>(
      tween: Tween(
        begin: height,
        end: last ? height : height - StudyStyle.previousOverlap,
      ),
      duration: duration,
      builder: (context, slotHeight, child) => SizedBox(
        height: slotHeight,
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: StudyStyle.previousHeight,
          maxHeight: StudyStyle.previousHeight,
          child: child,
        ),
      ),
      child: AnimatedScale(
        scale: scale,
        alignment: Alignment.topCenter,
        duration: duration,
        child: _Entrance(child: child),
      ),
    );
  }
}

/// How long the stack takes to step back: no time under reduce motion.
Duration _settle(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : StudyStyle.settleDuration;

/// Rises a card answered just now into the stack, or fades it in under
/// reduce motion.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: StudyStyle.fadeDuration,
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity, child: child),
        child: child,
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: StudyStyle.emergeOffset, end: 0),
      duration: StudyStyle.settleDuration,
      curve: Curves.easeOutCubic,
      builder: (context, offset, child) =>
          Transform.translate(offset: Offset(0, offset), child: child),
      child: child,
    );
  }
}

/// A card answered earlier, [depth] steps from the current card: front and
/// back, a dot for its answer, and a "Changed" label once the answer differs
/// from the first one given. It greys and blurs a step per step of depth.
class _PreviousCardView extends StatelessWidget {
  const _PreviousCardView({
    required this.card,
    required this.depth,
    required this.onTap,
  });

  final PreviousCard card;
  final int depth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final steps = min(depth - 1, StudyStyle.depthSteps) / StudyStyle.depthSteps;
    final sigma = StudyStyle.depthMaxBlur * steps;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge;
    final answer = switch (card.answer) {
      Answer.know => l10n.know,
      Answer.dontKnow => l10n.dontKnow,
    };
    final radius = BorderRadius.circular(StudyStyle.cardRadius);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: StudyStyle.cardMargin),
      child: Semantics(
        container: true,
        button: true,
        label: l10n.previousCardSemantics(
          describeContent(l10n, card.card.front),
          describeContent(l10n, card.card.back),
          answer,
          card.changed ? 'yes' : 'no',
        ),
        onTapHint: l10n.toggleAnswer,
        onTap: onTap,
        onLongPressHint: l10n.showWholeCard,
        onLongPress: () => _showWholeCard(context, card.card),
        excludeSemantics: true,
        child: AnimatedContainer(
          duration: _settle(context),
          decoration: BoxDecoration(
            color: Color.lerp(
              StudyStyle.cardColor,
              StudyStyle.depthColor,
              steps,
            ),
            borderRadius: radius,
            boxShadow: StudyStyle.previousShadow,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: onTap,
              onLongPress: () => _showWholeCard(context, card.card),
              child: Stack(
                children: [
                  _Blur(
                    sigma: sigma,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _CompactHalf(card.card.front, style: style),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: _CompactHalf(card.card.back, style: style),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: StudyStyle.cardPadding,
                    left: StudyStyle.cardPadding,
                    child: _AnswerDot(answer: card.answer),
                  ),
                  if (card.changed)
                    Positioned(
                      top: StudyStyle.cardPadding / 2,
                      right: StudyStyle.cardPadding,
                      child: Text(
                        l10n.answerChanged,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
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

/// Blurs [child] by [sigma], or leaves it sharp at zero.
class _Blur extends StatelessWidget {
  const _Blur({required this.sigma, required this.child});

  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) => sigma == 0
      ? child
      : ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: child,
        );
}

class _CompactHalf extends StatelessWidget {
  const _CompactHalf(this.blocks, {required this.style});

  final List<Content> blocks;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      StudyStyle.cardPadding + StudyStyle.dotSize,
      StudyStyle.cardPadding * 1.5,
      StudyStyle.cardPadding,
      StudyStyle.cardPadding,
    ),
    child: Align(
      alignment: Alignment.topLeft,
      child: ContentView(
        blocks,
        style: style,
        maxLines: StudyStyle.previousLines,
      ),
    ),
  );
}

class _AnswerDot extends StatelessWidget {
  const _AnswerDot({required this.answer});

  final Answer answer;

  @override
  Widget build(BuildContext context) => Container(
    width: StudyStyle.dotSize,
    height: StudyStyle.dotSize,
    decoration: BoxDecoration(
      color: switch (answer) {
        Answer.know => StudyStyle.knowColor,
        Answer.dontKnow => StudyStyle.dontKnowColor,
      },
      shape: BoxShape.circle,
    ),
  );
}

/// Opens [card]'s whole front and back in a sheet.
void _showWholeCard(BuildContext context, Card card) {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          StudyStyle.cardMargin,
          0,
          StudyStyle.cardMargin,
          StudyStyle.cardMargin,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: StudyStyle.cardPadding / 2,
          children: [
            Text(l10n.cardFront, style: theme.textTheme.labelLarge),
            ContentView(card.front, style: theme.textTheme.bodyLarge),
            const Divider(height: StudyStyle.cardPadding * 2),
            Text(l10n.cardBack, style: theme.textTheme.labelLarge),
            ContentView(card.back, style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    ),
  );
}
