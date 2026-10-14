import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'content.dart';
import 'deck_repository.dart';
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

  bool get _isNew => widget.card == null;

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    super.dispose();
  }

  Future<void> _save({bool allowDuplicate = false}) async {
    if (_front.text.trim().isEmpty || _back.text.trim().isEmpty) return;
    final repository = ref.read(deckRepositoryProvider);
    final card = widget.card;
    final front = _replaceText(card?.front ?? const [], _front.text);
    final back = _replaceText(card?.back ?? const [], _back.text);
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
  }

  Future<void> _resolveDuplicate(Card existing) async {
    final choice = await showDialog<_DuplicateChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Duplicate front'),
        content: Text(
          'This deck already has a card with this front: '
          '"${plainText(existing.front)}".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_DuplicateChoice.openExisting),
            child: const Text('Open existing card'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_DuplicateChoice.saveAnyway),
            child: Text(_isNew ? 'Add anyway' : 'Save anyway'),
          ),
        ],
      ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'New card' : 'Edit card')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _front,
            autofocus: _isNew,
            maxLines: null,
            decoration: const InputDecoration(labelText: 'Front'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _back,
            maxLines: null,
            decoration: const InputDecoration(labelText: 'Back'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Save card',
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
