import 'package:flutter/material.dart';

import '../../deck/deck.dart';
import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import 'candidates.dart';

/// The candidates to check, edit or leave out, with those whose key the deck
/// already holds grouped below with a duplicate option each.
class ReviewView extends StatelessWidget {
  const ReviewView({
    super.key,
    required this.review,
    required this.deckName,
    required this.saving,
    required this.onChanged,
    required this.onRetake,
    required this.onSave,
  });

  final Review review;
  final String deckName;
  final bool saving;

  /// Called after a row of [review] changed in place.
  final VoidCallback onChanged;

  final VoidCallback onRetake;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final fresh = [
      for (final row in review.rows)
        if (!review.isDuplicate(row)) row,
    ];
    final duplicates = [
      for (final row in review.rows)
        if (review.isDuplicate(row)) row,
    ];
    final count = review.saved.length;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.close,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [TextButton(onPressed: onRetake, child: Text(l10n.retake))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.reviewTitle(review.rows.length),
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.reviewHint(deckName),
            style: textTheme.bodyMedium?.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 16),
          for (final row in fresh)
            _CandidateRow(
              key: ObjectKey(row),
              row: row,
              duplicate: false,
              onChanged: onChanged,
            ),
          if (duplicates.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.reviewDuplicates(duplicates.length),
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            for (final row in duplicates)
              _CandidateRow(
                key: ObjectKey(row),
                row: row,
                duplicate: true,
                onChanged: onChanged,
              ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: count == 0 || saving ? null : onSave,
            child: Text(l10n.addCards(count)),
          ),
        ),
      ),
    );
  }
}

/// A candidate: its checkbox, its front and back split by a divider, each
/// edited in place on a tap, and its duplicate option when [duplicate].
class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    super.key,
    required this.row,
    required this.duplicate,
    required this.onChanged,
  });

  final ReviewRow row;
  final bool duplicate;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.row),
      ),
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
                    style: textTheme.bodyLarge,
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
                    text: row.back,
                    style: textTheme.bodyLarge?.copyWith(color: colors.muted),
                    onSubmitted: (text) {
                      row.back = text;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
          ),
          if (duplicate)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
                ? const Icon(Icons.check)
                : const SizedBox.square(dimension: 24),
            onPressed: () => onSelected(option),
            child: Text(label(option)),
          ),
      ],
      builder: (context, controller, _) => ActionChip(
        avatar: const Icon(Icons.expand_more),
        label: Text(label(choice)),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// A card side as text that becomes a field on a tap. Leaving the field keeps
/// its text, or the previous text when it was left empty.
class _EditableSide extends StatefulWidget {
  const _EditableSide({
    required this.label,
    required this.text,
    required this.style,
    required this.onSubmitted,
  });

  final String label;
  final String text;
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
        padding: const EdgeInsets.all(8),
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          autofocus: true,
          maxLines: null,
          style: widget.style,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: widget.label,
            errorText: _controller.text.trim().isEmpty
                ? AppLocalizations.of(context).cardSideRequired
                : null,
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _commit(),
        ),
      );
    }
    void edit() {
      _controller.text = widget.text;
      setState(() => _editing = true);
    }

    return Semantics(
      button: true,
      label: '${widget.label}: ${widget.text}',
      onTap: edit,
      excludeSemantics: true,
      child: InkWell(
        onTap: edit,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(widget.text, style: widget.style),
        ),
      ),
    );
  }
}
