import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../deck/deck.dart';
import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import 'content_view.dart';
import 'rust/api/engine.dart';
import 'study_style.dart';

/// The card under study: the question on one half and, once tapped, the
/// answer on the other. Dragged right it answers "Know", left "Don't know".
class CurrentCard extends StatefulWidget {
  const CurrentCard({super.key, required this.card, required this.onAnswer});

  final Card card;
  final void Function(Answer answer) onAnswer;

  @override
  State<CurrentCard> createState() => _CurrentCardState();
}

class _CurrentCardState extends State<CurrentCard>
    with SingleTickerProviderStateMixin {
  /// The card's horizontal offset from its place.
  late final _drag = AnimationController.unbounded(vsync: this);
  var _revealed = false;
  var _committed = false;

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_committed) _drag.value += details.delta.dx;
  }

  void _onDragEnd(DragEndDetails details) {
    if (_committed) return;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final distance = _drag.value;
    final direction = velocity.abs() >= StudyStyle.commitVelocity
        ? velocity
        : distance.abs() >= StudyStyle.commitDistance
        ? distance
        : 0.0;
    if (direction == 0) {
      _springBack();
    } else {
      _commit(direction > 0 ? Answer.know : Answer.dontKnow);
    }
  }

  void _springBack() {
    if (_committed) return;
    _drag.animateTo(
      0,
      duration: StudyStyle.springBackDuration,
      curve: Curves.easeOutBack,
    );
  }

  Future<void> _commit(Answer answer) async {
    if (_committed) return;
    _committed = true;
    HapticFeedback.lightImpact();
    if (!MediaQuery.disableAnimationsOf(context)) {
      final width = MediaQuery.sizeOf(context).width;
      await _drag.animateTo(
        switch (answer) {
          Answer.know => width,
          Answer.dontKnow => -width,
        },
        duration: StudyStyle.flyDuration,
        curve: Curves.easeIn,
      );
    }
    if (mounted) widget.onAnswer(answer);
  }

  /// Answers from a screen reader's action, which can reach the card while it
  /// is scrolled out of view: the card is brought into view first.
  Future<void> _answerFromAction(Answer answer) async {
    await Scrollable.ensureVisible(
      context,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
    if (mounted) await _commit(answer);
  }

  void _toggleRevealed() {
    if (!_committed) setState(() => _revealed = !_revealed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final front = describeContent(l10n, widget.card.front);
    final back = describeContent(l10n, widget.card.back);
    return Semantics(
      container: true,
      button: true,
      label: _revealed
          ? l10n.currentCardRevealedSemantics(front, back)
          : l10n.currentCardSemantics(front),
      onTapHint: _revealed ? l10n.hideAnswer : l10n.showAnswer,
      onTap: _toggleRevealed,
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.know): () =>
            _answerFromAction(Answer.know),
        CustomSemanticsAction(label: l10n.dontKnow): () =>
            _answerFromAction(Answer.dontKnow),
      },
      excludeSemantics: true,
      child: GestureDetector(
        // The card follows the finger from where it touched down.
        dragStartBehavior: DragStartBehavior.down,
        onTap: _toggleRevealed,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: _springBack,
        child: AnimatedBuilder(
          animation: _drag,
          builder: (context, child) => Transform.translate(
            offset: Offset(_drag.value, 0),
            child: Transform.rotate(
              angle: _drag.value * StudyStyle.tiltPerPixel,
              child: _DragFeedback(offset: _drag.value, child: child!),
            ),
          ),
          child: _CardFace(card: widget.card, revealed: _revealed),
        ),
      ),
    );
  }
}

/// The answer chip and tint a drag past [StudyStyle.dragFeedbackDistance]
/// shows over [child].
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.offset, required this.child});

  final double offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (offset.abs() < StudyStyle.dragFeedbackDistance) return child;
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final (label, tint, chip, onChip, alignment) = offset > 0
        ? (
            l10n.know,
            colors.know,
            colors.know,
            colors.onKnow,
            Alignment.topLeft,
          )
        : (
            l10n.dontKnow,
            colors.dontKnow,
            colors.dontKnowText,
            colors.onDontKnowText,
            Alignment.topRight,
          );
    final strength =
        ((offset.abs() - StudyStyle.dragFeedbackDistance) /
                (StudyStyle.commitDistance - StudyStyle.dragFeedbackDistance))
            .clamp(0.0, 1.0);
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tint.withValues(
                  alpha: StudyStyle.tintOpacity * strength,
                ),
                borderRadius: BorderRadius.circular(StudyStyle.cardRadius),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Align(
            alignment: alignment,
            child: Padding(
              padding: const EdgeInsets.all(StudyStyle.cardPadding),
              child: Chip(
                label: Text(label),
                labelStyle: TextStyle(color: onChip),
                backgroundColor: chip,
                side: BorderSide.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The card itself: the question and the answer side by side, or the answer
/// under the question when the halves would be too narrow. Either way the two
/// halves are the same size.
class _CardFace extends StatelessWidget {
  const _CardFace({required this.card, required this.revealed});

  final Card card;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(StudyStyle.cardRadius),
        boxShadow: StudyStyle.currentShadow(colors),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(StudyStyle.cardRadius),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final halfWidth =
                constraints.maxWidth / 2 - StudyStyle.cardPadding * 2;
            final stacked =
                halfWidth < textScaler.scale(StudyStyle.minHalfWidth);
            final question = ContentView(card.front, style: AppType.question);
            final answer = Visibility(
              visible: revealed,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: ContentView(card.back, style: AppType.answer),
            );
            return ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: StudyStyle.currentMinHeight,
                maxHeight: constraints.maxHeight,
              ),
              child: stacked
                  ? IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _Half(question)),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            indent: StudyStyle.dividerInset,
                            endIndent: StudyStyle.dividerInset,
                          ),
                          Expanded(child: _Half(answer)),
                        ],
                      ),
                    )
                  : IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _Half(question)),
                          const VerticalDivider(
                            width: 1,
                            thickness: 1,
                            indent: StudyStyle.dividerInset,
                            endIndent: StudyStyle.dividerInset,
                          ),
                          Expanded(child: _Half(answer)),
                        ],
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// One half, its content centred vertically while it fits and scrolling from
/// the top once the card has reached its cap.
class _Half extends StatelessWidget {
  const _Half(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(StudyStyle.cardPadding),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}
