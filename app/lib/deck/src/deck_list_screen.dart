import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card_list_screen.dart';
import 'model.dart';
import 'name_dialog.dart';
import 'providers.dart';

/// Lists decks and creates, renames, and deletes them.
class DeckListScreen extends ConsumerWidget {
  const DeckListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(decksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Decks')),
      body: switch (decks) {
        AsyncData(:final value) when value.isEmpty => const Center(
          child: Text('No decks yet'),
        ),
        AsyncData(:final value) => ListView(
          children: [for (final deck in value) _DeckTile(deck: deck)],
        ),
        AsyncError(:final error) => Center(child: Text('$error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
      floatingActionButton: FloatingActionButton(
        tooltip: 'New deck',
        onPressed: () => _create(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await showNameDialog(context, title: 'New deck');
    if (name != null) {
      await ref.read(deckRepositoryProvider).createDeck(name);
    }
  }
}

enum _DeckAction { rename, delete }

class _DeckTile extends ConsumerWidget {
  const _DeckTile({required this.deck});

  final Deck deck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(deck.name),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => CardListScreen(deck: deck)),
      ),
      trailing: PopupMenuButton<_DeckAction>(
        tooltip: 'Deck actions',
        onSelected: (action) => switch (action) {
          _DeckAction.rename => _rename(context, ref),
          _DeckAction.delete => _delete(context, ref),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: _DeckAction.rename, child: Text('Rename')),
          PopupMenuItem(value: _DeckAction.delete, child: Text('Delete')),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await showNameDialog(
      context,
      title: 'Rename deck',
      initial: deck.name,
    );
    if (name != null) {
      await ref.read(deckRepositoryProvider).renameDeck(deck.id, name);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(deckRepositoryProvider);
    final cardCount = await repository.countCards(deck.id);
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${deck.name}"?'),
        content: Text(
          'Its $cardCount ${cardCount == 1 ? 'card' : 'cards'} '
          'will be deleted too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await repository.deleteDeck(deck.id);
    }
  }
}
