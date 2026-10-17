import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../deck/deck.dart';
import '../../design/app_button.dart';
import '../../design/app_chip.dart';
import '../../design/app_list_row.dart';
import '../../design/app_section_label.dart';
import '../../design/app_text_field.dart';
import '../../design/theme.dart';
import '../../design/word_break.dart';
import '../../l10n/app_localizations.dart';
import 'candidates.dart';
import 'detail_step.dart';

/// The detail step, over the candidates it offers to check, edit or leave
/// out, with those whose key the deck already holds grouped below with a
/// duplicate option each.
class ReviewView extends StatelessWidget {
  const ReviewView({
    super.key,
    required this.review,
    required this.deckName,
    required this.saving,
    required this.onStep,
    required this.onChanged,
    required this.onRetake,
    required this.onSave,
  });

  final Review review;
  final String deckName;
  final bool saving;

  /// Chooses the detail step, which changes the rows offered and recomposes
  /// every answer not typed.
  final ValueChanged<DetailStep> onStep;

  /// Called after a row of [review] changed in place.
  final VoidCallback onChanged;

  final VoidCallback onRetake;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final offered = review.offered.toList();
    final fresh = [
      for (final row in offered)
        if (!review.isDuplicate(row)) row,
    ];
    final duplicates = [
      for (final row in offered)
        if (review.isDuplicate(row)) row,
    ];
    final count = review.saved.length;
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
              onPressed: onRetake,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          0,
          AppSpace.gutter,
          AppSpace.s16,
        ),
        children: [
          Semantics(
            header: true,
            child: Text(l10n.reviewTitle(offered.length), style: AppType.title),
          ),
          const SizedBox(height: AppSpace.s4),
          Text(
            l10n.reviewHint(deckName),
            style: AppType.secondary.copyWith(color: colors.muted),
          ),
          const SizedBox(height: AppSpace.s16),
          DetailStepSlider(step: review.step, onChanged: onStep),
          const SizedBox(height: AppSpace.s16),
          for (final row in fresh)
            _CandidateRow(
              key: ObjectKey(row),
              row: row,
              step: review.step,
              duplicate: false,
              onChanged: onChanged,
            ),
          if (duplicates.isNotEmpty) ...[
            const SizedBox(height: AppSpace.s16),
            AppSectionLabel(l10n.reviewDuplicates(duplicates.length)),
            for (final row in duplicates)
              _CandidateRow(
                key: ObjectKey(row),
                row: row,
                step: review.step,
                duplicate: true,
                onChanged: onChanged,
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
          child: AppButton(
            label: l10n.addCards(count),
            size: AppButtonSize.cta,
            loading: saving,
            onPressed: count == 0 ? null : onSave,
          ),
        ),
      ),
    );
  }
}

/// A candidate: its checkbox, its front and its answer at [step] split by a
/// divider, each edited in place on a tap, an answer typed by hand marked
/// edited, and its duplicate option when [duplicate].
class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    super.key,
    required this.row,
    required this.step,
    required this.duplicate,
    required this.onChanged,
  });

  final ReviewRow row;
  final DetailStep step;
  final bool duplicate;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return AppRowSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Checkbox(
                    semanticLabel: l10n.includeCard,
                    value: row.included,
                    onChanged: (value) {
                      row.included = value ?? false;
                      onChanged();
                    },
                  ),
                ),
                Expanded(
                  child: _EditableSide(
                    label: l10n.cardFront,
                    text: row.front,
                    style: AppType.body,
                    onSubmitted: (text) {
                      row.front = text;
                      onChanged();
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _EditableSide(
                    label: l10n.cardBack,
                    text: row.backAt(step),
                    mark: row.edited ? l10n.candidateEdited : null,
                    style: AppType.body.copyWith(color: colors.muted),
                    onSubmitted: (text) {
                      row.editedBack = text;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
          ),
          if (duplicate)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.s12,
                0,
                AppSpace.s12,
                AppSpace.s12,
              ),
              child: _DuplicateChoiceChip(
                choice: row.choice,
                onSelected: (choice) {
                  row.choice = choice;
                  onChanged();
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The current duplicate option; a tap offers the three.
class _DuplicateChoiceChip extends StatelessWidget {
  const _DuplicateChoiceChip({required this.choice, required this.onSelected});

  final DuplicateChoice choice;
  final ValueChanged<DuplicateChoice> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String label(DuplicateChoice choice) => switch (choice) {
      DuplicateChoice.skip => l10n.duplicateSkip,
      DuplicateChoice.mergeBack => l10n.duplicateMergeBack,
      DuplicateChoice.addNew => l10n.duplicateAddNew,
    };
    return MenuAnchor(
      menuChildren: [
        for (final option in DuplicateChoice.values)
          MenuItemButton(
            leadingIcon: option == choice
                ? const Icon(LucideIcons.check)
                : const SizedBox.square(dimension: AppSpace.s24),
            onPressed: () => onSelected(option),
            child: Text(label(option)),
          ),
      ],
      builder: (context, controller, _) => AppChip(
        label: label(choice),
        icon: LucideIcons.chevronDown,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// A card side as text that becomes a field on a tap, with [mark] under it
/// when there is one. The text breaks lines only between words, and is read
/// as written. Leaving the field keeps its text, or the previous text
/// when it was left empty.
class _EditableSide extends StatefulWidget {
  const _EditableSide({
    required this.label,
    required this.text,
    this.mark,
    required this.style,
    required this.onSubmitted,
  });

  final String label;
  final String text;
  final String? mark;
  final TextStyle? style;
  final ValueChanged<String> onSubmitted;

  @override
  State<_EditableSide> createState() => _EditableSideState();
}

class _EditableSideState extends State<_EditableSide> {
  late final _controller = TextEditingController(text: widget.text);
  late final _focus = FocusNode()..addListener(_onFocus);
  bool _editing = false;

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus && _editing) _commit();
  }

  void _commit() {
    final text = _controller.text.trim();
    setState(() => _editing = false);
    if (text.isEmpty) {
      _controller.text = widget.text;
    } else if (text != widget.text) {
      widget.onSubmitted(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.s8),
        child: AppTextField(
          label: widget.label,
          controller: _controller,
          focusNode: _focus,
          autofocus: true,
          maxLines: null,
          style: widget.style,
          textInputAction: TextInputAction.done,
          errorText: _controller.text.trim().isEmpty
              ? AppLocalizations.of(context).cardSideRequired
              : null,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _commit(),
        ),
      );
    }
    void edit() {
      _controller.text = widget.text;
      setState(() => _editing = true);
    }

    final mark = widget.mark;
    return Semantics(
      button: true,
      label: ['${widget.label}: ${widget.text}', ?mark].join(', '),
      onTap: edit,
      excludeSemantics: true,
      child: InkWell(
        onTap: edit,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(keepWords(widget.text), style: widget.style),
                if (mark != null) ...[
                  const SizedBox(height: AppSpace.s4),
                  Text(
                    mark,
                    style: AppType.caption.copyWith(
                      color: AppColors.of(context).muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
