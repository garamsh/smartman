import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_button.dart';
import '../../design/bottom_actions.dart';
import '../../design/app_sheet.dart';
import '../../design/app_text_field.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'card_kind.dart';
import 'card_preview.dart';
import 'cloze_form.dart';
import 'content.dart';
import 'deck_repository.dart';
import 'failure_message.dart';
import 'model.dart';
import 'providers.dart';
import 'table_form.dart';
import 'word_form.dart';

/// Adds a card to [deck], or edits [card] when one is given, above a preview
/// of the card as the study screen shows it, in the form of its kind: a text
/// front and back, a word with its senses, a line with blanks, or a table
/// with blanks under its name. A new card starts in the kind the deck's last
/// new card was added in, and a switch at the top changes it; a card being
/// edited keeps its kind (ADR 0083).
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
  /// The front's text; a table card's is its name, the table being the
  /// table form's.
  late final _front = TextEditingController(
    text: plainText([
      ...?widget.card?.front.where((block) => block is! TableContent),
    ]),
  );
  late final _back = TextEditingController(
    text: plainText(widget.card?.back ?? const []),
  );
  final _frontFocus = FocusNode();
  bool _showRequired = false;

  /// The kind the card is written in; a card being edited keeps its own.
  late CardKind _kind = switch (widget.card) {
    final card? => kindOf(card),
    null => rememberedKind(ref.read(deckStorageProvider), widget.deck.id),
  };

  /// The word form's senses: those of the card's back, or one empty sense.
  late final List<SenseDraft> _senses = _draftsOf(widget.card?.back);

  /// A field for each text block of the card's back, by its place there: a
  /// word's extras or a merged back, edited beside its senses (issue #312).
  late final Map<int, TextEditingController> _extras = {
    for (final (index, block) in (widget.card?.back ?? const []).indexed)
      if (block is TextContent) index: TextEditingController(text: block.text),
  };

  /// The cloze form's blanks: the card's own, or none.
  late ClozeDraft _cloze = switch (widget.card?.front
      .whereType<ClozeContent>()
      .firstOrNull) {
    final cloze? => ClozeDraft.of(cloze),
    null => ClozeDraft(),
  };

  /// The table form's table: the card's own, or two empty rows of two cells.
  late TableDraft _table = switch (widget.card?.front
      .whereType<TableContent>()
      .firstOrNull) {
    final table? => TableDraft.of(table),
    null => TableDraft(),
  };

  /// Whether the cloze's line or blanks were changed; until then, an existing
  /// cloze card keeps its own blocks, a blank inside a word included.
  bool _clozeEdited = false;

  bool get _isNew => widget.card == null;

  /// Whether anything was typed or chosen since the editor opened or last
  /// saved; leaving then asks first (issue #309). Switching the kind alone
  /// is no change.
  bool _edited = false;

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
    _front.dispose();
    _back.dispose();
    _frontFocus.dispose();
    for (final sense in _senses) {
      sense.dispose();
    }
    for (final extra in _extras.values) {
      extra.dispose();
    }
    _table.dispose();
    super.dispose();
  }

  /// Whether every field the kind requires is filled.
  bool get _isComplete =>
      _front.text.trim().isNotEmpty &&
      switch (_kind) {
        CardKind.basic => _back.text.trim().isNotEmpty,
        CardKind.word => !_senses.any((sense) => sense.isBlank),
        CardKind.cloze => _cloze.content != null,
        CardKind.table => _table.problem == null,
      };

  /// The card's own front and back while its cloze is left as it was.
  bool get _keepsCloze => widget.card != null && !_clozeEdited;

  /// The front as saved: the text typed, or the card's own blocks while their
  /// text is left as it was.
  List<Content> get _frontBlocks => switch (_kind) {
    CardKind.cloze when _keepsCloze => widget.card!.front,
    // While it has no blank, the line as a cloze without one, so the preview
    // draws it whole as the card will be, not on both halves (issue #313).
    // Such a cloze is never saved: the form refuses it.
    CardKind.cloze => [_cloze.content ?? ClozeContent(_front.text, const [])],
    CardKind.table => [TextContent(_front.text), _table.table],
    _ => _replaceText(widget.card?.front ?? const [], _front.text),
  };

  /// The back's block at [index] as a word saves it beside its senses: a
  /// text block as its field holds it, or none once the field is cleared;
  /// any other block but the senses as it is.
  Content? _besideSenses(int index, Content block) => switch (_extras[index]) {
    final extra? => extra.text.trim().isEmpty ? null : TextContent(extra.text),
    null => block is SensesContent ? null : block,
  };

  /// The back as saved: the text typed, as [_frontBlocks]; or a word's senses,
  /// then any other block the card's back holds, such as its extras.
  List<Content> get _backBlocks => switch (_kind) {
    CardKind.basic => _replaceText(widget.card?.back ?? const [], _back.text),
    CardKind.word => [
      SensesContent([for (final sense in _senses) sense.sense]),
      for (final (index, block) in (widget.card?.back ?? const []).indexed)
        ?_besideSenses(index, block),
    ],
    CardKind.cloze when _keepsCloze => widget.card!.back,
    // The line with its blanks filled, as photo import writes a cloze's back.
    CardKind.cloze => [TextContent(_cloze.content?.filled ?? _front.text)],
    // The name, then the table with every cell shown: the front's text, as
    // photo import writes a table card's back.
    CardKind.table => [TextContent(plainText(_frontBlocks))],
  };

  void _chooseKind(CardKind kind) => setState(() {
    _kind = kind;
    _showRequired = false;
  });

  Future<void> _save(_AfterSave after, {bool allowDuplicate = false}) async {
    if (!_isComplete) {
      setState(() => _showRequired = true);
      return;
    }
    final repository = ref.read(deckRepositoryProvider);
    final storage = ref.read(deckStorageProvider);
    final kind = _kind;
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
      if (!mounted) return;
      switch ((result, after)) {
        case (CardSaved(), _AfterSave.close):
          Navigator.of(context).pop();
        case (CardSaved(), _AfterSave.next):
          setState(() {
            _front.clear();
            _back.clear();
            for (final sense in _senses) {
              sense.dispose();
            }
            _senses
              ..clear()
              ..add(SenseDraft());
            _cloze = ClozeDraft();
            _table.dispose();
            _table = TableDraft();
            _showRequired = false;
            _edited = false;
          });
          _frontFocus.requestFocus();
        case (DuplicateFront(:final existing), _):
          await _resolveDuplicate(existing, after);
      }
      // The deck's next new card opens in the kind of the last one added,
      // not of the last switch tapped (issue #311).
      if (card == null && result is CardSaved) {
        await rememberKind(storage, widget.deck.id, kind);
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

  String? _requiredError(AppLocalizations l10n, TextEditingController side) =>
      _showRequired && side.text.trim().isEmpty ? l10n.cardSideRequired : null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final card = widget.card;
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
          title: Text(_isNew ? l10n.newCard : l10n.editCard),
          actions: [
            if (card != null)
              IconButton(
                tooltip: l10n.deleteCard,
                icon: const Icon(LucideIcons.trash2),
                onPressed: () => _delete(card),
              ),
            const SizedBox(width: AppSpace.s8),
          ],
        ),
        // The actions sit in the body under the form, not in the bottom bar, so
        // they stay above the keyboard, which shrinks the body (issue #307).
        body: Column(
          children: [
            Expanded(
              // A column, not a lazy list, so every field of a long word is built and
              // its error shows wherever it scrolls.
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpace.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The deck, in the form rather than the top bar, where a
                    // long name pushed the title out (issue #310).
                    Semantics(
                      label: l10n.cardDeck(widget.deck.name),
                      excludeSemantics: true,
                      child: Row(
                        spacing: AppSpace.s8,
                        children: [
                          Icon(
                            LucideIcons.layers,
                            size: AppSize.smallIcon,
                            color: AppColors.of(context).muted,
                          ),
                          Expanded(
                            child: Text(
                              widget.deck.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.secondary.copyWith(
                                color: AppColors.of(context).muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpace.s16),
                    if (_isNew) ...[
                      Semantics(
                        label: l10n.cardKindLabel,
                        child: SegmentedButton<CardKind>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: CardKind.basic,
                              label: Text(l10n.cardKindBasic),
                            ),
                            ButtonSegment(
                              value: CardKind.word,
                              label: Text(l10n.cardKindWord),
                            ),
                            ButtonSegment(
                              value: CardKind.cloze,
                              label: Text(l10n.cardKindCloze),
                            ),
                            ButtonSegment(
                              value: CardKind.table,
                              label: Text(l10n.cardKindTable),
                            ),
                          ],
                          selected: {_kind},
                          onSelectionChanged: (kinds) =>
                              _chooseKind(kinds.single),
                        ),
                      ),
                      const SizedBox(height: AppSpace.s24),
                    ],
                    CardPreview(front: _frontBlocks, back: _backBlocks),
                    const SizedBox(height: AppSpace.s24),
                    AppTextField(
                      // A table's front is its name, and says so while typed
                      // (issue #313).
                      label: _kind == CardKind.table
                          ? l10n.tableNameLabel
                          : l10n.cardFront,
                      controller: _front,
                      hint: _kind == CardKind.table ? l10n.tableNameHint : null,
                      focusNode: _frontFocus,
                      autofocus: _isNew,
                      minLines: 2,
                      maxLines: null,
                      errorText: _requiredError(l10n, _front),
                      onChanged: (text) => _change(() {
                        _cloze.update(text);
                        _clozeEdited = true;
                      }),
                    ),
                    if (card?.front.any((block) => block is SensesContent) ??
                        false) ...[
                      const SizedBox(height: AppSpace.s8),
                      Text(
                        l10n.sensesEditNote,
                        style: AppType.secondary.copyWith(
                          color: AppColors.of(context).muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpace.s16),
                    switch (_kind) {
                      CardKind.basic => AppTextField(
                        label: l10n.cardBack,
                        controller: _back,
                        minLines: 2,
                        maxLines: null,
                        errorText: _requiredError(l10n, _back),
                        onChanged: (_) => _change(),
                      ),
                      CardKind.word => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: AppSpace.s16,
                        children: [
                          SenseFields(
                            senses: _senses,
                            showErrors: _showRequired,
                            onChanged: _change,
                          ),
                          for (final extra in _extras.values)
                            AppTextField(
                              label: l10n.wordExtra,
                              controller: extra,
                              minLines: 2,
                              maxLines: null,
                              onChanged: (_) => _change(),
                            ),
                        ],
                      ),
                      CardKind.cloze => ClozeWords(
                        line: _front.text,
                        draft: _cloze,
                        showError: _showRequired,
                        onChanged: () => _change(() => _clozeEdited = true),
                      ),
                      CardKind.table => TableFields(
                        draft: _table,
                        showErrors: _showRequired,
                        onChanged: _change,
                      ),
                    },
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
          ],
        ),
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

/// [blocks] while [text] is still their text, so a side the user left as it
/// was keeps its blocks, a senses block included; otherwise [text] as a text
/// block, with blocks of other types kept. An edited senses front, a reversed
/// word's, so becomes text, its labels as typed.
List<Content> _replaceText(List<Content> blocks, String text) =>
    text == plainText(blocks)
    ? blocks
    : [
        TextContent(text),
        ...blocks.where(
          (block) => block is! TextContent && block is! SensesContent,
        ),
      ];

/// One draft per sense of [back]'s senses block, or one empty draft when it
/// holds none.
List<SenseDraft> _draftsOf(List<Content>? back) {
  final senses = [
    for (final block in back ?? const <Content>[])
      if (block is SensesContent) ...block.senses,
  ];
  return senses.isEmpty
      ? [SenseDraft()]
      : [for (final sense in senses) SenseDraft(sense)];
}
