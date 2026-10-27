import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_button.dart';
import '../../design/app_section_label.dart';
import '../../design/bottom_actions.dart';
import '../../design/app_sheet.dart';
import '../../design/theme.dart';
import '../../design/word_break.dart';
import '../../l10n/app_localizations.dart';
import '../../media/media.dart';
import 'block_list.dart';
import 'card_preview.dart';
import 'card_preview_screen.dart';
import 'card_template.dart';
import 'content.dart';
import 'deck_repository.dart';
import 'failure_message.dart';
import 'label_presets.dart';
import 'label_presets_screen.dart';
import 'model.dart';
import 'providers.dart';
import 'senses_block.dart';

/// Adds a card to [deck], or edits [card] when one is given. Each side is a
/// group of blocks under its name, ending in "+ 추가"; "미리보기" opens the
/// card as study draws it. A new card opens with one empty 글 on each side,
/// and every card, of whichever template it was made in, opens with all its
/// blocks in order (ADR 0108, ADR 0114, ADR 0117).
class CardEditorScreen extends ConsumerStatefulWidget {
  const CardEditorScreen({super.key, required this.deck, this.card});

  final Deck deck;
  final Card? card;

  @override
  ConsumerState<CardEditorScreen> createState() => _CardEditorScreenState();
}

/// What the user chose on the duplicate sheet; dismissing it chooses neither.
enum _DuplicateChoice { saveAnyway, openExisting }

/// Where the editor goes once a card is saved.
enum _AfterSave { close, next }

class _CardEditorScreenState extends ConsumerState<CardEditorScreen> {
  /// The card's blocks on each side, or one empty 글 on each of a new card.
  late final _front = switch (widget.card) {
    final card? => [for (final block in card.front) BlockDraft.of(block)],
    null => <BlockDraft>[TextBlockDraft()],
  };
  late final _back = switch (widget.card) {
    final card? => [for (final block in card.back) BlockDraft.of(block)],
    null => <BlockDraft>[TextBlockDraft()],
  };

  bool _showRequired = false;

  /// Whether the card records a template, or a template version, this build
  /// does not know, so the editor shows it read-only and never writes it
  /// (ADR 0106).
  late final bool _readOnly = switch (widget.card) {
    final card? => !canEdit(card),
    null => false,
  };

  bool get _isNew => widget.card == null;

  /// Whether anything was typed or chosen since the editor opened or last
  /// saved; leaving then asks first (issue #309).
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    // The presets show while a label field has focus, and a 빈칸 문장's
    // action while its line has.
    FocusManager.instance.addListener(_focusChanged);
    if (_isNew) _focusFront();
  }

  void _focusChanged() => setState(() {});

  /// Puts the focus in the front's first block once it is built, where a new
  /// card is typed first, while that block is a 글.
  void _focusFront() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    if (_front.firstOrNull case final TextBlockDraft first) {
      first.focus.requestFocus();
    }
  });

  /// Marks the card changed and redraws.
  void _change([VoidCallback? change]) => setState(() {
    change?.call();
    _edited = true;
  });

  /// Asks before leaving with changes, and leaves once the user discards
  /// them.
  Future<void> _confirmLeave(bool didPop) async {
    if (didPop) return;
    final l10n = AppLocalizations.of(context);
    final discard = await showAppConfirm(
      context,
      title: l10n.discardCardTitle,
      consequence: l10n.discardCardBody,
      confirmLabel: l10n.discardCard,
      cancelLabel: l10n.keepWriting,
    );
    if (discard && mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    for (final block in [..._front, ..._back]) {
      block.dispose();
    }
    // Photos and sounds stored here that no saved card holds, the card left
    // unsaved.
    for (final image in _picked) {
      unawaited(_media?.release(image));
    }
    super.dispose();
  }

  /// The photos 사진 blocks and the sounds 소리 blocks stored since the card
  /// was last saved; those the saved card does not hold are let go
  /// (ADR 0109, ADR 0112).
  final _picked = <MediaId>{};

  /// The store the files went to, read on the first, so an editor that
  /// stores none needs none.
  MediaStore? _media;

  void _mediaStored(MediaId image) {
    _media ??= ref.read(mediaStoreProvider);
    _picked.add(image);
  }

  /// Lets go of the files stored since the last save that [saved] does not
  /// hold.
  Future<void> _releaseUnsaved(Set<MediaId> saved) async {
    for (final image in _picked.difference(saved)) {
      await _media?.release(image);
    }
    _picked.clear();
  }

  /// Whether each side holds what it must, and every block can be saved.
  bool get _isComplete =>
      _sideRequired(CardSide.front) == null &&
      _sideRequired(CardSide.back) == null &&
      [..._saved(_front), ..._saved(_back)].every((block) => block.isComplete);

  /// Why [side] cannot be saved: it holds no block to save, the front always
  /// and the back unless the card is studied on one face; null once it can.
  String? _sideRequired(CardSide side) {
    final l10n = AppLocalizations.of(context);
    return switch (side) {
      CardSide.front when _saved(_front).isEmpty => l10n.sideBlockRequired,
      CardSide.back
          when _saved(_back).isEmpty &&
              oneFaceOf(_frontBlocks, _backBlocks) == null =>
        l10n.sideBlockRequired,
      _ => null,
    };
  }

  /// The blocks of [side] that are saved: all but a 글 left empty, which
  /// is dropped, so a new card's untouched back holds nothing.
  List<BlockDraft> _saved(List<BlockDraft> side) => [
    for (final block in side)
      if (block is! TextBlockDraft || !block.isEmpty) block,
  ];

  /// The front as saved: each block as its type writes it.
  List<Content> get _frontBlocks => [
    for (final block in _saved(_front)) block.content,
  ];

  /// The back as saved: each block as its type writes it.
  List<Content> get _backBlocks => [
    for (final block in _saved(_back)) block.content,
  ];

  Future<void> _save(_AfterSave after, {bool allowDuplicate = false}) async {
    if (!_isComplete) {
      setState(() => _showRequired = true);
      return;
    }
    final repository = ref.read(deckRepositoryProvider);
    final card = widget.card;
    final front = _frontBlocks;
    final back = _backBlocks;
    await reportingFailure(context, () async {
      final result = card == null
          ? await repository.addCard(
              widget.deck.id,
              front: front,
              back: back,
              allowDuplicate: allowDuplicate,
            )
          : await repository.editCard(
              card,
              front: front,
              back: back,
              allowDuplicate: allowDuplicate,
            );
      if (result is CardSaved) {
        await _releaseUnsaved(mediaOf([...front, ...back]));
      }
      if (!mounted) return;
      switch ((result, after)) {
        case (CardSaved(), _AfterSave.close):
          Navigator.of(context).pop();
        case (CardSaved(), _AfterSave.next):
          setState(() {
            for (final side in [_front, _back]) {
              for (final block in side) {
                block.dispose();
              }
              side
                ..clear()
                ..add(TextBlockDraft());
            }
            _showRequired = false;
            _edited = false;
          });
          _focusFront();
        case (DuplicateFront(:final existing), _):
          await _resolveDuplicate(existing, after);
      }
    });
  }

  Future<void> _resolveDuplicate(Card existing, _AfterSave after) async {
    final choice = await showAppSheet<_DuplicateChoice>(
      context,
      builder: (_) => _DuplicateSheet(existing: existing, isNew: _isNew),
    );
    if (!mounted) return;
    switch (choice) {
      case _DuplicateChoice.saveAnyway:
        await _save(after, allowDuplicate: true);
      case _DuplicateChoice.openExisting:
        // Over the editor, so closing it returns to the card being typed.
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CardEditorScreen(deck: widget.deck, card: existing),
          ),
        );
      case null:
        break;
    }
  }

  Future<void> _delete(Card card) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppConfirm(
      context,
      title: l10n.deleteCardTitle,
      consequence: l10n.deleteCardBody,
      confirmLabel: l10n.delete,
    );
    if (!confirmed || !mounted) return;
    final repository = ref.read(deckRepositoryProvider);
    await reportingFailure(context, () async {
      await repository.deleteCard(card.id);
      if (mounted) Navigator.of(context).pop();
    });
  }

  /// The 뜻 목록 sense whose label field has focus.
  SenseDraft? _focusedSense() => [
    for (final block in [..._front, ..._back])
      if (block case SensesBlockDraft(:final senses)) ...senses,
  ].where((sense) => sense.labelFocus.hasFocus).firstOrNull;

  /// The blocks of [side] in its group, ending in "+ 추가".
  Widget _blockList(CardSide side) => BlockList(
    side: side,
    blocks: switch (side) {
      CardSide.front => _front,
      CardSide.back => _back,
    },
    showErrors: _showRequired,
    emptyError: _showRequired ? _sideRequired(side) : null,
    onChanged: _change,
    onMediaStored: _mediaStored,
  );

  /// Each side as study will draw it, empty blanks and incomplete blocks
  /// included.
  List<Content> get _frontPreview => [
    for (final block in _front) block.preview,
  ];
  List<Content> get _backPreview => [for (final block in _back) block.preview];

  /// Whether the back holds nothing to save while the card holds a blank,
  /// so the card is answered on its front and the back may stay empty.
  bool get _backMayStayEmpty =>
      _saved(_back).isEmpty && oneFaceOf(_frontPreview, _backPreview) != null;

  /// Opens the card as study draws it.
  void _openPreview() {
    final front = _frontPreview;
    final back = _backPreview;
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => CardPreviewScreen(front: front, back: back),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final card = widget.card;
    if (card != null && _readOnly) {
      return _ReadOnlyCard(card: card, onDelete: _delete);
    }
    return PopScope(
      canPop: !_edited,
      onPopInvokedWithResult: (didPop, _) => _confirmLeave(didPop),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: l10n.close,
            icon: const Icon(LucideIcons.x),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(_isNew ? l10n.newCardTitle : l10n.editCard),
          actions: [
            AppButton(
              label: l10n.previewCard,
              variant: AppButtonVariant.text,
              onPressed: _openPreview,
            ),
            const SizedBox(width: AppSpace.s8),
          ],
        ),
        // The actions sit in the body under the form, not in the bottom bar, so
        // they stay above the keyboard, which shrinks the body (issue #307).
        body: Column(
          children: [
            Expanded(
              // A column, not a lazy list, so every block is built and its
              // error shows wherever it scrolls.
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpace.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The deck, in the form rather than the top bar, where a
                    // long name pushed the title out (issue #310).
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.s4,
                      ),
                      child: Text(
                        widget.deck.name,
                        semanticsLabel: l10n.cardDeck(widget.deck.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(color: colors.muted),
                      ),
                    ),
                    const SizedBox(height: AppSpace.s20),
                    AppSectionLabel(l10n.cardFront),
                    _blockList(CardSide.front),
                    const SizedBox(height: AppSpace.sectionGap),
                    AppSectionLabel(l10n.cardBack),
                    _blockList(CardSide.back),
                    if (_backMayStayEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.s4,
                          AppSpace.s8,
                          AppSpace.s4,
                          0,
                        ),
                        child: Text(
                          keepWords(l10n.clozeBackHint),
                          semanticsLabel: l10n.clozeBackHint,
                          style: AppType.caption.copyWith(color: colors.muted),
                        ),
                      ),
                    if (card != null) ...[
                      const SizedBox(height: AppSpace.sectionGap),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AppButton(
                          label: l10n.deleteCard,
                          variant: AppButtonVariant.destructive,
                          onPressed: () => _delete(card),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_isNew)
              BottomActions(
                secondary: AppButton(
                  label: l10n.save,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.cta,
                  onPressed: () => _save(_AfterSave.close),
                ),
                primary: AppButton(
                  label: l10n.saveAndNext,
                  size: AppButtonSize.cta,
                  onPressed: () => _save(_AfterSave.next),
                ),
              )
            else
              BottomActions(
                secondary: AppButton(
                  label: l10n.save,
                  size: AppButtonSize.cta,
                  onPressed: () => _save(_AfterSave.close),
                ),
              ),
            // Last, so it sits right above the keyboard.
            if (_focusedSense() case final sense?)
              LabelPresetStrip(
                presets: labelPresets(
                  ref.read(deckStorageProvider),
                  defaultLabelPresets(l10n),
                ),
                current: sense.label.text,
                onPick: (label) => _change(() {
                  sense.label.value = TextEditingValue(
                    text: label,
                    selection: TextSelection.collapsed(offset: label.length),
                  );
                }),
                onManage: () => openPartOfSpeechPresets(context),
              ),
          ],
        ),
      ),
    );
  }
}

/// A card whose template this build does not know: shown as it is, with a
/// line saying the app needs an update to edit it, and nothing to save; it
/// can still be deleted, by the red "카드 삭제" at the end (ADR 0106).
class _ReadOnlyCard extends StatelessWidget {
  const _ReadOnlyCard({required this.card, required this.onDelete});

  final Card card;
  final ValueChanged<Card> onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.close,
          icon: const Icon(LucideIcons.x),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.editCard),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.gutter),
        children: [
          CardPreview(front: card.front, back: card.back),
          const SizedBox(height: AppSpace.s24),
          Text(
            l10n.cardNeedsUpdate,
            style: AppType.body.copyWith(color: AppColors.of(context).ink2),
          ),
          const SizedBox(height: AppSpace.sectionGap),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: l10n.deleteCard,
              variant: AppButtonVariant.destructive,
              onPressed: () => onDelete(card),
            ),
          ),
        ],
      ),
    );
  }
}

/// The sheet shown when a save collides with [existing]: save anyway or open
/// the existing card; dismissing it does neither. Nothing is overwritten.
class _DuplicateSheet extends StatelessWidget {
  const _DuplicateSheet({required this.existing, required this.isNew});

  final Card existing;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.duplicateTitle,
      body: l10n.duplicateBody,
      content: CardPreview(front: existing.front, back: existing.back),
      actions: [
        AppButton(
          label: l10n.openExistingCard,
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.cta,
          onPressed: () =>
              Navigator.of(context).pop(_DuplicateChoice.openExisting),
        ),
        AppButton(
          label: isNew ? l10n.addAnyway : l10n.saveAnyway,
          size: AppButtonSize.cta,
          onPressed: () =>
              Navigator.of(context).pop(_DuplicateChoice.saveAnyway),
        ),
      ],
    );
  }
}
