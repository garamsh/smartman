import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../deck/deck.dart';
import 'study_coach.dart';
import '../../design/app_section_label.dart';
import '../../design/app_sheet.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'rust/api/engine.dart';
import 'session.dart';
import 'study_style.dart';

/// The other answer.
Answer _other(Answer answer) => switch (answer) {
  Answer.know => Answer.dontKnow,
  Answer.dontKnow => Answer.know,
};

/// The card answered just before the current one: front and back, both
/// always shown, on its grade's fill and line, with the grade's chip on its
/// top edge. It fills the height it is given, as the current card does.
///
/// Dragged left or right, it shows the answer the drag would give behind it,
/// and released past [StudyStyle.commitDistance], or flung, toward the other
/// answer it changes to that answer. A tap opens the whole card in a sheet. A
/// screen reader changes it by its action instead of a drag.
class PreviousCardView extends StatefulWidget {
  const PreviousCardView({
    super.key,
    required this.card,
    required this.onRedecide,
  });

  final PreviousCard card;
  final void Function(Answer answer) onRedecide;

  @override
  State<PreviousCardView> createState() => _PreviousCardViewState();
}

class _PreviousCardViewState extends State<PreviousCardView>
    with SingleTickerProviderStateMixin {
  /// The card's horizontal offset from its place.
  late final _drag = AnimationController.unbounded(vsync: this);

  /// How far the finger has moved since the drag began.
  var _finger = 0.0;

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  /// The answer a drag by [offset] points to.
  Answer _target(double offset) => offset > 0 ? Answer.know : Answer.dontKnow;

  void _onDragUpdate(DragUpdateDetails details) {
    _finger += details.delta.dx;
    // A drag toward the answer the card already has follows the finger only
    // a little, and shows nothing behind it.
    _drag.value = _target(_finger) == widget.card.answer
        ? _finger * StudyStyle.sameAnswerResistance
        : _finger;
  }

  void _onDragEnd(DragEndDetails details) {
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
    _finger = 0;
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
        spoken(
          describeContent(l10n, card.card.front),
          revealed: false,
          blank: l10n.blank,
        ),
        describeContent(l10n, card.card.back),
        _answerName(l10n, card.answer),
        card.changed ? 'yes' : 'no',
      ),
      customSemanticsActions: {
        CustomSemanticsAction(label: _changeTo(l10n, other)): () =>
            widget.onRedecide(other),
      },
      button: true,
      onTapHint: l10n.showWholeCard,
      onTap: () => _showWholeCard(context, card.card),
      excludeSemantics: true,
      child: GestureDetector(
        // The card follows the finger from where it touched down.
        dragStartBehavior: DragStartBehavior.down,
        onTap: () => _showWholeCard(context, card.card),
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: _springBack,
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
          child: _GradedCard(
            front: card.card.front,
            back: card.card.back,
            answer: card.answer,
          ),
        ),
      ),
    );
  }
}

/// The day's last answer from an earlier session, in the previous card's
/// place: graded as a previous card is, with "지난번 마지막 카드", and opened
/// whole by a tap. Its answer is not changed from here.
class EarlierCardView extends StatelessWidget {
  const EarlierCardView({super.key, required this.earlier});

  final EarlierAnswer earlier;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final card = earlier.card;
    return Semantics(
      container: true,
      label: [
        l10n.earlierCard,
        l10n.previousCardSemantics(
          spoken(
            describeContent(l10n, card.front),
            revealed: false,
            blank: l10n.blank,
          ),
          describeContent(l10n, card.back),
          _answerName(l10n, earlier.answer),
          'no',
        ),
      ].join('. '),
      button: true,
      onTapHint: l10n.showWholeCard,
      onTap: () => _showWholeCard(context, card),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => _showWholeCard(context, card),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: _GradedCard(
                front: card.front,
                back: card.back,
                answer: earlier.answer,
              ),
            ),
            // At the bottom, clear of the notice that may show over the top.
            Positioned(
              bottom: AppSpace.s12,
              left: StudyStyle.cardPadding,
              child: Text(
                l10n.earlierCard,
                style: AppType.micro.copyWith(color: colors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The coach's third step in the previous card's place: a sample card,
/// [front] and [back], answered "Know", dragged toward "Don't know" by a
/// finger and sprung back, [progress] through one [coachCycle], over what the
/// drag shows behind it. Hidden from screen readers, which read the coach's
/// caption.
class PreviousCardDemo extends StatelessWidget {
  const PreviousCardDemo({
    super.key,
    required this.front,
    required this.back,
    required this.progress,
  });

  final List<Content> front;
  final List<Content> back;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final offset = -StudyStyle.coachPreviousPeek * coachPeek(progress);
    return ExcludeSemantics(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (offset != 0)
            const Positioned.fill(child: _Reveal(answer: Answer.dontKnow)),
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(offset, 0),
              child: Transform.rotate(
                angle: offset * StudyStyle.tiltPerPixel,
                child: _GradedCard(
                  front: front,
                  back: back,
                  answer: Answer.know,
                ),
              ),
            ),
          ),
          Positioned(
            right: StudyStyle.coachFingerInset - offset,
            bottom: StudyStyle.coachFingerLift,
            child: StudyCoachFinger(shown: coachFingerShown(progress)),
          ),
        ],
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
/// line, at the current card's sizes and shrunk as far as their floors to fit
/// their halves, then cut, or a whole card's front with its blanks filled,
/// fitted to the card; and the grade's chip on its top edge.
class _GradedCard extends StatelessWidget {
  const _GradedCard({
    required this.front,
    required this.back,
    required this.answer,
  });

  final List<Content> front;
  final List<Content> back;
  final Answer answer;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final whole = describeContent(AppLocalizations.of(context), front);
    final (fill, line) = switch (answer) {
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
            // The card is given its height, so its halves are laid out at
            // it and each side reads the height its half leaves it.
            child: hasBlanks(whole)
                ? Padding(
                    padding: const EdgeInsets.all(StudyStyle.cardPadding),
                    child: LayoutBuilder(
                      builder: (context, constraints) => Center(
                        child: WholeCardView(
                          whole,
                          revealed: true,
                          style: AppType.question.copyWith(color: colors.ink),
                          minFontSize: AppType.questionFloor,
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                        ),
                      ),
                    ),
                  )
                : SplitCard(
                    padding: StudyStyle.cardPadding,
                    dividerInset: StudyStyle.dividerInset,
                    dividerColor: line,
                    stackBelow: StudyStyle.minHalfWidth,
                    front: (context, width) => LayoutBuilder(
                      builder: (context, constraints) => ContentView(
                        front,
                        style: AppType.question.copyWith(color: colors.ink),
                        fit: (
                          minFontSize: AppType.questionFloor,
                          width: width,
                          height: constraints.maxHeight,
                        ),
                      ),
                    ),
                    back: (context, width) => LayoutBuilder(
                      builder: (context, constraints) => ContentView(
                        back,
                        style: AppType.answer.copyWith(color: colors.ink2),
                        fit: (
                          minFontSize: AppType.answerFloor,
                          width: width,
                          height: constraints.maxHeight,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        Positioned(
          top: -StudyStyle.chipHeight / 2,
          right: StudyStyle.chipInset,
          child: _GradeChip(answer: answer),
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

/// Opens [card]'s whole front and back in a sheet, or a whole card's front
/// with its blanks filled.
void _showWholeCard(BuildContext context, Card card) {
  final l10n = AppLocalizations.of(context);
  final whole = describeContent(l10n, card.front);
  final isWhole = hasBlanks(whole);
  showAppSheet<void>(
    context,
    builder: (context) => AppSheet(
      title: isWhole ? l10n.wholeCard : l10n.cardFront,
      content: isWhole
          ? WholeCardView(whole, revealed: true, style: AppType.body)
          : Column(
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
