import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_button.dart';
import '../../design/app_text_field.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'content.dart';
import 'label_presets.dart';

/// The width of a sense's label field, which holds a short form such as
/// `조동`.
const _labelWidth = 72.0;

/// One sense of a basic card's back as the form edits it: its labels as
/// typed, its meaning, and its examples, one per line (ADR 0100).
class SenseDraft {
  SenseDraft([CardSense? sense])
    : _stored = [...?sense?.labels],
      label = TextEditingController(text: _typed(sense?.labels ?? const [])),
      meaning = TextEditingController(text: sense?.meaning ?? ''),
      examples = TextEditingController(
        text: (sense?.examples ?? const []).join('\n'),
      ),
      hasExamples = sense?.examples.isNotEmpty ?? false;

  /// The labels the sense opened with, kept while their text is left as it
  /// was, so a label keeps the text it was printed with.
  final List<SenseLabel> _stored;

  final TextEditingController label;
  final TextEditingController meaning;
  final TextEditingController examples;

  /// The label field's focus, which shows the presets above the keyboard.
  final labelFocus = FocusNode();

  /// Whether the sense opened with examples, so their field is shown.
  final bool hasExamples;

  /// The labels as saved: those the sense opened with while their text is
  /// unchanged, otherwise one per word typed.
  List<SenseLabel> get labels =>
      label.text == _typed(_stored) ? [..._stored] : labelsOf(label.text);

  /// Whether the meaning is empty, which saving refuses.
  bool get isBlank => meaning.text.trim().isEmpty;

  /// Whether the sense has no label and no example, so a back of it alone
  /// is plain text.
  bool get isPlain => labels.isEmpty && examples.text.trim().isEmpty;

  /// The sense as saved: its labels, its meaning trimmed, and each non-empty
  /// line of its examples, trimmed.
  CardSense get sense => CardSense(
    labels: labels,
    meaning: meaning.text.trim(),
    examples: [
      for (final line in examples.text.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ],
  );

  void dispose() {
    label.dispose();
    meaning.dispose();
    examples.dispose();
    labelFocus.dispose();
  }

  /// [labels] as the label field shows them, one space apart.
  static String _typed(List<SenseLabel> labels) =>
      labels.map((label) => label.shown).join(' ');
}

/// A basic card's back: one meaning, or its senses, each with a label typed
/// beside its meaning, and under them "뜻 추가". With more than one sense,
/// each moves up or down, or is deleted, by its buttons, which a screen
/// reader reaches by name. With [showErrors], an empty meaning says so under
/// it.
class SenseFields extends StatelessWidget {
  const SenseFields({
    super.key,
    required this.senses,
    required this.showErrors,
    required this.onChanged,
    this.meaningLabel,
  });

  final List<SenseDraft> senses;
  final bool showErrors;

  /// Called after every change to [senses], which this widget makes in place.
  final VoidCallback onChanged;

  /// The label of the one meaning's field while there is one sense; "뒷면"
  /// when null.
  final String? meaningLabel;

  void _move(int from, int to) {
    senses.insert(to, senses.removeAt(from));
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final single = senses.length == 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpace.s16,
      children: [
        for (final (index, sense) in senses.indexed)
          _SenseRow(
            // Keyed by the draft, so a moved sense keeps its fields' focus and
            // text.
            key: ObjectKey(sense),
            sense: sense,
            number: single ? null : index + 1,
            meaningLabel: meaningLabel,
            showError: showErrors && sense.isBlank,
            onUp: index == 0 ? null : () => _move(index, index - 1),
            onDown: index == senses.length - 1
                ? null
                : () => _move(index, index + 1),
            onDelete: () {
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

/// One sense: its label field beside its meaning, and its examples when it
/// has any. [number] is null while it is the back's one meaning, which reads
/// as the back and has no buttons.
class _SenseRow extends StatelessWidget {
  const _SenseRow({
    super.key,
    required this.sense,
    required this.number,
    required this.showError,
    required this.onUp,
    required this.onDown,
    required this.onDelete,
    required this.onChanged,
    this.meaningLabel,
  });

  final SenseDraft sense;
  final int? number;
  final bool showError;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  final String? meaningLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final number = this.number;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpace.s8,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpace.s8,
          children: [
            SizedBox(
              width: _labelWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpace.s8,
                children: [
                  // The meaning's label line, so both fields start level.
                  ExcludeSemantics(
                    child: Text(
                      ' ',
                      style: AppType.section.copyWith(color: colors.ink2),
                    ),
                  ),
                  MergeSemantics(
                    child: Semantics(
                      label: number == null
                          ? l10n.senseLabelHint
                          : l10n.senseLabelField(number),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: AppSize.field,
                        ),
                        child: TextField(
                          controller: sense.label,
                          focusNode: sense.labelFocus,
                          textAlign: TextAlign.center,
                          style: AppType.bodyStrong,
                          onChanged: (_) => onChanged(),
                          decoration: InputDecoration(
                            hintText: l10n.senseLabelHint,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.s8,
                              vertical: AppSpace.s12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AppTextField(
                label: number == null
                    ? meaningLabel ?? l10n.cardBack
                    : l10n.senseHeading(number),
                controller: sense.meaning,
                minLines: number == null ? 2 : 1,
                maxLines: null,
                errorText: !showError
                    ? null
                    : number == null
                    ? l10n.cardSideRequired
                    : l10n.senseMeaningRequired,
                onChanged: (_) => onChanged(),
              ),
            ),
          ],
        ),
        if (sense.hasExamples)
          AppTextField(
            label: l10n.senseExamples,
            hint: l10n.senseExamplesHint,
            controller: sense.examples,
            minLines: 1,
            maxLines: null,
            onChanged: (_) => onChanged(),
          ),
        if (number != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
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
      ],
    );
  }
}

/// The user's labels in a strip above the keyboard while a sense's label
/// field has focus: a tap on one fills that field with it, and "관리" opens
/// the "품사 표시" screen.
class LabelPresetStrip extends StatelessWidget {
  const LabelPresetStrip({
    super.key,
    required this.presets,
    required this.current,
    required this.onPick,
    required this.onManage,
  });

  final List<LabelPreset> presets;

  /// The focused field's text, whose preset shows chosen.
  final String current;
  final ValueChanged<String> onPick;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      container: true,
      label: l10n.labelPresetsTitle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.outline)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.s12,
            vertical: AppSpace.s8,
          ),
          child: Row(
            spacing: AppSpace.s8,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: AppSpace.s8,
                    children: [
                      for (final preset in presets)
                        ChoiceChip(
                          label: Text(preset.label),
                          tooltip: preset.name.isEmpty ? null : preset.name,
                          showCheckmark: false,
                          labelStyle: AppType.bodyStrong.copyWith(
                            color: colors.ink,
                          ),
                          selectedColor: colors.brandTint,
                          selected: preset.label == current.trim(),
                          onSelected: (_) => onPick(preset.label),
                        ),
                    ],
                  ),
                ),
              ),
              AppButton(
                label: l10n.manageLabelPresets,
                variant: AppButtonVariant.text,
                onPressed: onManage,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
