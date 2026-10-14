import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide Card;

import '../../deck/deck.dart';
import '../../shared/l10n/app_localizations.dart';
import 'content_view.dart';
import 'rust/api/engine.dart';
import 'session.dart';
import 'study_style.dart';

/// Every card answered in the session, oldest at the top and newest at the
/// bottom, in one scroll view that opens at the newest and returns there after
/// each answer. Only the cards near the viewport are built.
///
/// The list runs oldest first, not reversed, because a list paints its
/// children in index order and each card must paint over the one above it.
class PreviousCards extends StatefulWidget {
  const PreviousCards({super.key, required this.cards, required this.onToggle});

  /// Oldest first.
  final List<PreviousCard> cards;
  final void Function(int position) onToggle;

  @override
  State<PreviousCards> createState() => _PreviousCardsState();
}

class _PreviousCardsState extends State<PreviousCards> {
  ScrollController? _controller;
  var _count = 0;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// The height of the slot of the card at [index] of [count].
  static double _extent(int index, int count) {
    final depth = count - index;
    final height = StudyStyle.previousHeight * _scale(depth);
    return depth == 1 ? height : height - StudyStyle.previousOverlap;
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    return LayoutBuilder(
      builder: (context, constraints) {
        var total = 0.0;
        for (var index = 0; index < cards.length; index++) {
          total += _extent(index, cards.length);
        }
        final viewport = constraints.maxHeight;
        final end = max(0.0, total - viewport);
        final controller = _controller ??= ScrollController(
          initialScrollOffset: end,
        );
        if (cards.length != _count) {
          _count = cards.length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (controller.hasClients) {
              controller.jumpTo(controller.position.maxScrollExtent);
            }
          });
        }
        return ListView.builder(
          controller: controller,
          // Fewer cards than fill the view sit at its bottom.
          padding: EdgeInsets.only(top: max(0, viewport - total)),
          itemCount: cards.length,
          itemExtentBuilder: (index, _) =>
              index < cards.length ? _extent(index, cards.length) : null,
          findChildIndexCallback: (key) => switch (key) {
            ValueKey<int>(:final value) when value < cards.length => value,
            _ => null,
          },
          itemBuilder: (context, index) {
            final card = cards[index];
            final depth = cards.length - index;
            return _Slot(
              key: ValueKey(card.position),
              depth: depth,
              child: _PreviousCardView(
                card: card,
                depth: depth,
                onTap: () => widget.onToggle(card.position),
              ),
            );
          },
        );
      },
    );
  }
}

/// How far a card [depth] steps from the current one is scaled down.
double _scale(int depth) =>
    max(StudyStyle.depthScaleFloor, 1 - StudyStyle.depthScaleStep * depth);

/// Where a previous card [depth] steps from the current one sits: scaled down
/// a step per card, its bottom under the card below it by
/// [StudyStyle.previousOverlap]. The newest card rises into place.
class _Slot extends StatelessWidget {
  const _Slot({super.key, required this.depth, required this.child});

  final int depth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return OverflowBox(
      alignment: Alignment.topCenter,
      minHeight: StudyStyle.previousHeight,
      maxHeight: StudyStyle.previousHeight,
      child: AnimatedScale(
        scale: _scale(depth),
        alignment: Alignment.topCenter,
        duration: _settle(context),
        child: _Entrance(rising: depth == 1, child: child),
      ),
    );
  }
}

/// How long the stack takes to step back: no time under reduce motion.
Duration _settle(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : StudyStyle.settleDuration;

/// Rises the card answered just now into the stack, or fades it in under
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
    // Past the cap no card blurs: its blur would no longer change, and a long
    // session would otherwise composite a blur layer for every card.
    final sigma = depth - 1 > StudyStyle.depthSteps
        ? 0.0
        : StudyStyle.depthMaxBlur * steps;
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
