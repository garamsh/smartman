import 'package:flutter/material.dart' hide Card;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../deck/deck.dart';
import '../../design/app_button.dart';
import '../../design/app_list_row.dart';
import '../../design/app_sheet.dart';
import '../../design/theme.dart';
import '../../design/word_break.dart';
import '../../l10n/app_localizations.dart';
import 'card_edit_sheet.dart';
import 'import_list.dart';

/// The cards made from the photo, as one list in sections by topic: each row
/// included or left out by its check or a swipe left, and edited in a sheet
/// on a tap; each section's cards take the form its menu sets. The button
/// adds every included row's cards.
class ImportListView extends StatefulWidget {
  const ImportListView({
    super.key,
    required this.list,
    required this.decks,
    required this.target,
    required this.onTarget,
    required this.saving,
    required this.onChanged,
    required this.onCancel,
    required this.onRetake,
    required this.retakeLabel,
    required this.onSave,
  });

  final ImportList list;
  final List<Deck> decks;

  /// The deck the cards go into; null for a new deck.
  final Deck? target;

  /// Chooses the deck the cards go into; null for a new deck.
  final ValueChanged<DeckId?> onTarget;

  final bool saving;

  /// Called after [list] changed in place.
  final VoidCallback onChanged;

  final VoidCallback onCancel;
  final VoidCallback onRetake;

  /// What the retake is called: "다시 찍기", or "다른 사진 고르기" for a photo
  /// from the album.
  final String retakeLabel;
  final VoidCallback onSave;

  @override
  State<ImportListView> createState() => _ImportListViewState();
}

class _ImportListViewState extends State<ImportListView> {
  ImportList get _list => widget.list;

  void _change(VoidCallback change) {
    setState(change);
    widget.onChanged();
  }

  /// Opens [row]'s edit sheet. The row keeps the state it had, so an edit
  /// whose front the deck holds is not left out: it merges back when saved.
  Future<void> _edit(ImportRow row) async {
    final included = _list.isIncluded(row);
    if (await showCardEditSheet(context, row)) {
      _change(() => row.included ??= included);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final count = _list.cardCount;
    final rows = _list.rows.length;
    return Scaffold(
      appBar: AppBar(
        leadingWidth: AppSize.tapTarget * 2,
        leading: Padding(
          padding: const EdgeInsets.only(left: AppSpace.s4),
          child: AppButton(
            label: l10n.cancel,
            variant: AppButtonVariant.text,
            onPressed: widget.onCancel,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.s4),
            child: AppButton(
              label: widget.retakeLabel,
              variant: AppButtonVariant.text,
              onPressed: widget.onRetake,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter,
              0,
              AppSpace.gutter,
              AppSize.cta + AppSize.cta + AppSpace.s40,
            ),
            children: [
              Semantics(
                header: true,
                child: Text(
                  _list.allVocabulary
                      ? l10n.importTitleWords(rows)
                      : l10n.importTitleCards(rows),
                  style: AppType.display.copyWith(color: colors.ink),
                ),
              ),
              _DeckLine(
                name: widget.target?.name ?? l10n.newDeck,
                onTap: () => _chooseTarget(context),
              ),
              for (final section in _list.sections) ...[
                const SizedBox(height: AppSpace.s20),
                _SectionHeader(
                  list: _list,
                  section: section,
                  onChanged: () => _change(() {}),
                ),
                const SizedBox(height: AppSpace.s8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.field),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.field),
                    child: Column(
                      children: [
                        for (final (i, row) in section.rows.indexed)
                          _RowTile(
                            key: ObjectKey(row),
                            sides: row.cards(section.form).first,
                            included: _list.isIncluded(row),
                            inDeck: _list.isDuplicate(row),
                            first: i == 0,
                            onCheck: row.savable
                                ? () => _change(
                                    () => row.included = !_list.isIncluded(row),
                                  )
                                : null,
                            onExclude: () =>
                                _change(() => row.included = false),
                            onEdit: () => _edit(row),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [colors.ground.withValues(alpha: 0), colors.ground],
                  stops: const [0, 0.3],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.gutter,
                    AppSpace.s24,
                    AppSpace.gutter,
                    AppSpace.s16,
                  ),
                  child: AppButton(
                    label: l10n.importAdd(count),
                    size: AppButtonSize.cta,
                    loading: widget.saving,
                    onPressed: count == 0 ? null : widget.onSave,
                  ),
                ),
              ),
            ),
          ),
        ],
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

/// "덱 '`name`'에 추가돼요", the name a button that opens the deck chooser.
class _DeckLine extends StatelessWidget {
  const _DeckLine({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    // The localized line, split around the name it holds.
    const marker = '\u0000';
    final [before, after] = l10n.importDeck(marker).split(marker);
    final style = AppType.label.copyWith(color: colors.muted);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (before.isNotEmpty) Text(before, style: style),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, AppSize.tapTarget),
            tapTargetSize: MaterialTapTargetSize.padded,
            foregroundColor: colors.ink,
            textStyle: AppType.label.copyWith(
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
          ),
          child: Text(name),
        ),
        if (after.isNotEmpty) Text(after, style: style),
      ],
    );
  }
}

/// A section's topic and row count, and the menu of its cards' form.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.list,
    required this.section,
    required this.onChanged,
  });

  final ImportList list;
  final ImportSection section;

  /// Called after the section's form or rows changed.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final topic = section.topic ?? l10n.importTopicNone;
    final title = section.identify ? l10n.importIdentifySection(topic) : topic;
    final form = section.form;
    final formLabel = switch (form) {
      VocabularyForm(direction: Direction.forward) => l10n.importForward,
      VocabularyForm(direction: Direction.backward) => l10n.importBackward,
      VocabularyForm(direction: Direction.both) => l10n.importBothShort,
      NoteForm(swapped: false) => l10n.importNoteForward,
      NoteForm(swapped: true) => l10n.importNoteSwapped,
    };
    void set(SectionForm next) {
      section.form = next;
      onChanged();
    }

    /// A menu item that does [onTap]: a choice, read as checked or not, when
    /// [checked] is given, else a plain action.
    Widget item(String label, {bool? checked, required VoidCallback onTap}) {
      final button = MenuItemButton(
        onPressed: onTap,
        leadingIcon: SizedBox(
          width: AppSize.smallIcon,
          child: checked == true
              ? const Icon(LucideIcons.check, size: AppSize.smallIcon)
              : null,
        ),
        child: Text(label),
      );
      // One node, so a screen reader hears a choice's state with its label.
      return checked == null
          ? button
          : MergeSemantics(
              child: Semantics(checked: checked, child: button),
            );
    }

    // The heavier rule between a menu's groups.
    final separator = Divider(
      height: AppSpace.s4,
      thickness: AppSpace.s4,
      color: colors.hairline,
    );
    final anyIncluded = section.rows.any(list.isIncluded);
    final pronunciations = section.rows.any((row) => row.pronunciation != null);
    final extras = section.rows.any((row) => row.extras.isNotEmpty);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(
              left: AppSpace.s4,
              bottom: AppSpace.s12,
            ),
            child: Text(
              l10n.importSection(title, section.rows.length),
              style: AppType.caption.copyWith(color: colors.muted),
            ),
          ),
        ),
        MenuAnchor(
          alignmentOffset: const Offset(0, AppSpace.s4),
          menuChildren: [
            if (form case final VocabularyForm vocabulary) ...[
              for (final (direction, label) in [
                (Direction.forward, l10n.importForward),
                (Direction.backward, l10n.importBackward),
                (Direction.both, l10n.importBoth),
              ])
                item(
                  label,
                  checked: vocabulary.direction == direction,
                  onTap: () => set(vocabulary.copyWith(direction: direction)),
                ),
              separator,
              item(
                l10n.importFirstSense,
                checked: vocabulary.firstSenseOnly,
                onTap: () => set(
                  vocabulary.copyWith(
                    firstSenseOnly: !vocabulary.firstSenseOnly,
                  ),
                ),
              ),
              item(
                l10n.importShowPos,
                checked: vocabulary.showPos,
                onTap: () =>
                    set(vocabulary.copyWith(showPos: !vocabulary.showPos)),
              ),
              if (pronunciations)
                item(
                  l10n.importShowPronunciation,
                  checked: vocabulary.showPronunciation,
                  onTap: () => set(
                    vocabulary.copyWith(
                      showPronunciation: !vocabulary.showPronunciation,
                    ),
                  ),
                ),
              if (extras)
                item(
                  l10n.importShowExtras,
                  checked: vocabulary.showExtras,
                  onTap: () => set(
                    vocabulary.copyWith(showExtras: !vocabulary.showExtras),
                  ),
                ),
            ],
            if (form case NoteForm(:final swapped))
              item(
                l10n.importSwap,
                checked: swapped,
                onTap: () => set(NoteForm(swapped: !swapped)),
              ),
            separator,
            item(
              anyIncluded ? l10n.importDropSection : l10n.importKeepSection,
              onTap: () {
                list.toggleSection(section);
                onChanged();
              },
            ),
          ],
          builder: (context, controller, _) => Semantics(
            container: true,
            button: true,
            label: l10n.importFormMenu(title, formLabel),
            excludeSemantics: true,
            child: TextButton(
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              style: TextButton.styleFrom(
                foregroundColor: colors.ink,
                minimumSize: const Size(AppSize.tapTarget, AppSize.tapTarget),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4),
                textStyle: AppType.caption.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: AppSpace.s4,
                children: [
                  Text(formLabel),
                  const Icon(LucideIcons.chevronDown, size: AppSpace.s12),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One row: its check, its front at 44% and its back one line per sense,
/// "이미 덱에 있어요" under it when the deck holds it. A tap edits it, and a
/// swipe left leaves it out.
class _RowTile extends StatelessWidget {
  const _RowTile({
    super.key,
    required this.sides,
    required this.included,
    required this.inDeck,
    required this.first,
    required this.onCheck,
    required this.onExclude,
    required this.onEdit,
  });

  final CardSides sides;
  final bool included;
  final bool inDeck;

  /// Whether it is the section's first row, with no separator above it.
  final bool first;

  /// Includes or leaves out the row; null while it has nothing to save.
  final VoidCallback? onCheck;

  final VoidCallback onExclude;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final onCheck = this.onCheck;
    final tile = DecoratedBox(
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(top: BorderSide(color: colors.hairline, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            checked: included,
            label: l10n.importInclude(sides.front),
            excludeSemantics: true,
            onTap: onCheck,
            child: InkResponse(
              onTap: onCheck,
              radius: AppSize.tapTarget / 2,
              child: SizedBox(
                width: AppSize.tapTarget + AppSpace.s4,
                height: AppSize.tapTarget + AppSpace.s4,
                child: Center(child: _Check(on: included)),
              ),
            ),
          ),
          Expanded(
            child: Semantics(
              container: true,
              button: true,
              label: l10n.importRow(sides.front, sides.back),
              excludeSemantics: true,
              onTap: onEdit,
              child: InkWell(
                onTap: onEdit,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    0,
                    AppSpace.s12,
                    AppSpace.s16,
                    AppSpace.s12,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: AppSpace.s4,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: AppSpace.s12,
                          children: [
                            SizedBox(
                              width: constraints.maxWidth * 0.44,
                              child: Text(
                                keepWords(sides.front),
                                style: AppType.bodyStrong.copyWith(
                                  color: included ? colors.ink : colors.muted,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                keepWords(sides.back),
                                style: AppType.secondary.copyWith(
                                  color: included ? colors.ink2 : colors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (inDeck)
                          Text(
                            l10n.importInDeck,
                            style: AppType.caption.copyWith(
                              color: colors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Dismissible(
      key: key ?? UniqueKey(),
      direction: included ? DismissDirection.endToStart : DismissDirection.none,
      confirmDismiss: (_) async {
        onExclude();
        return false;
      },
      background: ColoredBox(
        color: colors.dontKnowText,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpace.gutter),
            child: Text(
              l10n.importRemove,
              style: AppType.label.copyWith(color: colors.onDontKnowText),
            ),
          ),
        ),
      ),
      child: Material(type: MaterialType.transparency, child: tile),
    );
  }
}

/// A round check, filled in ink with a tick when on, outlined when off.
class _Check extends StatelessWidget {
  const _Check({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: AppSpace.s20 + AppSpace.s4,
      height: AppSpace.s20 + AppSpace.s4,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? colors.ink : null,
        border: on ? null : Border.all(color: colors.muted, width: 1.5),
      ),
      child: on
          ? Icon(
              LucideIcons.check,
              size: AppSize.checkIcon,
              color: colors.onPrimary,
            )
          : null,
    );
  }
}
