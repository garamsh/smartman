import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_button.dart';
import '../../design/bottom_actions.dart';
import '../../design/app_sheet.dart';
import '../../design/app_text_field.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'card_preview.dart';
import 'content.dart';
import 'deck_repository.dart';
import 'failure_message.dart';
import 'model.dart';
import 'providers.dart';

/// Adds a card to [deck], or edits [card] when one is given, above a preview
/// of the card as the study screen shows it. A table or cloze card is shown
/// read-only, with a note, as it cannot be edited yet (ADR 0068).
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
  late final _front = TextEditingController(
    text: plainText(widget.card?.front ?? const []),
  );
  late final _back = TextEditingController(
    text: plainText(widget.card?.back ?? const []),
  );
  final _frontFocus = FocusNode();
  bool _showRequired = false;

  bool get _isNew => widget.card == null;

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    _frontFocus.dispose();
    super.dispose();
  }

  Future<void> _save(_AfterSave after, {bool allowDuplicate = false}) async {
    if (_front.text.trim().isEmpty || _back.text.trim().isEmpty) {
      setState(() => _showRequired = true);
      return;
    }
    final repository = ref.read(deckRepositoryProvider);
    final card = widget.card;
    final front = _replaceText(card?.front ?? const [], _front.text);
    final back = _replaceText(card?.back ?? const [], _back.text);
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
            _showRequired = false;
          });
          _frontFocus.requestFocus();
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
        await Navigator.of(context).pushReplacement(
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
    // A table or cloze card cannot be edited yet, so it is shown read-only.
    final readOnly = card != null && isWholeCard(card.front);
    return Scaffold(
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
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.gutter),
            child: Text(
              widget.deck.name,
              style: AppType.secondary.copyWith(
                color: AppColors.of(context).muted,
              ),
            ),
          ),
        ],
      ),
      body: readOnly
          ? ListView(
              padding: const EdgeInsets.all(AppSpace.gutter),
              children: [
                CardPreview(front: card.front, back: card.back),
                const SizedBox(height: AppSpace.s24),
                Text(
                  l10n.wholeCardReadOnly,
                  style: AppType.secondary.copyWith(
                    color: AppColors.of(context).muted,
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpace.gutter),
              children: [
                CardPreview(
                  front: _replaceText(card?.front ?? const [], _front.text),
                  back: _replaceText(card?.back ?? const [], _back.text),
                ),
                const SizedBox(height: AppSpace.s24),
                AppTextField(
                  label: l10n.cardFront,
                  controller: _front,
                  focusNode: _frontFocus,
                  autofocus: _isNew,
                  minLines: 2,
                  maxLines: null,
                  errorText: _requiredError(l10n, _front),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpace.s16),
                AppTextField(
                  label: l10n.cardBack,
                  controller: _back,
                  minLines: 2,
                  maxLines: null,
                  errorText: _requiredError(l10n, _back),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
      bottomNavigationBar: readOnly
          ? null
          : _isNew
          ? BottomActions(
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
          : BottomActions(
              secondary: AppButton(
                label: l10n.save,
                size: AppButtonSize.cta,
                onPressed: () => _save(_AfterSave.close),
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

/// [blocks] with its text replaced by [text]; blocks of other types are kept.
List<Content> _replaceText(List<Content> blocks, String text) => [
  TextContent(text),
  ...blocks.where((block) => block is! TextContent),
];
