import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_button.dart';
import '../../design/app_list_row.dart';
import '../../design/app_sheet.dart';
import '../../design/app_text_field.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../media/media.dart';
import 'audio_block.dart';
import 'cloze_block.dart';
import 'content.dart';
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
  /// photo yet, or a 음성 with no sound yet.
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

  String description(AppLocalizations l10n) => switch (this) {
    text => l10n.blockTextDescription,
    senses => l10n.blockSensesDescription,
    table => l10n.blockTableDescription,
    cloze => l10n.blockClozeDescription,
    image => l10n.blockImageDescription,
    audio => l10n.blockAudioDescription,
  };

  IconData get icon => switch (this) {
    text => LucideIcons.type,
    senses => LucideIcons.listOrdered,
    table => LucideIcons.table,
    cloze => LucideIcons.textCursorInput,
    image => LucideIcons.image,
    audio => LucideIcons.audioLines,
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

/// A 음성 block: its sound, once recorded or picked (ADR 0112).
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

/// What a block's menu does.
enum _BlockAction { up, down, delete }

/// One side's [blocks], each under a row naming its type with a menu that
/// moves it up or down or deletes it, a non-drag way to reorder (WCAG 2.2
/// dragging), and under them "+ 앞면에 추가" or "+ 뒷면에 추가", which
/// opens a sheet of the types to add (ADR 0108). With [showErrors], what
/// keeps a block from being saved shows under it. [emptyError], given while
/// the side must hold a block and holds none to save, shows under the side
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

  /// Called with each photo a 사진 block and each sound a 음성 block stores,
  /// so the editor can let go of one the card is not saved with.
  final ValueChanged<MediaId> onMediaStored;

  void _act(int index, _BlockAction action) {
    switch (action) {
      case _BlockAction.up:
        blocks.insert(index - 1, blocks.removeAt(index));
      case _BlockAction.down:
        blocks.insert(index + 1, blocks.removeAt(index));
      case _BlockAction.delete:
        blocks.removeAt(index).dispose();
    }
    onChanged();
  }

  Future<void> _add(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final type = await showAppSheet<BlockType>(
      context,
      builder: (context) {
        final colors = AppColors.of(context);
        return AppSheet(
          title: _addLabel(l10n),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final type in BlockType.values)
                AppListRow(
                  title: type.title(l10n),
                  subtitle: type.description(l10n),
                  onSheet: true,
                  leading: Container(
                    width: AppSize.deckTile,
                    height: AppSize.deckTile,
                    decoration: BoxDecoration(
                      color: colors.brandTint,
                      borderRadius: BorderRadius.circular(AppRadius.field),
                    ),
                    child: Icon(type.icon, color: colors.ink),
                  ),
                  onTap: () => Navigator.of(context).pop(type),
                ),
            ],
          ),
        );
      },
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
      spacing: AppSpace.s16,
      children: [
        for (final (index, block) in blocks.indexed)
          _Block(
            // Keyed by the draft, so a moved block keeps its fields' focus
            // and state.
            key: ObjectKey(block),
            block: block,
            sideName: sideName,
            menuLabel: l10n.blockMenu(sideName, index + 1),
            showErrors: showErrors,
            sideRequired: emptyError != null,
            onChanged: onChanged,
            onMediaStored: onMediaStored,
            onAction: (action) => _act(index, action),
            canMoveUp: index > 0,
            canMoveDown: index < blocks.length - 1,
          ),
        if (emptyError != null && blocks.isEmpty)
          Text(
            emptyError,
            style: AppType.caption.copyWith(color: colors.dontKnowText),
          ),
        AppButton(
          label: _addLabel(l10n),
          icon: LucideIcons.plus,
          variant: AppButtonVariant.secondary,
          onPressed: () => _add(context),
        ),
      ],
    );
  }
}

/// One block: its type and menu on a row, then its fields.
class _Block extends StatelessWidget {
  const _Block({
    super.key,
    required this.block,
    required this.sideName,
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

  /// "앞면" or "뒷면", which a one-meaning 뜻 목록's field is labelled.
  final String sideName;
  final String menuLabel;
  final bool showErrors;

  /// Whether the side must hold a block and holds none to save, so an empty
  /// 글 asks for its text.
  final bool sideRequired;
  final VoidCallback onChanged;
  final ValueChanged<_BlockAction> onAction;
  final bool canMoveUp;
  final bool canMoveDown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final (icon, title) = switch (block) {
      KeptBlockDraft(:final content) => (
        LucideIcons.circleQuestionMark,
        l10n.unsupportedContent(content.type),
      ),
      TextBlockDraft(:final type) ||
      SensesBlockDraft(:final type) ||
      TableBlockDraft(:final type) ||
      ClozeBlockDraft(:final type) ||
      ImageBlockDraft(:final type) ||
      AudioBlockDraft(:final type) => (type.icon, type.title(l10n)),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpace.s8,
      children: [
        Row(
          spacing: AppSpace.s8,
          children: [
            Icon(icon, size: AppSize.smallIcon, color: colors.muted),
            Expanded(
              child: Text(
                title,
                style: AppType.secondary.copyWith(color: colors.muted),
              ),
            ),
            PopupMenuButton<_BlockAction>(
              tooltip: menuLabel,
              icon: Icon(LucideIcons.ellipsis, color: colors.muted),
              onSelected: onAction,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _BlockAction.up,
                  enabled: canMoveUp,
                  child: Text(l10n.moveUp),
                ),
                PopupMenuItem(
                  value: _BlockAction.down,
                  enabled: canMoveDown,
                  child: Text(l10n.moveDown),
                ),
                PopupMenuItem(
                  value: _BlockAction.delete,
                  child: Text(l10n.deleteBlock),
                ),
              ],
            ),
          ],
        ),
        switch (block) {
          final TextBlockDraft draft => AppTextField(
            controller: draft.text,
            focusNode: draft.focus,
            hint: l10n.blockTextDescription,
            minLines: 2,
            maxLines: null,
            errorText: sideRequired && draft.isEmpty
                ? l10n.cardSideRequired
                : null,
            onChanged: (_) => onChanged(),
          ),
          SensesBlockDraft(:final senses) => SenseFields(
            senses: senses,
            meaningLabel: sideName,
            showErrors: showErrors,
            onChanged: onChanged,
          ),
          TableBlockDraft(:final table) => TableFields(
            draft: table,
            showErrors: showErrors,
            onChanged: onChanged,
          ),
          final ClozeBlockDraft draft => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpace.s8,
            children: [
              AppTextField(
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
              ClozeProblemText(
                draft: draft.cloze,
                showError: showErrors && !draft.isComplete,
              ),
            ],
          ),
          ImageBlockDraft(:final image) => ImageBlockFields(
            draft: image,
            showErrors: showErrors,
            onChanged: onChanged,
            onPicked: onMediaStored,
          ),
          AudioBlockDraft(:final audio) => AudioBlockFields(
            draft: audio,
            showErrors: showErrors,
            onChanged: onChanged,
            onStored: onMediaStored,
          ),
          KeptBlockDraft() => const SizedBox.shrink(),
        },
      ],
    );
  }
}
