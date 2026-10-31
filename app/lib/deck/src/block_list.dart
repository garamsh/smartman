import 'package:flutter/material.dart';

import '../../design/app_sheet.dart';
import '../../design/app_text_field.dart';
import '../../design/theme.dart';
import '../../design/word_break.dart';
import '../../l10n/app_localizations.dart';
import '../../media/media.dart';
import 'audio_block.dart';
import 'cloze_block.dart';
import 'content.dart';
import 'editor_group.dart';
import 'image_block.dart';
import 'senses_block.dart';
import 'table_block.dart';

/// A side of a card, which a block list adds to.
enum CardSide { front, back }

/// A block type the add sheet offers. A type whose block issue has not
/// landed is not one of them (ADR 0108).
enum BlockType {
  text,
  senses,
  table,
  cloze,
  image,
  audio;

  /// An empty block of this type: a 글 with no text, one empty meaning, a
  /// table of two rows of two cells, a line with no blank, a 사진 with no
  /// photo yet, or a 소리 with no sound yet.
  BlockDraft draft() => switch (this) {
    text => TextBlockDraft(),
    senses => SensesBlockDraft(),
    table => TableBlockDraft(),
    cloze => ClozeBlockDraft(),
    image => ImageBlockDraft(),
    audio => AudioBlockDraft(),
  };

  String title(AppLocalizations l10n) => switch (this) {
    text => l10n.blockText,
    senses => l10n.blockSenses,
    table => l10n.blockTable,
    cloze => l10n.blockCloze,
    image => l10n.blockImage,
    audio => l10n.blockAudio,
  };

  /// The line under the type in the add sheet, or null where its name says
  /// enough: 글.
  String? description(AppLocalizations l10n) => switch (this) {
    text => null,
    senses => l10n.blockSensesDescription,
    table => l10n.blockTableDescription,
    cloze => l10n.blockClozeDescription,
    image => l10n.blockImageDescription,
    audio => l10n.blockAudioDescription,
  };
}

/// A block as a block list edits it.
sealed class BlockDraft {
  /// A draft of [block]: its text, senses, table or line, or a block this
  /// build cannot read, kept as it is.
  static BlockDraft of(Content block) => switch (block) {
    TextContent(:final text) => TextBlockDraft(text),
    SensesContent(:final senses) => SensesBlockDraft(senses),
    TableContent() => TableBlockDraft(block),
    ClozeContent() => ClozeBlockDraft(block),
    ImageContent() => ImageBlockDraft(block),
    AudioContent() => AudioBlockDraft(block),
    final UnsupportedContent kept => KeptBlockDraft(kept),
  };

  /// The block's type, or null for a block this build cannot read.
  BlockType? get type;

  /// The block as saved; meaningful once [isComplete].
  Content get content;

  /// The block as the preview draws it, while it may still be incomplete.
  Content get preview => content;

  /// Whether the block can be saved as it is.
  bool get isComplete;

  void dispose() {}
}

/// A 글 block: its text as typed.
final class TextBlockDraft extends BlockDraft {
  TextBlockDraft([String text = '']) : text = TextEditingController(text: text);

  final TextEditingController text;

  /// The field's focus, which a new card's first block takes.
  final focus = FocusNode();

  @override
  BlockType get type => BlockType.text;

  @override
  Content get content => TextContent(text.text);

  /// Whether nothing but spaces is typed, so the editor saves no block for
  /// it.
  bool get isEmpty => text.text.trim().isEmpty;

  @override
  bool get isComplete => true;

  @override
  void dispose() {
    text.dispose();
    focus.dispose();
  }
}

/// A 뜻 목록 block: its senses, one empty meaning when new.
final class SensesBlockDraft extends BlockDraft {
  SensesBlockDraft([List<CardSense> senses = const []])
    : senses = senses.isEmpty
          ? [SenseDraft()]
          : [for (final sense in senses) SenseDraft(sense)];

  final List<SenseDraft> senses;

  @override
  BlockType get type => BlockType.senses;

  @override
  Content get content =>
      SensesContent([for (final sense in senses) sense.sense]);

  @override
  bool get isComplete => !senses.any((sense) => sense.isBlank);

  @override
  void dispose() {
    for (final sense in senses) {
      sense.dispose();
    }
  }
}

/// A 표 block: its headers, cells and blanks.
final class TableBlockDraft extends BlockDraft {
  TableBlockDraft([TableContent? table])
    : table = table == null ? TableDraft() : TableDraft.of(table);

  final TableDraft table;

  @override
  BlockType get type => BlockType.table;

  @override
  Content get content => table.table;

  @override
  bool get isComplete => table.problem == null;

  @override
  void dispose() => table.dispose();
}

/// A 빈칸 문장 block: its line and blanks, kept as stored until either is
/// edited, so a blank inside a word survives an unchanged save.
final class ClozeBlockDraft extends BlockDraft {
  ClozeBlockDraft([ClozeContent? stored])
    : _stored = stored,
      cloze = stored == null ? ClozeDraft() : ClozeDraft.of(stored) {
    line = ClozeLineController(
      text: cloze.line,
      blanks: () => cloze.line == line.text ? cloze.blanks : const [],
    )..addListener(_sync);
  }

  final ClozeContent? _stored;
  final ClozeDraft cloze;
  late final ClozeLineController line;

  /// The line's focus, which shows the cloze's action above the keyboard.
  final focus = FocusNode();

  /// Whether the line or its blanks were changed since the block opened.
  bool edited = false;

  @override
  BlockType get type => BlockType.cloze;

  /// Keeps the blanks on the line as it is typed, and ends the blank "빈칸
  /// 넣기" opened once the cursor leaves it.
  void _sync() => cloze
    ..update(line.text)
    ..track(line.selection);

  @override
  Content get content => switch (_stored) {
    final stored? when !edited => stored,
    _ => cloze.content ?? cloze.preview,
  };

  @override
  Content get preview => edited || _stored == null ? cloze.preview : content;

  @override
  bool get isComplete => (!edited && _stored != null) || cloze.content != null;

  @override
  void dispose() {
    line
      ..removeListener(_sync)
      ..dispose();
    focus.dispose();
  }
}

/// A 사진 block: its photo, once chosen, and the boxes over it (ADR 0109).
final class ImageBlockDraft extends BlockDraft {
  ImageBlockDraft([ImageContent? image]) : image = ImageDraft(image);

  final ImageDraft image;

  @override
  BlockType get type => BlockType.image;

  /// The photo and its boxes; an empty 글 while no photo is chosen, which
  /// [isComplete] refuses to save.
  @override
  Content get content => image.image ?? const TextContent('');

  @override
  bool get isComplete => image.image != null;

  @override
  void dispose() => image.dispose();
}

/// A 소리 block: its sound, once recorded or picked (ADR 0112).
final class AudioBlockDraft extends BlockDraft {
  AudioBlockDraft([AudioContent? audio]) : audio = AudioDraft(audio);

  final AudioDraft audio;

  @override
  BlockType get type => BlockType.audio;

  /// The sound; an empty 글 while none is in it, which [isComplete] refuses
  /// to save.
  @override
  Content get content => audio.audio ?? const TextContent('');

  @override
  bool get isComplete => audio.audio != null;
}

/// A block this build cannot read, kept and written back as it was stored.
final class KeptBlockDraft extends BlockDraft {
  KeptBlockDraft(this.content);

  @override
  final UnsupportedContent content;

  @override
  BlockType? get type => null;

  @override
  bool get isComplete => true;
}

/// One side's [blocks] in one white group, each a row separated from the
/// next by a hairline, with a ⋯ menu that moves it up or down or deletes
/// it, a non-drag way to reorder (WCAG 2.2 dragging); a block's type is
/// named over its fields but for a 글's. The group ends with "+ 추가",
/// which opens a sheet of the types to add, titled "앞면에 추가" or
/// "뒷면에 추가" (ADR 0108, ADR 0117). With [showErrors], what keeps a
/// block from being saved shows under it. [emptyError], given while the
/// side must hold a block and holds none to save, shows under the group
/// when it holds no block, and each empty 글 then asks for its text.
class BlockList extends StatelessWidget {
  const BlockList({
    super.key,
    required this.side,
    required this.blocks,
    required this.showErrors,
    required this.onChanged,
    required this.onMediaStored,
    this.emptyError,
  });

  final CardSide side;
  final List<BlockDraft> blocks;
  final bool showErrors;
  final String? emptyError;

  /// Called after every change, which this widget makes in place.
  final VoidCallback onChanged;

  /// Called with each photo a 사진 block and each sound a 소리 block stores,
  /// so the editor can let go of one the card is not saved with.
  final ValueChanged<MediaId> onMediaStored;

  void _act(int index, RowAction action) {
    switch (action) {
      case RowAction.up:
        blocks.insert(index - 1, blocks.removeAt(index));
      case RowAction.down:
        blocks.insert(index + 1, blocks.removeAt(index));
      case RowAction.delete:
        blocks.removeAt(index).dispose();
    }
    onChanged();
  }

  Future<void> _add(BuildContext context) async {
    final type = await showAppSheet<BlockType>(
      context,
      builder: (context) => AppSheet(
        title: _addLabel(AppLocalizations.of(context)),
        content: const _TypeList(),
      ),
    );
    if (type == null) return;
    blocks.add(type.draft());
    onChanged();
  }

  String _addLabel(AppLocalizations l10n) => switch (side) {
    CardSide.front => l10n.addToFront,
    CardSide.back => l10n.addToBack,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final emptyError = this.emptyError;
    final sideName = switch (side) {
      CardSide.front => l10n.cardFront,
      CardSide.back => l10n.cardBack,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpace.s8,
      children: [
        EditorGroup(
          children: [
            for (final (index, block) in blocks.indexed)
              _Block(
                // Keyed by the draft, so a moved block keeps its fields'
                // focus and state.
                key: ObjectKey(block),
                block: block,
                menuLabel: l10n.blockMenu(sideName, index + 1),
                showErrors: showErrors,
                sideRequired: emptyError != null,
                onChanged: onChanged,
                onMediaStored: onMediaStored,
                onAction: (action) => _act(index, action),
                canMoveUp: index > 0,
                canMoveDown: index < blocks.length - 1,
              ),
            GroupAddRow(
              label: l10n.addBlock,
              semanticsLabel: _addLabel(l10n),
              onPressed: () => _add(context),
            ),
          ],
        ),
        if (emptyError != null && blocks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4),
            child: Text(
              keepWords(emptyError),
              semanticsLabel: emptyError,
              style: AppType.caption.copyWith(color: colors.dontKnowText),
            ),
          ),
      ],
    );
  }
}

/// The add sheet's one grouped list of block types, each its name and,
/// where the name does not say enough, one line under it; a tap picks it.
class _TypeList extends StatelessWidget {
  const _TypeList();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Material(
      color: colors.ground,
      borderRadius: BorderRadius.circular(AppRadius.group),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, type) in BlockType.values.indexed) ...[
            if (index > 0) const Divider(height: 1, thickness: 1),
            MergeSemantics(
              child: InkWell(
                onTap: () => Navigator.of(context).pop(type),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppSize.tapTarget,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.s16,
                      vertical: AppSpace.s12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(type.title(l10n), style: AppType.bodyStrong),
                        if (type.description(l10n) case final line?)
                          Text(
                            keepWords(line),
                            semanticsLabel: line,
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
          ],
        ],
      ),
    );
  }
}

/// One block's row: a 글's field beside its menu, or a block's type and menu
/// over its fields, or, for a block this build cannot read, its placeholder
/// line and menu with no field.
class _Block extends StatelessWidget {
  const _Block({
    super.key,
    required this.block,
    required this.menuLabel,
    required this.showErrors,
    required this.sideRequired,
    required this.onChanged,
    required this.onMediaStored,
    required this.onAction,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  final BlockDraft block;
  final ValueChanged<MediaId> onMediaStored;
  final String menuLabel;
  final bool showErrors;

  /// Whether the side must hold a block and holds none to save, so an empty
  /// 글 asks for its text.
  final bool sideRequired;
  final VoidCallback onChanged;
  final ValueChanged<RowAction> onAction;
  final bool canMoveUp;
  final bool canMoveDown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final menu = RowMenu(
      label: menuLabel,
      upLabel: l10n.moveUp,
      downLabel: l10n.moveDown,
      deleteLabel: l10n.deleteBlock,
      canMoveUp: canMoveUp,
      canMoveDown: canMoveDown,
      onAction: onAction,
    );
    final block = this.block;
    if (block is TextBlockDraft) {
      return Padding(
        padding: const EdgeInsets.all(groupInset),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                controller: block.text,
                focusNode: block.focus,
                hint: l10n.blockTextDescription,
                minLines: 2,
                maxLines: null,
                errorText: sideRequired && block.isEmpty
                    ? l10n.cardSideRequired
                    : null,
                onChanged: (_) => onChanged(),
              ),
            ),
            menu,
          ],
        ),
      );
    }
    final title = switch (block) {
      KeptBlockDraft(:final content) => l10n.unsupportedContent(content.type),
      TextBlockDraft(:final type) ||
      SensesBlockDraft(:final type) ||
      TableBlockDraft(:final type) ||
      ClozeBlockDraft(:final type) ||
      ImageBlockDraft(:final type) ||
      AudioBlockDraft(:final type) => type.title(l10n),
    };
    final fields = switch (block) {
      TextBlockDraft() || KeptBlockDraft() => null,
      SensesBlockDraft(:final senses) => SenseFields(
        senses: senses,
        showErrors: showErrors,
        onChanged: onChanged,
      ),
      TableBlockDraft(:final table) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.s16,
          0,
          AppSpace.s16,
          AppSpace.s16,
        ),
        child: TableFields(
          draft: table,
          showErrors: showErrors,
          onChanged: onChanged,
        ),
      ),
      final ClozeBlockDraft draft => _ClozeFields(
        draft: draft,
        showErrors: showErrors,
        onChanged: onChanged,
      ),
      ImageBlockDraft(:final image) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.s16,
          0,
          AppSpace.s16,
          AppSpace.s16,
        ),
        child: ImageBlockFields(
          draft: image,
          showErrors: showErrors,
          onChanged: onChanged,
          onPicked: onMediaStored,
        ),
      ),
      AudioBlockDraft(:final audio) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.s16,
          0,
          AppSpace.s16,
          AppSpace.s16,
        ),
        child: AudioBlockFields(
          draft: audio,
          showErrors: showErrors,
          onChanged: onChanged,
          onStored: onMediaStored,
        ),
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          // The menu's inset matches a 글's, so the menus line up.
          padding: const EdgeInsets.only(right: groupInset),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: AppSpace.s20),
                  child: Text(
                    title,
                    style: AppType.caption.copyWith(color: colors.muted),
                  ),
                ),
              ),
              menu,
            ],
          ),
        ),
        ?fields,
      ],
    );
  }
}

/// A 빈칸 문장's line, borderless in its group, and right under it, while the
/// line has focus, its one action as a small outlined chip that follows the
/// caret, "빈칸 넣기" or "빈칸 풀기" (ADR 0101, ADR 0117); then what keeps it
/// from being saved, with [showErrors].
class _ClozeFields extends StatelessWidget {
  const _ClozeFields({
    required this.draft,
    required this.showErrors,
    required this.onChanged,
  });

  final ClozeBlockDraft draft;
  final bool showErrors;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = this.draft;
    return Padding(
      padding: const EdgeInsets.fromLTRB(groupInset, 0, groupInset, groupInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClozeEmptyBlanks(
            controller: draft.line,
            child: AppTextField(
              controller: draft.line,
              focusNode: draft.focus,
              hint: l10n.blockClozeDescription,
              minLines: 2,
              maxLines: null,
              onChanged: (_) {
                draft.edited = true;
                onChanged();
              },
            ),
          ),
          if (draft.focus.hasFocus)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12),
              child: ListenableBuilder(
                listenable: draft.line,
                builder: (context, _) => ClozeAction(
                  draft: draft.cloze,
                  blank: draft.cloze.blankAt(draft.line.selection),
                  onInsert: () {
                    draft.cloze.insert(draft.line.selection);
                    draft.edited = true;
                    onChanged();
                  },
                  onUndo: (blank) {
                    draft.cloze.remove(blank);
                    draft.edited = true;
                    onChanged();
                  },
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
            child: ClozeProblemText(
              draft: draft.cloze,
              showError: showErrors && !draft.isComplete,
            ),
          ),
        ],
      ),
    );
  }
}
