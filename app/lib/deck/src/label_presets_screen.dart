import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_button.dart';
import '../../design/app_list_row.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'card_kind.dart';
import 'failure_message.dart';
import 'label_presets.dart';

/// The settings row "품사 표시", which opens [PartOfSpeechPresetsScreen].
class PartOfSpeechPresetsRow extends StatelessWidget {
  const PartOfSpeechPresetsRow({super.key});

  @override
  Widget build(BuildContext context) => AppListRow(
    title: AppLocalizations.of(context).labelPresetsTitle,
    trailing: const Icon(LucideIcons.chevronRight),
    onTap: () => openPartOfSpeechPresets(context),
  );
}

/// Pushes the "품사 표시" screen.
Future<void> openPartOfSpeechPresets(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PartOfSpeechPresetsScreen(),
      ),
    );

/// "품사 표시": the labels the card editor offers above the keyboard, in
/// their order, each with its name. A tap on one edits it in place, its
/// delete button removes it, "표시 추가" adds one, and each moves by a drag on its handle or
/// by "위로" and "아래로" in the handle's menu. Every change is stored on the
/// device at once (ADR 0100).
class PartOfSpeechPresetsScreen extends ConsumerStatefulWidget {
  const PartOfSpeechPresetsScreen({super.key});

  @override
  ConsumerState<PartOfSpeechPresetsScreen> createState() =>
      _PartOfSpeechPresetsScreenState();
}

class _PartOfSpeechPresetsScreenState
    extends ConsumerState<PartOfSpeechPresetsScreen> {
  late List<LabelPreset> _presets = labelPresets(
    ref.read(deckStorageProvider),
    defaultLabelPresets(AppLocalizations.of(context)),
  );

  /// The preset being edited, by its place, or null.
  int? _editing;

  /// Whether the preset being edited was just added, so leaving it empty
  /// removes it.
  bool _adding = false;

  final _label = TextEditingController();
  final _name = TextEditingController();
  bool _showLabelError = false;

  @override
  void dispose() {
    _label.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _store(List<LabelPreset> presets) async {
    setState(() => _presets = presets);
    await reportingFailure(
      context,
      () => saveLabelPresets(ref.read(deckStorageProvider), presets),
    );
  }

  void _edit(int index) => setState(() {
    _editing = index;
    _adding = false;
    _showLabelError = false;
    _label.text = _presets[index].label;
    _name.text = _presets[index].name;
  });

  void _add() => setState(() {
    _presets = [..._presets, const LabelPreset('')];
    _editing = _presets.length - 1;
    _adding = true;
    _showLabelError = false;
    _label.clear();
    _name.clear();
  });

  Future<void> _done() async {
    final index = _editing!;
    final label = _label.text.trim();
    if (label.isEmpty) {
      if (_adding && _name.text.trim().isEmpty) {
        setState(() {
          _presets = [..._presets]..removeAt(index);
          _editing = null;
        });
      } else {
        setState(() => _showLabelError = true);
      }
      return;
    }
    _editing = null;
    await _store(
      [..._presets]..[index] = LabelPreset(label, _name.text.trim()),
    );
  }

  Future<void> _remove(int index) async {
    if (_editing != null) _editing = null;
    await _store([..._presets]..removeAt(index));
  }

  Future<void> _move(int from, int to) async {
    final presets = [..._presets];
    presets.insert(to, presets.removeAt(from));
    if (_editing != null) _editing = null;
    await _store(presets);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.labelPresetsTitle)),
      body: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.s8,
          AppSpace.gutter,
          AppSpace.s24,
        ),
        header: Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.s16),
          child: Text(
            l10n.labelPresetsBody,
            style: AppType.secondary.copyWith(color: colors.muted),
          ),
        ),
        footer: Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: l10n.addLabelPreset,
            icon: LucideIcons.plus,
            variant: AppButtonVariant.text,
            onPressed: _editing == null ? _add : null,
          ),
        ),
        itemCount: _presets.length,
        onReorderItem: _move,
        itemBuilder: (context, index) => _editing == index
            ? _EditingRow(
                key: ValueKey(('editing', index)),
                label: _label,
                name: _name,
                showLabelError: _showLabelError,
                onDone: _done,
              )
            : _PresetRow(
                key: ValueKey((_presets[index], index)),
                index: index,
                preset: _presets[index],
                onEdit: _editing == null ? () => _edit(index) : null,
                onRemove: () => _remove(index),
                onUp: index == 0 ? null : () => _move(index, index - 1),
                onDown: index == _presets.length - 1
                    ? null
                    : () => _move(index, index + 1),
              ),
      ),
    );
  }
}

/// What a preset's handle menu offers.
enum _Move { up, down }

/// A preset as it is listed: its handle, which drags it or opens a menu of
/// "위로" and "아래로", its label and name, which a tap edits, and its delete
/// button.
class _PresetRow extends StatelessWidget {
  const _PresetRow({
    super.key,
    required this.index,
    required this.preset,
    required this.onEdit,
    required this.onRemove,
    required this.onUp,
    required this.onDown,
  });

  final int index;
  final LabelPreset preset;
  final VoidCallback? onEdit;
  final VoidCallback onRemove;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return AppRowSurface(
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: PopupMenuButton<_Move>(
              tooltip: l10n.moveLabelPreset(preset.label),
              icon: Icon(LucideIcons.gripVertical, color: colors.muted),
              onSelected: (move) => switch (move) {
                _Move.up => onUp?.call(),
                _Move.down => onDown?.call(),
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _Move.up,
                  enabled: onUp != null,
                  child: Text(l10n.moveUp),
                ),
                PopupMenuItem(
                  value: _Move.down,
                  enabled: onDown != null,
                  child: Text(l10n.moveDown),
                ),
              ],
            ),
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: l10n.editLabelPreset(preset.label, preset.name),
              excludeSemantics: true,
              child: InkWell(
                onTap: onEdit,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppSize.tapTarget,
                  ),
                  child: Row(
                    spacing: AppSpace.s12,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.ground,
                          borderRadius: BorderRadius.circular(AppRadius.field),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.s12,
                            vertical: AppSpace.s4,
                          ),
                          child: Text(preset.label, style: AppType.bodyStrong),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          preset.name,
                          style: AppType.body.copyWith(color: colors.ink2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.removeLabelPreset(preset.label),
            icon: const Icon(LucideIcons.trash2),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// The preset being edited: its label and its name, and "완료". An empty
/// label says so under it.
class _EditingRow extends StatelessWidget {
  const _EditingRow({
    super.key,
    required this.label,
    required this.name,
    required this.showLabelError,
    required this.onDone,
  });

  final TextEditingController label;
  final TextEditingController name;
  final bool showLabelError;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppRowSurface(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpace.s8,
          children: [
            SizedBox(
              width: 96,
              child: TextField(
                controller: label,
                autofocus: true,
                textAlign: TextAlign.center,
                style: AppType.bodyStrong,
                decoration: InputDecoration(
                  labelText: l10n.labelPresetLabel,
                  errorText: showLabelError ? l10n.labelPresetRequired : null,
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: name,
                style: AppType.body,
                decoration: InputDecoration(labelText: l10n.labelPresetName),
                onSubmitted: (_) => onDone(),
              ),
            ),
            AppButton(
              label: l10n.labelPresetDone,
              variant: AppButtonVariant.text,
              onPressed: onDone,
            ),
          ],
        ),
      ),
    );
  }
}
