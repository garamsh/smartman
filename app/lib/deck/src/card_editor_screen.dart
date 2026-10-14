import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/app_localizations.dart';
import 'content.dart';
import 'deck_repository.dart';
import 'failure_message.dart';
import 'model.dart';
import 'providers.dart';

/// Adds a card to [deck], or edits [card] when one is given.
class CardEditorScreen extends ConsumerStatefulWidget {
  const CardEditorScreen({super.key, required this.deck, this.card});

  final Deck deck;
  final Card? card;

  @override
  ConsumerState<CardEditorScreen> createState() => _CardEditorScreenState();
}

enum _DuplicateChoice { openExisting, saveAnyway }

class _CardEditorScreenState extends ConsumerState<CardEditorScreen> {
  late final _front = TextEditingController(
    text: plainText(widget.card?.front ?? const []),
  );
  late final _back = TextEditingController(
    text: plainText(widget.card?.back ?? const []),
  );
  bool _showRequired = false;

  bool get _isNew => widget.card == null;

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    super.dispose();
  }

  Future<void> _save({bool allowDuplicate = false}) async {
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
      switch (result) {
        case CardSaved():
          Navigator.of(context).pop();
        case DuplicateFront(:final existing):
          await _resolveDuplicate(existing);
      }
    });
  }

  Future<void> _resolveDuplicate(Card existing) async {
    final choice = await showDialog<_DuplicateChoice>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.duplicateTitle),
          content: Text(l10n.duplicateBody(plainText(existing.front))),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_DuplicateChoice.openExisting),
              child: Text(l10n.openExistingCard),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_DuplicateChoice.saveAnyway),
              child: Text(_isNew ? l10n.addAnyway : l10n.saveAnyway),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    switch (choice) {
      case _DuplicateChoice.openExisting:
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => CardEditorScreen(deck: widget.deck, card: existing),
          ),
        );
      case _DuplicateChoice.saveAnyway:
        await _save(allowDuplicate: true);
      case null:
        break;
    }
  }

  String? _requiredError(AppLocalizations l10n, TextEditingController side) =>
      _showRequired && side.text.trim().isEmpty ? l10n.cardSideRequired : null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? l10n.newCard : l10n.editCard)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _front,
            autofocus: _isNew,
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
            maxLines: null,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.cardBack,
              errorText: _requiredError(l10n, _back),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.saveCard,
        onPressed: _save,
        child: const Icon(Icons.check),
      ),
    );
  }
}

/// [blocks] with its text replaced by [text]; blocks of other types are kept.
List<Content> _replaceText(List<Content> blocks, String text) => [
  TextContent(text),
  ...blocks.where((block) => block is! TextContent),
];
