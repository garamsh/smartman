import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/app_localizations.dart';
import 'card_editor_screen.dart';
import 'content.dart';
import 'failure_message.dart';
import 'model.dart';
import 'providers.dart';

/// Lists a deck's cards and opens them for adding, editing, and deleting.
class CardListScreen extends ConsumerWidget {
  const CardListScreen({super.key, required this.deck});

  final Deck deck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cards = ref.watch(cardsProvider(deck.id));
    return Scaffold(
      appBar: AppBar(title: Text(deck.name)),
      body: switch (cards) {
        AsyncData(:final value) when value.isEmpty => Center(
          child: Text(l10n.noCards),
        ),
        AsyncData(:final value) => ListView(
          children: [
            for (final card in value)
              ListTile(
                title: Text(describeContent(l10n, card.front)),
                subtitle: Text(describeContent(l10n, card.back)),
                onTap: () => _open(context, card),
                trailing: IconButton(
                  tooltip: l10n.deleteCard,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => reportingFailure(
                    context,
                    () => ref.read(deckRepositoryProvider).deleteCard(card.id),
                  ),
                ),
              ),
          ],
        ),
        AsyncError(:final error, :final stackTrace) => Center(
          child: Text(describeProviderError(l10n, error, stackTrace)),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.newCard,
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
String describeContent(AppLocalizations l10n, List<Content> blocks) => blocks
    .map(
      (block) => switch (block) {
        TextContent(:final text) => text,
        UnsupportedContent(:final type) => l10n.unsupportedContent(type),
      },
    )
    .join(' ');
