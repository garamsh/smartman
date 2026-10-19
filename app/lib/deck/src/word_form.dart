import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_button.dart';
import '../../design/app_sheet.dart';
import '../../design/app_text_field.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'content.dart';

/// One sense of a word as the word form edits it: its labels, its meaning,
/// and its examples, one per line.
class SenseDraft {
  SenseDraft([CardSense? sense])
    : labels = [...?sense?.labels],
      meaning = TextEditingController(text: sense?.meaning ?? ''),
      examples = TextEditingController(
        text: (sense?.examples ?? const []).join('\n'),
      );

  final List<SenseLabel> labels;
  final TextEditingController meaning;
  final TextEditingController examples;

  /// Whether the meaning is empty, which saving refuses.
  bool get isBlank => meaning.text.trim().isEmpty;

  /// The sense as saved: its labels, its meaning trimmed, and each non-empty
  /// line of its examples, trimmed.
  CardSense get sense => CardSense(
    labels: [...labels],
    meaning: meaning.text.trim(),
    examples: [
      for (final line in examples.text.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ],
  );

  void dispose() {
    meaning.dispose();
    examples.dispose();
  }
}

/// The senses of the word form, each with its labels, meaning and examples,
/// and under them "뜻 추가". A sense moves up or down, or is deleted, by its
/// buttons, which a screen reader reaches by name; a word keeps at least one
/// sense. With [showErrors], a sense without a meaning says so under it.
class SenseFields extends StatelessWidget {
  const SenseFields({
    super.key,
    required this.senses,
    required this.showErrors,
    required this.onChanged,
  });

  final List<SenseDraft> senses;
  final bool showErrors;

  /// Called after every change to [senses], which this widget makes in place.
  final VoidCallback onChanged;

  void _move(int from, int to) {
    senses.insert(to, senses.removeAt(from));
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpace.s16,
      children: [
        for (final (index, sense) in senses.indexed)
          _SenseCard(
            // Keyed by the draft, so a moved sense keeps its fields' focus and
            // text.
            key: ObjectKey(sense),
            sense: sense,
            number: index + 1,
            showError: showErrors && sense.isBlank,
            onUp: index == 0 ? null : () => _move(index, index - 1),
            onDown: index == senses.length - 1
                ? null
                : () => _move(index, index + 1),
            onDelete: senses.length == 1
                ? null
                : () {
                    senses.removeAt(index).dispose();
                    onChanged();
                  },
            onChanged: onChanged,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: l10n.addSense,
            icon: LucideIcons.plus,
            variant: AppButtonVariant.secondary,
            onPressed: () {
              senses.add(SenseDraft());
              onChanged();
            },
          ),
        ),
      ],
    );
  }
}

class _SenseCard extends StatelessWidget {
  const _SenseCard({
    super.key,
    required this.sense,
    required this.number,
    required this.showError,
    required this.onUp,
    required this.onDown,
    required this.onDelete,
    required this.onChanged,
  });

  final SenseDraft sense;
  final int number;
  final bool showError;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onDelete;
  final VoidCallback onChanged;

  Future<void> _addLabel(BuildContext context) async {
    final label = await showAppSheet<SenseLabel>(
      context,
      builder: (_) => const _LabelSheet(),
    );
    if (label == null) return;
    sense.labels.add(label);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.row),
        border: Border.all(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpace.s12,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.senseHeading(number),
                      style: AppType.label.copyWith(color: colors.ink),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.moveSenseUp(number),
                  icon: const Icon(LucideIcons.arrowUp),
                  onPressed: onUp,
                ),
                IconButton(
                  tooltip: l10n.moveSenseDown(number),
                  icon: const Icon(LucideIcons.arrowDown),
                  onPressed: onDown,
                ),
                IconButton(
                  tooltip: l10n.deleteSense(number),
                  icon: const Icon(LucideIcons.trash2),
                  onPressed: onDelete,
                ),
              ],
            ),
            Wrap(
              spacing: AppSpace.s8,
              runSpacing: AppSpace.s8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (index, label) in sense.labels.indexed)
                  InputChip(
                    label: Text('[${label.shown}]'),
                    deleteButtonTooltipMessage: l10n.removeLabel(label.shown),
                    onDeleted: () {
                      sense.labels.removeAt(index);
                      onChanged();
                    },
                  ),
                AppButton(
                  label: l10n.addLabel,
                  icon: LucideIcons.tag,
                  variant: AppButtonVariant.text,
                  onPressed: () => _addLabel(context),
                ),
              ],
            ),
            AppTextField(
              label: l10n.senseMeaning,
              controller: sense.meaning,
              minLines: 1,
              maxLines: null,
              errorText: showError ? l10n.senseMeaningRequired : null,
              onChanged: (_) => onChanged(),
            ),
            AppTextField(
              label: l10n.senseExamples,
              hint: l10n.senseExamplesHint,
              controller: sense.examples,
              minLines: 1,
              maxLines: null,
              onChanged: (_) => onChanged(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sheet that adds a label to a sense: a tap on a part of speech of the
/// closed list adds it, or the typed text is added as another label.
class _LabelSheet extends StatefulWidget {
  const _LabelSheet();

  @override
  State<_LabelSheet> createState() => _LabelSheetState();
}

class _LabelSheetState extends State<_LabelSheet> {
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final other = _other.text.trim();
    return AppSheet(
      title: l10n.addLabel,
      body: l10n.labelSheetBody,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpace.s16,
        children: [
          Wrap(
            spacing: AppSpace.s8,
            runSpacing: AppSpace.s8,
            children: [
              for (final category in PartOfSpeech.values)
                ActionChip(
                  label: Text(
                    l10n.partOfSpeechChoice(
                      category.short,
                      l10n.partOfSpeechName(category.name),
                    ),
                  ),
                  onPressed: () =>
                      Navigator.of(context)
                          .pop(PartOfSpeechLabel(category, category.short)),
                ),
            ],
          ),
          AppTextField(
            label: l10n.otherLabel,
            hint: l10n.otherLabelHint,
            controller: _other,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: l10n.addOtherLabel,
          size: AppButtonSize.cta,
          onPressed: other.isEmpty
              ? null
              : () => Navigator.of(context).pop(OtherLabel(other)),
        ),
      ],
    );
  }
}
