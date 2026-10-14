import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card_editor_screen.dart';
import 'content.dart';
import 'model.dart';
import 'providers.dart';

/// Lists a deck's cards and opens them for adding, editing, and deleting.
class CardListScreen extends ConsumerWidget {
  const CardListScreen({super.key, required this.deck});

  final Deck deck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(cardsProvider(deck.id));
    return Scaffold(
      appBar: AppBar(title: Text(deck.name)),
      body: switch (cards) {
        AsyncData(:final value) when value.isEmpty => const Center(
          child: Text('No cards yet'),
        ),
        AsyncData(:final value) => ListView(
          children: [
            for (final card in value)
              ListTile(
                title: Text(describeContent(card.front)),
                subtitle: Text(describeContent(card.back)),
                onTap: () => _open(context, card),
                trailing: IconButton(
                  tooltip: 'Delete card',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () =>
                      ref.read(deckRepositoryProvider).deleteCard(card.id),
                ),
              ),
          ],
        ),
        AsyncError(:final error) => Center(child: Text('$error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
      floatingActionButton: FloatingActionButton(
        tooltip: 'New card',
        onPressed: () => _open(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _open(BuildContext context, Card? card) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CardEditorScreen(deck: deck, card: card),
      ),
    );
  }
}

/// One line of text for a card side; a block this version cannot show is
/// named by its type.
String describeContent(List<Content> blocks) => blocks
    .map(
      (block) => switch (block) {
        TextContent(:final text) => text,
        UnsupportedContent(:final type) => '[$type]',
      },
    )
    .join(' ');
