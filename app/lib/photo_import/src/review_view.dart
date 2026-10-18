import 'package:flutter/material.dart' hide Card;
import 'package:flutter/semantics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../deck/deck.dart';
import '../../design/app_button.dart';
import '../../design/app_chip.dart';
import '../../design/app_list_row.dart';
import '../../design/app_sheet.dart';
import '../../design/app_text_field.dart';
import '../../design/theme.dart';
import '../../design/word_break.dart';
import '../../l10n/app_localizations.dart';
import 'candidates.dart';

/// How far a card is dragged before it is removed or put back.
const _swipeThreshold = 48.0;

/// How far the coach slides the first card to show a swipe.
const _coachPeek = 84.0;

/// The coach's steps, each teaching one gesture on the first card.
enum _CoachStep {
  remove,
  restore,
  edit;

  /// The step after this one; null after the last.
  _CoachStep? get next => switch (this) {
    remove => restore,
    restore => edit,
    edit => null,
  };
}

/// The cards made from the photo, grouped by topic, each topic with a switch
/// that keeps or drops it: a swipe left removes a card and a swipe right puts
/// it back, a tap edits it in place, and a removed card stays, struck
/// through. On first use a coach teaches the three gestures.
class ReviewView extends StatefulWidget {
  const ReviewView({
    super.key,
    required this.review,
    required this.decks,
    required this.target,
    required this.onTarget,
    required this.saving,
    required this.coach,
    required this.onChanged,
    required this.onRetake,
    required this.onSave,
  });

  final Review review;
  final List<Deck> decks;

  /// The deck the cards go into; null for a new deck.
  final Deck? target;

  /// Chooses the deck the cards go into; null for a new deck.
  final ValueChanged<DeckId?> onTarget;

  final bool saving;

  /// Whether the coach shows when the screen opens.
  final bool coach;

  /// Called after [review] changed in place.
  final VoidCallback onChanged;

  final VoidCallback onRetake;
  final VoidCallback onSave;

  @override
  State<ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends State<ReviewView> {
  /// The coach's step; null once it has ended or when it never showed.
  late _CoachStep? _coach = widget.coach && widget.review.rows.isNotEmpty
      ? _CoachStep.remove
      : null;

  /// The row open for editing, and what is typed in its fields.
  ReviewRow? _editing;
  String _draftFront = '';
  String _draftBack = '';

  Review get _review => widget.review;

  /// Applies a user's change after committing an open edit, so no typed text
  /// is lost; any change ends the coach.
  void _change(VoidCallback change) {
    setState(() {
      _coach = null;
      if (_editing case final row?) {
        _review.edit(row, front: _draftFront, back: _draftBack);
        _editing = null;
      }
      change();
    });
    widget.onChanged();
  }

  void _edit(ReviewRow row) => _change(() {
    _editing = row;
    _draftFront = row.front;
    _draftBack = row.back;
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final count = _review.saved.length;
    final first = _review.rows.firstOrNull;
    final coach = _coach;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.close,
          icon: const Icon(LucideIcons.x),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.s12),
            child: AppButton(
              label: l10n.retake,
              variant: AppButtonVariant.text,
              onPressed: widget.onRetake,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.s8,
          AppSpace.gutter,
          AppSpace.s24,
        ),
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.reviewMade(_review.rows.length),
              textAlign: TextAlign.center,
              style: AppType.title,
            ),
          ),
          const SizedBox(height: AppSpace.s12),
          Center(
            child: AppChip(
              label: l10n.photoTarget(widget.target?.name ?? l10n.newDeck),
              icon: LucideIcons.chevronDown,
              onPressed: () => _chooseTarget(context),
            ),
          ),
          for (final topic in _review.topics) ...[
            const SizedBox(height: AppSpace.s24),
            if (topic.name case final name?)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.rowGap),
                child: _TopicHeading(
                  name: name,
                  count: topic.rows.length,
                  on: topic.on,
                  onChanged: (on) => _change(() => topic.on = on),
                ),
              ),
            for (final row in topic.rows)
              _ReviewCard(
                key: ObjectKey(row),
                row: row,
                state: _review.stateOf(row),
                inDeck: _review.isDuplicate(row),
                editing: identical(_editing, row),
                coachStep: identical(row, first) ? coach : null,
                dimmed: coach != null && !identical(row, first),
                onRemoved: (removed) => _change(() => row.removed = removed),
                onEdit: () => _edit(row),
                onDraft: (front, back) {
                  _draftFront = front;
                  _draftBack = back;
                },
                onDone: () => _change(() {}),
              ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.s8,
            AppSpace.gutter,
            AppSpace.s16,
          ),
          child: coach != null
              ? _Coach(
                  step: coach,
                  onNext: () => setState(() => _coach = coach.next),
                  onSkip: () => setState(() => _coach = null),
                )
              : AppButton(
                  label: l10n.reviewAdd(count),
                  size: AppButtonSize.cta,
                  loading: widget.saving,
                  onPressed: count == 0
                      ? null
                      : () {
                          _change(() {});
                          widget.onSave();
                        },
                ),
        ),
      ),
    );
  }

  Future<void> _chooseTarget(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    Widget check(bool chosen) => chosen
        ? Icon(LucideIcons.check, color: colors.know)
        : const SizedBox.shrink();
    final target = widget.target;
    final chosen = await showAppSheet<_TargetChoice>(
      context,
      builder: (context) => AppSheet(
        title: l10n.photoTargetTitle,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final deck in widget.decks)
              AppListRow(
                title: deck.name,
                onSheet: true,
                selected: deck.id == target?.id,
                trailing: check(deck.id == target?.id),
                onTap: () => Navigator.of(context).pop(_TargetChoice(deck.id)),
              ),
            AppListRow(
              title: l10n.newDeck,
              leading: const Icon(LucideIcons.plus),
              onSheet: true,
              selected: target == null,
              trailing: check(target == null),
              onTap: () => Navigator.of(context).pop(const _TargetChoice(null)),
            ),
          ],
        ),
      ),
    );
    if (chosen != null) widget.onTarget(chosen.deck);
  }
}

/// A choice in the target sheet; null [deck] is a new deck.
final class _TargetChoice {
  const _TargetChoice(this.deck);

  final DeckId? deck;
}

/// A topic's name and card count, muted while off, beside its switch.
class _TopicHeading extends StatelessWidget {
  const _TopicHeading({
    required this.name,
    required this.count,
    required this.on,
    required this.onChanged,
  });

  final String name;
  final int count;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Row(
      children: [
        Expanded(
          child: ExcludeSemantics(
            child: Text(
              keepWords(l10n.reviewTopic(name, count)),
              style: AppType.label.copyWith(
                color: on ? colors.ink : colors.muted,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpace.s12),
        Semantics(
          label: l10n.reviewTopicSwitch(name, count),
          child: Switch(value: on, onChanged: onChanged),
        ),
      ],
    );
  }
}

/// A card's front and answer side by side, moved by a horizontal drag that
/// removes it past the threshold to the left and puts it back to the right,
/// or, while [editing], its two fields with the remove or restore button.
/// A screen reader opens it with a tap and removes or restores it with a
/// custom action. A card whose topic is off takes neither gesture.
class _ReviewCard extends StatefulWidget {
  const _ReviewCard({
    super.key,
    required this.row,
    required this.state,
    required this.inDeck,
    required this.editing,
    required this.coachStep,
    required this.dimmed,
    required this.onRemoved,
    required this.onEdit,
    required this.onDraft,
    required this.onDone,
  });

  final ReviewRow row;
  final RowState state;

  /// Whether the deck already holds the card's key.
  final bool inDeck;

  final bool editing;

  /// The coach step this card demonstrates; null for none.
  final _CoachStep? coachStep;

  final bool dimmed;
  final ValueChanged<bool> onRemoved;
  final VoidCallback onEdit;

  /// Called with the fields' text as it is typed.
  final void Function(String front, String back) onDraft;

  final VoidCallback onDone;

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard>
    with SingleTickerProviderStateMixin {
  double _drag = 0;

  /// Drives the coach's demonstration: a peek left, a peek right, or a press.
  late final _demo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  bool get _editable => widget.state != RowState.dropped;

  @override
  void initState() {
    super.initState();
    if (widget.coachStep != null) _demo.repeat();
  }

  @override
  void didUpdateWidget(_ReviewCard old) {
    super.didUpdateWidget(old);
    if (widget.coachStep != null && !_demo.isAnimating) {
      _demo.repeat();
    } else if (widget.coachStep == null && _demo.isAnimating) {
      _demo.reset();
    }
  }

  @override
  void dispose() {
    _demo.dispose();
    super.dispose();
  }

  void _dragEnd() {
    final drag = _drag;
    setState(() => _drag = 0);
    if (drag <= -_swipeThreshold) widget.onRemoved(true);
    if (drag >= _swipeThreshold) widget.onRemoved(false);
  }

  /// The coach's offset of the card at the demonstration's progress [t]: out
  /// to the peek, held, and back.
  double _peek(double t) {
    final direction = switch (widget.coachStep) {
      _CoachStep.remove => -1.0,
      _CoachStep.restore => 1.0,
      _CoachStep.edit || null => 0.0,
    };
    final out = Curves.easeOutCubic.transform(
      ((t - 0.2) / 0.26).clamp(0.0, 1.0),
    );
    final back = Curves.easeOutBack.transform(
      ((t - 0.62) / 0.18).clamp(0.0, 1.0),
    );
    return direction * _coachPeek * (out - back);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.editing) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.rowGap),
        child: _CardEditor(
          row: widget.row,
          removed: widget.state == RowState.removed,
          onRemoved: widget.onRemoved,
          onDraft: widget.onDraft,
          onDone: widget.onDone,
        ),
      );
    }
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final row = widget.row;
    final coachStep = widget.coachStep;
    final label = switch (widget.state) {
      RowState.kept => l10n.reviewCard(row.front, row.back),
      RowState.removed => l10n.reviewRemovedCard(row.front, row.back),
      RowState.dropped => l10n.reviewDroppedCard(row.front, row.back),
    };
    final actions = switch (widget.state) {
      RowState.kept => {
        CustomSemanticsAction(label: l10n.reviewRemove): () =>
            widget.onRemoved(true),
      },
      RowState.removed => {
        CustomSemanticsAction(label: l10n.reviewRestore): () =>
            widget.onRemoved(false),
      },
      RowState.dropped => const <CustomSemanticsAction, VoidCallback>{},
    };
    return Opacity(
      opacity: widget.dimmed ? 0.45 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedBuilder(
            animation: _demo,
            builder: (context, child) {
              final offset = _drag + _peek(_demo.value);
              return Stack(
                children: [
                  if (offset != 0)
                    Positioned.fill(
                      bottom: AppSpace.rowGap,
                      child: _SwipeUnder(offset: offset),
                    ),
                  Transform.translate(offset: Offset(offset, 0), child: child),
                  if (coachStep != null)
                    _CoachFinger(step: coachStep, progress: _demo.value),
                ],
              );
            },
            child: Semantics(
              button: _editable,
              label: label,
              onTap: _editable ? widget.onEdit : null,
              customSemanticsActions: actions,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: _editable ? widget.onEdit : null,
                onHorizontalDragUpdate: _editable
                    ? (details) => setState(() => _drag += details.delta.dx)
                    : null,
                onHorizontalDragEnd: _editable ? (_) => _dragEnd() : null,
                onHorizontalDragCancel: _editable
                    ? () => setState(() => _drag = 0)
                    : null,
                child: _CardFace(
                  row: row,
                  removed: widget.state != RowState.kept,
                ),
              ),
            ),
          ),
          if (widget.inDeck)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpace.s4,
                bottom: AppSpace.rowGap,
              ),
              child: Text(
                l10n.reviewInDeck,
                style: AppType.caption.copyWith(color: colors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// What shows under a card dragged by [offset]: "다시 넣기" on the green to the
/// left as it moves right, "빼기" on the red to the right as it moves left.
class _SwipeUnder extends StatelessWidget {
  const _SwipeUnder({required this.offset});

  final double offset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final restoring = offset > 0;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: restoring ? colors.know : colors.dontKnowText,
          borderRadius: BorderRadius.circular(AppRadius.row),
        ),
        child: Align(
          alignment: restoring ? Alignment.centerLeft : Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
            child: Text(
              restoring ? l10n.reviewRestore : l10n.reviewRemove,
              style: AppType.bodyStrong.copyWith(
                color: restoring ? colors.onKnow : colors.onDontKnowText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A card's front and answer in two halves; struck through inside a dashed
/// outline while [removed].
class _CardFace extends StatelessWidget {
  const _CardFace({required this.row, required this.removed});

  final ReviewRow row;
  final bool removed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    TextStyle side(TextStyle style) => removed
        ? style.copyWith(
            color: colors.muted,
            decoration: TextDecoration.lineThrough,
            decorationColor: colors.muted,
          )
        : style;
    final face = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.s16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  keepWords(row.front),
                  style: side(AppType.bodyStrong.copyWith(color: colors.ink)),
                ),
              ),
            ),
          ),
          VerticalDivider(width: 1, color: colors.hairline),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.s16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  keepWords(row.back),
                  style: side(AppType.body.copyWith(color: colors.ink2)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final shape = BorderRadius.circular(AppRadius.row);
    return removed
        ? Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.rowGap),
            child: CustomPaint(
              foregroundPainter: _DashedOutline(
                color: colors.muted,
                radius: AppRadius.row,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.ground,
                  borderRadius: shape,
                ),
                child: face,
              ),
            ),
          )
        : AppRowSurface(child: face);
  }
}

/// A dashed rounded outline, for a removed card.
class _DashedOutline extends CustomPainter {
  const _DashedOutline({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _dash = 6.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.5),
      );
    for (final metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += _dash + _gap) {
        canvas.drawPath(metric.extractPath(at, at + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline old) =>
      old.color != color || old.radius != radius;
}

/// A card opened for editing: its front and answer as fields, reported as
/// they are typed, the button that removes it or puts it back, and "완료".
/// The review commits what is typed before either takes effect.
class _CardEditor extends StatefulWidget {
  const _CardEditor({
    required this.row,
    required this.removed,
    required this.onRemoved,
    required this.onDraft,
    required this.onDone,
  });

  final ReviewRow row;
  final bool removed;
  final ValueChanged<bool> onRemoved;
  final void Function(String front, String back) onDraft;
  final VoidCallback onDone;

  @override
  State<_CardEditor> createState() => _CardEditorState();
}

class _CardEditorState extends State<_CardEditor> {
  late final _front = TextEditingController(text: widget.row.front);
  late final _back = TextEditingController(text: widget.row.back);

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpace.s12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.row),
        border: Border.all(color: colors.ink, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpace.s8,
        children: [
          AppTextField(
            label: l10n.reviewFront,
            controller: _front,
            autofocus: true,
            maxLines: null,
            onChanged: (_) => widget.onDraft(_front.text, _back.text),
          ),
          AppTextField(
            label: l10n.reviewBack,
            controller: _back,
            maxLines: null,
            onChanged: (_) => widget.onDraft(_front.text, _back.text),
          ),
          Row(
            children: [
              AppButton(
                label: widget.removed
                    ? l10n.reviewRestore
                    : l10n.reviewRemoveCard,
                variant: widget.removed
                    ? AppButtonVariant.secondary
                    : AppButtonVariant.destructive,
                onPressed: () => widget.onRemoved(!widget.removed),
              ),
              const Spacer(),
              AppButton(label: l10n.reviewDone, onPressed: widget.onDone),
            ],
          ),
        ],
      ),
    );
  }
}

/// The coach's finger on the first card: dragging it for a swipe, or tapping
/// for an edit.
class _CoachFinger extends StatelessWidget {
  const _CoachFinger({required this.step, required this.progress});

  final _CoachStep step;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final visible = progress > 0.08 && progress < 0.68;
    return Positioned(
      top: AppSpace.s20,
      left: step == _CoachStep.restore ? AppSpace.s32 : null,
      right: step == _CoachStep.remove ? AppSpace.s32 : null,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Opacity(
            opacity: visible ? 1 : 0,
            child: Icon(
              LucideIcons.pointer,
              size: 34,
              color: colors.ink,
              shadows: [Shadow(color: colors.shadow, blurRadius: 6)],
            ),
          ),
        ),
      ),
    );
  }
}

/// The coach's caption over the add button: the step's line, its dots,
/// "건너뛰기" and "다음", the last "시작하기".
class _Coach extends StatelessWidget {
  const _Coach({
    required this.step,
    required this.onNext,
    required this.onSkip,
  });

  final _CoachStep step;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final line = switch (step) {
      _CoachStep.remove => l10n.coachRemove,
      _CoachStep.restore => l10n.coachRestore,
      _CoachStep.edit => l10n.coachEdit,
    };
    return Semantics(
      container: true,
      liveRegion: true,
      label: l10n.coachStep(step.index + 1, _CoachStep.values.length),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.s20,
          AppSpace.s16,
          AppSpace.s16,
          AppSpace.s12,
        ),
        decoration: BoxDecoration(
          color: colors.hero,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    line,
                    style: AppType.bodyStrong.copyWith(color: colors.onHero),
                  ),
                ),
                for (final dot in _CoachStep.values)
                  Container(
                    width: dot == step ? 16 : 6,
                    height: 6,
                    margin: const EdgeInsets.only(left: AppSpace.s4),
                    decoration: BoxDecoration(
                      color: colors.onHero.withValues(
                        alpha: dot == step ? 1 : 0.4,
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.s8),
            Row(
              children: [
                AppButton(
                  label: l10n.coachSkip,
                  variant: AppButtonVariant.onHeroText,
                  onPressed: onSkip,
                ),
                const Spacer(),
                AppButton(
                  label: step.next == null ? l10n.coachStart : l10n.coachNext,
                  variant: AppButtonVariant.onHero,
                  onPressed: onNext,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
