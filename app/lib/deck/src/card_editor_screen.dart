import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import 'card_list_screen.dart';
import 'card_preview.dart';
import 'content.dart';
import 'deck_repository.dart';
import 'failure_message.dart';
import 'model.dart';
import 'providers.dart';

/// Adds a card to [deck], or edits [card] when one is given, above a preview
/// of the card as the study screen shows it.
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
    final choice = await showModalBottomSheet<_DuplicateChoice>(
      context: context,
      isScrollControlled: true,
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.deleteCardTitle),
          content: Text(l10n.deleteCardBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
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
    final theme = Theme.of(context);
    final card = widget.card;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.close,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(_isNew ? l10n.newCard : l10n.editCard),
        actions: [
          if (card != null)
            IconButton(
              tooltip: l10n.deleteCard,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(card),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              widget.deck.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.of(context).muted,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CardPreview(
            front: describeContent(
              l10n,
              _replaceText(card?.front ?? const [], _front.text),
            ),
            back: describeContent(
              l10n,
              _replaceText(card?.back ?? const [], _back.text),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _front,
            focusNode: _frontFocus,
            autofocus: _isNew,
            minLines: 2,
            maxLines: null,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.cardFront,
              errorText: _requiredError(l10n, _front),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _back,
            minLines: 2,
            maxLines: null,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.cardBack,
              errorText: _requiredError(l10n, _back),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            spacing: 12,
            children: [
              if (_isNew) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _save(_AfterSave.close),
                    child: Text(l10n.save),
                  ),
                ),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _save(_AfterSave.next),
                    child: Text(l10n.saveAndNext),
                  ),
                ),
              ] else
                Expanded(
                  child: FilledButton(
                    onPressed: () => _save(_AfterSave.close),
                    child: Text(l10n.save),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sheet shown when a save collides with [existing]: save anyway, open the
/// existing card, or cancel. Nothing is overwritten either way.
class _DuplicateSheet extends StatelessWidget {
  const _DuplicateSheet({required this.existing, required this.isNew});

  final Card existing;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(l10n.duplicateTitle, style: theme.textTheme.titleLarge),
            Text(
              l10n.duplicateBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.of(context).muted,
              ),
            ),
            const SizedBox(height: 4),
            CardPreview(
              front: describeContent(l10n, existing.front),
              back: describeContent(l10n, existing.back),
            ),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_DuplicateChoice.saveAnyway),
              child: Text(isNew ? l10n.addAnyway : l10n.saveAnyway),
            ),
            OutlinedButton(
              onPressed: () =>
                  Navigator.of(context).pop(_DuplicateChoice.openExisting),
              child: Text(l10n.openExistingCard),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
          ],
        ),
      ),
    );
  }
}

/// [blocks] with its text replaced by [text]; blocks of other types are kept.
List<Content> _replaceText(List<Content> blocks, String text) => [
  TextContent(text),
  ...blocks.where((block) => block is! TextContent),
];
