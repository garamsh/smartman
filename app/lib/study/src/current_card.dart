import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../deck/deck.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'rust/api/engine.dart';
import 'study_style.dart';

/// The card under study, filling the height it is given less the answer
/// buttons under it: the question on one half and, once tapped, the answer on
/// the other. Dragged right, or
/// by its "안다" button, it answers "Know"; left, or by "모른다", "Don't know".
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

  void _toggleRevealed() {
    if (!_committed) setState(() => _revealed = !_revealed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final front = describeContent(l10n, widget.card.front);
    final back = describeContent(l10n, widget.card.back);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Semantics(
            container: true,
            button: true,
            label: _revealed
                ? l10n.currentCardRevealedSemantics(front, back)
                : l10n.currentCardSemantics(front),
            onTapHint: _revealed ? l10n.hideAnswer : l10n.showAnswer,
            onTap: _toggleRevealed,
            customSemanticsActions: {
              CustomSemanticsAction(label: l10n.know): () =>
                  _commit(Answer.know),
              CustomSemanticsAction(label: l10n.dontKnow): () =>
                  _commit(Answer.dontKnow),
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
          ),
        ),
        const SizedBox(height: StudyStyle.answerGap),
        _AnswerButtons(onAnswer: _commit),
      ],
    );
  }
}

/// "모른다" after a left chevron and "안다" before a right chevron, under the
/// card: the answers without a drag.
class _AnswerButtons extends StatelessWidget {
  const _AnswerButtons({required this.onAnswer});

  final void Function(Answer answer) onAnswer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    ButtonStyle style(Color fill, Color text, EdgeInsets padding) =>
        TextButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: text,
          shape: const StadiumBorder(),
          minimumSize: const Size(AppSize.tapTarget, StudyStyle.answerHeight),
          padding: padding,
          textStyle: AppType.secondary.copyWith(fontWeight: FontWeight.w700),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        spacing: AppSpace.s12,
        children: [
          Flexible(
            child: TextButton(
              style: style(
                colors.tintRed,
                colors.onDontKnowTint,
                const EdgeInsets.only(left: AppSpace.s8, right: AppSpace.s16),
              ),
              onPressed: () => onAnswer(Answer.dontKnow),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: AppSpace.s4,
                children: [
                  const Icon(LucideIcons.chevronLeft, size: AppSize.smallIcon),
                  Flexible(
                    child: Text(l10n.dontKnow, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
          Flexible(
            child: TextButton(
              style: style(
                colors.tintGreen,
                colors.onKnowTint,
                const EdgeInsets.only(left: AppSpace.s16, right: AppSpace.s8),
              ),
              onPressed: () => onAnswer(Answer.know),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: AppSpace.s4,
                children: [
                  Flexible(
                    child: Text(l10n.know, overflow: TextOverflow.ellipsis),
                  ),
                  const Icon(LucideIcons.chevronRight, size: AppSize.smallIcon),
                ],
              ),
            ),
          ),
        ],
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
/// halves are the same size. While the answer is hidden an eye holds its
/// place.
class _CardFace extends StatelessWidget {
  const _CardFace({required this.card, required this.revealed});

  final Card card;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(StudyStyle.cardRadius),
        boxShadow: StudyStyle.currentShadow(colors),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(StudyStyle.cardRadius),
        child: SizedBox.expand(
          child: SplitCard(
            padding: StudyStyle.cardPadding,
            dividerInset: StudyStyle.dividerInset,
            stackBelow: StudyStyle.minHalfWidth,
            scrolls: true,
            front: (context, width) => ContentView(
              card.front,
              style: AppType.question,
              fit: (
                minFontSize: AppType.questionFloor,
                width: width,
                height: null,
              ),
            ),
            back: (context, width) => Stack(
              alignment: Alignment.center,
              children: [
                Visibility(
                  visible: revealed,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: ContentView(
                    card.back,
                    style: AppType.answer,
                    fit: (
                      minFontSize: AppType.answerFloor,
                      width: width,
                      height: null,
                    ),
                  ),
                ),
                if (!revealed)
                  Icon(
                    LucideIcons.eye,
                    size: StudyStyle.hiddenAnswerIcon,
                    color: colors.muted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
