import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../deck/deck.dart';
import 'study_coach.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'rust/api/engine.dart';
import 'study_style.dart';

/// The card under study, filling the height it is given less the answer
/// buttons under it: its front alone, centred; its back shows once answered,
/// on the previous card. Dragged right, or by its "안다" button, it answers
/// "Know"; left, or by "모른다", "Don't know". "안내 다시 보기" between the
/// buttons calls [onGuide].
///
/// While the coach demonstrates an answer, [demo], the card moves toward it
/// over the answer's tint under a finger, [demoProgress] through one
/// [coachCycle], and [coach] takes the answer buttons' place.
class CurrentCard extends StatefulWidget {
  const CurrentCard({
    super.key,
    required this.card,
    required this.onAnswer,
    required this.onGuide,
    this.onDragStart,
    this.demo,
    this.demoProgress = 0,
    this.coach,
  });

  final Card card;
  final void Function(Answer answer) onAnswer;
  final VoidCallback onGuide;

  /// Called as a drag on the card begins.
  final VoidCallback? onDragStart;

  final Answer? demo;
  final double demoProgress;
  final Widget? coach;

  @override
  State<CurrentCard> createState() => _CurrentCardState();
}

class _CurrentCardState extends State<CurrentCard>
    with SingleTickerProviderStateMixin {
  /// The card's horizontal offset from its place.
  late final _drag = AnimationController.unbounded(vsync: this);
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Semantics(
            container: true,
            label: l10n.currentCardSemantics(
              spokenContent(l10n, widget.card.front, revealed: false),
            ),
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
              onHorizontalDragStart: (_) => widget.onDragStart?.call(),
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
                child: switch (widget.demo) {
                  final answer? => _Demo(
                    answer: answer,
                    progress: widget.demoProgress,
                    child: _CardFace(card: widget.card),
                  ),
                  null => _CardFace(card: widget.card),
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: StudyStyle.answerGap),
        widget.coach ??
            _AnswerButtons(onAnswer: _commit, onGuide: widget.onGuide),
      ],
    );
  }
}

/// The coach's demonstration of [answer] on [child], the card's face:
/// [progress] through one [coachCycle], it moves toward the answer and back
/// over the answer's tint and name, under a finger that moves with it.
class _Demo extends StatelessWidget {
  const _Demo({
    required this.answer,
    required this.progress,
    required this.child,
  });

  final Answer answer;
  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final (sign, fill, text, icon, label, alignment) = switch (answer) {
      Answer.know => (
        1.0,
        colors.tintGreen,
        colors.onKnowTint,
        LucideIcons.check,
        l10n.know,
        Alignment.centerLeft,
      ),
      Answer.dontKnow => (
        -1.0,
        colors.tintRed,
        colors.onDontKnowTint,
        LucideIcons.x,
        l10n.dontKnow,
        Alignment.centerRight,
      ),
    };
    final offset = sign * StudyStyle.coachCurrentPeek * coachPeek(progress);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (offset != 0)
          Positioned.fill(
            child: ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(StudyStyle.cardRadius),
                ),
                child: Align(
                  alignment: alignment,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.s20,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: AppSpace.s8,
                      children: [
                        Icon(icon, size: AppSize.smallIcon, color: text),
                        Text(
                          label,
                          style: AppType.secondary.copyWith(
                            color: text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: Transform.translate(
            offset: Offset(offset, 0),
            child: Transform.rotate(
              angle: offset * StudyStyle.tiltPerPixel,
              child: child,
            ),
          ),
        ),
        Positioned.fill(
          child: Transform.translate(
            offset: Offset(offset, StudyStyle.coachFingerDrop),
            child: Center(
              child: StudyCoachFinger(shown: coachFingerShown(progress)),
            ),
          ),
        ),
      ],
    );
  }
}

/// "모른다" after a left chevron and "안다" before a right chevron, under the
/// card: the answers without a drag.
class _AnswerButtons extends StatelessWidget {
  const _AnswerButtons({required this.onAnswer, required this.onGuide});

  final void Function(Answer answer) onAnswer;
  final VoidCallback onGuide;

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
              style: TextButton.styleFrom(
                foregroundColor: colors.muted,
                minimumSize: const Size(AppSize.tapTarget, AppSize.tapTarget),
                textStyle: AppType.micro,
              ),
              onPressed: onGuide,
              child: Text(
                l10n.studyCoachReplay,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
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

/// The card itself: its front alone, centred, scrolling inside where it is
/// taller than the card; a whole card's with its blanks empty.
class _CardFace extends StatelessWidget {
  const _CardFace({required this.card});

  final Card card;

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
          child: LayoutBuilder(
            builder: (context, constraints) => Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(StudyStyle.cardPadding),
                child: SizedBox(
                  width: double.infinity,
                  child: isWholeCard(card.front)
                      ? WholeCardView(
                          card.front,
                          revealed: false,
                          style: AppType.front,
                          minFontSize: AppType.frontFloor,
                          width:
                              constraints.maxWidth - 2 * StudyStyle.cardPadding,
                        )
                      : ContentView(
                          card.front,
                          style: AppType.front,
                          fit: (
                            minFontSize: AppType.frontFloor,
                            width:
                                constraints.maxWidth -
                                2 * StudyStyle.cardPadding,
                            height: null,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
