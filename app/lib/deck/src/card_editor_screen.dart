import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_button.dart';
import '../../design/app_section_label.dart';
import '../../design/bottom_actions.dart';
import '../../design/app_sheet.dart';
import '../../design/app_text_field.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'block_list.dart';
import 'card_kind.dart';
import 'card_preview.dart';
import 'cloze_form.dart';
import 'content.dart';
import 'deck_repository.dart';
import 'failure_message.dart';
import 'label_presets.dart';
import 'label_presets_screen.dart';
import 'model.dart';
import 'providers.dart';
import 'table_form.dart';
import 'word_form.dart';

/// Adds a card to [deck], or edits [card] when one is given, above a preview
/// of the card as the study screen shows it, in the form of its kind: a text
/// front and a back of one meaning or of senses, a line with blanks, or a
/// table with blanks under its name, or, in 자유, each side a list of blocks.
/// Under every kind's form, each side lists the blocks added to it, with
/// "+ 앞면에 추가" and "+ 뒷면에 추가" (ADR 0108). A new card starts in the
/// kind the deck's last new card was added in, and a switch at the top
/// changes it; a card being edited keeps its kind (ADR 0083, ADR 0100).
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

/// The blocks a block list edits on each side.
typedef _Sides = ({List<BlockDraft> front, List<BlockDraft> back});

/// The kind [card] opens in: its own, or basic for one this build cannot
/// edit, which opens read-only.
CardKind _openingKind(Card card) => kindOf(card) ?? CardKind.basic;

class _CardEditorScreenState extends ConsumerState<CardEditorScreen> {
  /// The front's text; a table card's is its name, the table being the
  /// table form's. A cloze's blanks are drawn in it as blocks.
  late final ClozeLineController _front = ClozeLineController(
    text: plainText([..._storedFront.where((block) => block is! TableContent)]),
    blanks: () => _kind == CardKind.cloze && _cloze.line == _front.text
        ? _cloze.blanks
        : const [],
  );
  final _frontFocus = FocusNode();
  bool _showRequired = false;

  /// The kind the card is written in; a card being edited keeps its own.
  late CardKind _kind = switch (widget.card) {
    final card? => _openingKind(card),
    null => rememberedKind(ref.read(deckStorageProvider), widget.deck.id),
  };

  /// The card's leading blocks of each side its kind's form edits; the rest
  /// are listed under the form, as blocks added to it are (ADR 0108).
  late final List<Content> _storedFront = switch (widget.card) {
    final card? => card.front.take(_formLength(card, CardSide.front)).toList(),
    null => const [],
  };
  late final List<Content> _storedBack = switch (widget.card) {
    final card? => card.back.take(_formLength(card, CardSide.back)).toList(),
    null => const [],
  };

  /// The blocks listed under the form of a kind other than 자유: those of
  /// the card past what its form edits, and those added since.
  late final _Sides _added = switch (widget.card) {
    final card? when _openingKind(card) != CardKind.free => _listedOf(card),
    _ => (front: [], back: []),
  };

  /// A 자유 card's sides: the card's own, or one empty 글 on each side.
  late final _Sides _free = switch (widget.card) {
    final card? when _openingKind(card) == CardKind.free => _listedOf(card),
    _ => (front: [TextBlockDraft()], back: [TextBlockDraft()]),
  };

  /// The block lists the editor shows for its kind.
  _Sides get _lists => _kind == CardKind.free ? _free : _added;

  /// Whether the card records a template this build does not know, so the
  /// editor shows it read-only and never writes it (ADR 0106).
  late final bool _readOnly = switch (widget.card) {
    final card? => kindOf(card) == null,
    null => false,
  };

  /// Whether the card's back held senses when the editor opened, so it is
  /// saved as senses whatever they become.
  late final bool _backHadSenses = _storedBack.any(
    (block) => block is SensesContent,
  );

  /// The back's senses: those of the card's back, or one sense of its text,
  /// which a plain back is.
  late final List<SenseDraft> _senses = _draftsOf(_storedBack);

  /// A field for each text block of a back of senses, by its place there: a
  /// word's extras or a merged back, edited beside its senses (issue #312).
  late final Map<int, TextEditingController> _extras = {
    if (_backHadSenses)
      for (final (index, block) in _storedBack.indexed)
        if (block is TextContent)
          index: TextEditingController(text: block.text),
  };

  /// The cloze form's blanks: the card's own, or none.
  late ClozeDraft _cloze = switch (_storedFront
      .whereType<ClozeContent>()
      .firstOrNull) {
    final cloze? => ClozeDraft.of(cloze),
    null => ClozeDraft(),
  };

  /// The table form's table: the card's own, or two empty rows of two cells.
  late TableDraft _table = switch (_storedFront
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

  @override
  void initState() {
    super.initState();
    // The presets show while a label field has focus.
    FocusManager.instance.addListener(_focusChanged);
    _front.addListener(_lineChanged);
  }

  void _focusChanged() => setState(() {});

  /// Keeps the cloze's blanks on the line as it is typed, and ends the blank
  /// "빈칸 넣기" opened once the cursor leaves it.
  void _lineChanged() => setState(() {
    _cloze
      ..update(_front.text)
      ..track(_front.selection);
  });

  /// "빈칸 넣기": the selected characters, or an empty blank at the cursor.
  void _insertBlank() => _change(() {
    _cloze.insert(_front.selection);
    _clozeEdited = true;
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
    _front
      ..removeListener(_lineChanged)
      ..dispose();
    _frontFocus.dispose();
    for (final sense in _senses) {
      sense.dispose();
    }
    for (final extra in _extras.values) {
      extra.dispose();
    }
    _table.dispose();
    for (final block in [
      ..._added.front,
      ..._added.back,
      ..._free.front,
      ..._free.back,
    ]) {
      block.dispose();
    }
    super.dispose();
  }

  /// Whether every field the kind requires is filled, and every listed block
  /// can be saved.
  bool get _isComplete =>
      switch (_kind) {
        CardKind.basic =>
          _front.text.trim().isNotEmpty &&
              !_senses.any((sense) => sense.isBlank),
        CardKind.cloze =>
          _front.text.trim().isNotEmpty && _cloze.content != null,
        CardKind.table =>
          _front.text.trim().isNotEmpty && _table.problem == null,
        CardKind.free =>
          _sideRequired(CardSide.front) == null &&
              _sideRequired(CardSide.back) == null,
      } &&
      [..._lists.front, ..._lists.back].every((block) => block.isComplete);

  /// Why a 자유 card's [side] cannot be saved: it holds no block, the front
  /// always and the back unless the card is studied on one face; null once
  /// it can.
  String? _sideRequired(CardSide side) {
    final l10n = AppLocalizations.of(context);
    return switch (side) {
      CardSide.front when _free.front.isEmpty => l10n.sideBlockRequired,
      CardSide.back
          when _free.back.isEmpty &&
              oneFaceOf(_frontBlocks, _backBlocks) == null =>
        l10n.sideBlockRequired,
      _ => null,
    };
  }

  /// The card's own front and back while its cloze is left as it was.
  bool get _keepsCloze => widget.card != null && !_clozeEdited;

  /// The card's own back while its name and table are saved as they were,
  /// whatever shape that back has, such as a copy's or the table alone.
  bool get _keepsTable =>
      widget.card != null && listEquals(_formFront, _storedFront);

  /// The front as saved: what the form makes of it, then its listed blocks.
  List<Content> get _frontBlocks => [
    ..._formFront,
    for (final block in _lists.front) block.content,
  ];

  /// The back as saved: what the form makes of it, then its listed blocks.
  List<Content> get _backBlocks => [
    ..._formBack,
    for (final block in _lists.back) block.content,
  ];

  /// The front as the form saves it: the text typed, or the card's own blocks
  /// while their text is left as it was; nothing in 자유.
  List<Content> get _formFront => switch (_kind) {
    CardKind.free => const [],
    CardKind.cloze when _keepsCloze => _storedFront,
    // While it cannot be saved, the line as the preview draws it, whole as
    // the card will be, not on both halves (issue #313); the form refuses
    // the save.
    CardKind.cloze => [_cloze.content ?? _cloze.preview],
    CardKind.table => [TextContent(_front.text), _table.table],
    CardKind.basic => _replaceText(_storedFront, _front.text),
  };

  /// Whether the back is saved as its one meaning's text: a back that held
  /// no senses, still of one sense with no label and no example.
  bool get _savesText =>
      !_backHadSenses && _senses.length == 1 && _senses.single.isPlain;

  /// The front as the preview draws it: as saved, but a cloze's every blank
  /// in place, an empty one included (ADR 0101), and each listed block as it
  /// is so far.
  List<Content> get _previewFront => [
    ...(_kind == CardKind.cloze && !_keepsCloze
        ? [_cloze.preview]
        : _formFront),
    for (final block in _lists.front) block.preview,
  ];

  /// The back as the preview draws it: each listed block as it is so far.
  List<Content> get _previewBack => [
    ..._formBack,
    for (final block in _lists.back) block.preview,
  ];

  /// The back's block at [index] as a back of senses saves it beside them: a
  /// text block as its field holds it, or none once the field is cleared or
  /// when the back held no senses, its text being the first meaning; any
  /// other block but the senses as it is.
  Content? _besideSenses(int index, Content block) => switch (_extras[index]) {
    final extra? => extra.text.trim().isEmpty ? null : TextContent(extra.text),
    null => block is SensesContent || block is TextContent ? null : block,
  };

  /// The back as the form saves it: its one meaning's text, as [_formFront];
  /// or its senses, then any other block the card's back holds, such as its
  /// extras; nothing in 자유.
  List<Content> get _formBack => switch (_kind) {
    CardKind.free => const [],
    CardKind.basic when _savesText => _replaceText(
      _storedBack,
      _senses.single.meaning.text,
    ),
    CardKind.basic => [
      SensesContent([for (final sense in _senses) sense.sense]),
      for (final (index, block) in _storedBack.indexed)
        ?_besideSenses(index, block),
    ],
    CardKind.cloze when _keepsCloze => _storedBack,
    // The line with its blanks filled, as photo import writes a cloze's back.
    CardKind.cloze => [TextContent(_cloze.content?.filled ?? _front.text)],
    CardKind.table when _keepsTable => _storedBack,
    // The name, then the table with every cell shown: the front's text, as
    // photo import writes a table card's back.
    CardKind.table => [TextContent(plainText(_formFront))],
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
              kind: kind,
              allowDuplicate: allowDuplicate,
            )
          : await repository.editCard(
              card,
              front: front,
              back: back,
              kind: kind,
              allowDuplicate: allowDuplicate,
            );
      if (!mounted) return;
      switch ((result, after)) {
        case (CardSaved(), _AfterSave.close):
          Navigator.of(context).pop();
        case (CardSaved(), _AfterSave.next):
          setState(() {
            _front.clear();
            for (final sense in _senses) {
              sense.dispose();
            }
            _senses
              ..clear()
              ..add(SenseDraft());
            _cloze = ClozeDraft();
            _table.dispose();
            _table = TableDraft();
            for (final side in [
              _added.front,
              _added.back,
              _free.front,
              _free.back,
            ]) {
              for (final block in side) {
                block.dispose();
              }
              side.clear();
            }
            _free.front.add(TextBlockDraft());
            _free.back.add(TextBlockDraft());
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

  /// The sense whose label field has focus: the basic form's, while it
  /// shows, or a listed 뜻 목록's.
  SenseDraft? _focusedSense() => [
    if (_kind == CardKind.basic) ..._senses,
    for (final block in [..._lists.front, ..._lists.back])
      if (block case SensesBlockDraft(:final senses)) ...senses,
  ].where((sense) => sense.labelFocus.hasFocus).firstOrNull;

  /// The listed 빈칸 문장 whose line has focus.
  ClozeBlockDraft? _focusedCloze() => [..._lists.front, ..._lists.back]
      .whereType<ClozeBlockDraft>()
      .where((block) => block.focus.hasFocus)
      .firstOrNull;

  /// The listed blocks of [side], with "+ 앞면에 추가" or "+ 뒷면에 추가".
  Widget _blockList(CardSide side) => BlockList(
    side: side,
    blocks: switch (side) {
      CardSide.front => _lists.front,
      CardSide.back => _lists.back,
    },
    showErrors: _showRequired,
    emptyError: _kind == CardKind.free && _showRequired
        ? _sideRequired(side)
        : null,
    onChanged: _change,
  );

  String? _requiredError(AppLocalizations l10n, TextEditingController side) =>
      _showRequired && side.text.trim().isEmpty ? l10n.cardSideRequired : null;

  /// The card as study will draw it: on one face when it holds a blank
  /// anywhere, the face [oneFaceOf] gives, and front then back otherwise.
  Widget _preview() {
    final front = _previewFront;
    final back = _previewBack;
    final face = oneFaceOf(front, back);
    return CardPreview(
      front: face ?? front,
      back: face == null ? back : const [],
    );
  }

  /// The form of a kind other than 자유: the basic back's senses and extras,
  /// what keeps a cloze from being saved, or a table's grid.
  Widget _form(AppLocalizations l10n) => switch (_kind) {
    CardKind.basic => Column(
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
    CardKind.cloze => ClozeProblemText(draft: _cloze, showError: _showRequired),
    CardKind.table => TableFields(
      draft: _table,
      showErrors: _showRequired,
      onChanged: _change,
    ),
    CardKind.free => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                              label: Text(l10n.cardKindFlip),
                            ),
                            ButtonSegment(
                              value: CardKind.cloze,
                              label: Text(l10n.cardKindCloze),
                            ),
                            ButtonSegment(
                              value: CardKind.table,
                              label: Text(l10n.cardKindTable),
                            ),
                            ButtonSegment(
                              value: CardKind.free,
                              label: Text(l10n.cardKindFree),
                            ),
                          ],
                          selected: {_kind},
                          onSelectionChanged: (kinds) =>
                              _chooseKind(kinds.single),
                        ),
                      ),
                      const SizedBox(height: AppSpace.s24),
                    ],
                    _preview(),
                    const SizedBox(height: AppSpace.s24),
                    if (_kind == CardKind.free) ...[
                      AppSectionLabel(l10n.cardFront),
                      _blockList(CardSide.front),
                      const SizedBox(height: AppSpace.s24),
                      AppSectionLabel(l10n.cardBack),
                      _blockList(CardSide.back),
                    ] else ...[
                      AppTextField(
                        // A table's front is its name, and says so while
                        // typed (issue #313).
                        label: _kind == CardKind.table
                            ? l10n.tableNameLabel
                            : l10n.cardFront,
                        controller: _front,
                        hint: _kind == CardKind.table
                            ? l10n.tableNameHint
                            : null,
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
                      if (_storedFront.any(
                        (block) => block is SensesContent,
                      )) ...[
                        const SizedBox(height: AppSpace.s8),
                        Text(
                          l10n.sensesEditNote,
                          style: AppType.secondary.copyWith(
                            color: AppColors.of(context).muted,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpace.s16),
                      // The basic form is the back, so the front's blocks
                      // come before it; a cloze's and a table's form is the
                      // front's own.
                      if (_kind != CardKind.basic) ...[
                        _form(l10n),
                        const SizedBox(height: AppSpace.s16),
                      ],
                      _blockList(CardSide.front),
                      const SizedBox(height: AppSpace.s16),
                      if (_kind == CardKind.basic) ...[
                        _form(l10n),
                        const SizedBox(height: AppSpace.s16),
                      ],
                      _blockList(CardSide.back),
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
            if (_focusedCloze() case final block?)
              ListenableBuilder(
                listenable: block.line,
                builder: (context, _) => ClozeToolbar(
                  draft: block.cloze,
                  blank: block.cloze.blankAt(block.line.selection),
                  onInsert: () => _change(() {
                    block.cloze.insert(block.line.selection);
                    block.edited = true;
                  }),
                  onUndo: (blank) => _change(() {
                    block.cloze.remove(blank);
                    block.edited = true;
                  }),
                ),
              )
            else if (_kind == CardKind.cloze)
              ClozeToolbar(
                draft: _cloze,
                blank: _cloze.blankAt(_front.selection),
                onInsert: _insertBlank,
                onUndo: (blank) => _change(() {
                  _cloze.remove(blank);
                  _clozeEdited = true;
                }),
              ),
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
/// can still be deleted (ADR 0106).
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
        actions: [
          IconButton(
            tooltip: l10n.deleteCard,
            icon: const Icon(LucideIcons.trash2),
            onPressed: () => onDelete(card),
          ),
          const SizedBox(width: AppSpace.s8),
        ],
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

/// How many of [card]'s leading blocks on [side] the form of the kind it
/// opens in edits: none in 자유; on the front, a basic card's first text or
/// senses block, and a cloze's or a table's blocks up to its first cloze or
/// table; on the back, a basic card's first text block, or its first senses
/// block and the text blocks and unreadable blocks right after it, which
/// the form keeps beside the senses, and a cloze's or a table's
/// first text block. Each kind writes its sides in that shape, so a card
/// opens in its form as it did before blocks could be added, and every
/// block after them is listed (ADR 0108).
int _formLength(Card card, CardSide side) {
  final blocks = switch (side) {
    CardSide.front => card.front,
    CardSide.back => card.back,
  };
  final first = blocks.firstOrNull;
  return switch ((_openingKind(card), side, first)) {
    (CardKind.free, _, _) => 0,
    (CardKind.basic, CardSide.front, TextContent() || SensesContent()) => 1,
    (CardKind.cloze, CardSide.front, _) =>
      blocks.indexWhere((block) => block is ClozeContent) + 1,
    (CardKind.table, CardSide.front, _) =>
      blocks.indexWhere((block) => block is TableContent) + 1,
    (CardKind.basic, CardSide.back, SensesContent()) =>
      1 +
          blocks
              .skip(1)
              .takeWhile(
                (block) => block is TextContent || block is UnsupportedContent,
              )
              .length,
    (_, CardSide.back, TextContent()) => 1,
    _ => 0,
  };
}

/// One draft for each of [card]'s blocks past what its form edits.
_Sides _listedOf(Card card) => (
  front: [
    for (final block in card.front.skip(_formLength(card, CardSide.front)))
      BlockDraft.of(block),
  ],
  back: [
    for (final block in card.back.skip(_formLength(card, CardSide.back)))
      BlockDraft.of(block),
  ],
);

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

/// One draft per sense of [back]'s senses block, or, when it holds none, one
/// draft whose meaning is [back]'s text.
List<SenseDraft> _draftsOf(List<Content>? back) {
  final senses = [
    for (final block in back ?? const <Content>[])
      if (block is SensesContent) ...block.senses,
  ];
  return senses.isEmpty
      ? [SenseDraft(CardSense(meaning: plainText(back ?? const [])))]
      : [for (final sense in senses) SenseDraft(sense)];
}
