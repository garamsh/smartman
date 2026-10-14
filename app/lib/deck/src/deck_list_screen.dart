import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/app_localizations.dart';
import 'card_list_screen.dart';
import 'failure_message.dart';
import 'model.dart';
import 'name_dialog.dart';
import 'providers.dart';

/// Lists decks and creates, renames, and deletes them.
class DeckListScreen extends ConsumerWidget {
  const DeckListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final decks = ref.watch(decksProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.decksTitle),
        actions: [
          IconButton(
            tooltip: l10n.account,
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ref.read(accountScreenProvider)(),
              ),
            ),
          ),
        ],
      ),
      body: switch (decks) {
        AsyncData(:final value) when value.isEmpty => Center(
          child: Text(l10n.noDecks),
        ),
        AsyncData(:final value) => ListView(
          children: [for (final deck in value) _DeckTile(deck: deck)],
        ),
        AsyncError(:final error, :final stackTrace) => Center(
          child: Text(describeProviderError(l10n, error, stackTrace)),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.newDeck,
        onPressed: () => _create(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(deckRepositoryProvider);
    final name = await showNameDialog(
      context,
      title: AppLocalizations.of(context).newDeck,
    );
    if (name == null || !context.mounted) return;
    await reportingFailure(context, () => repository.createDeck(name));
  }
}

enum _DeckAction { rename, delete }

class _DeckTile extends ConsumerWidget {
  const _DeckTile({required this.deck});

  final Deck deck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: Text(deck.name),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => CardListScreen(deck: deck)),
      ),
      trailing: PopupMenuButton<_DeckAction>(
        tooltip: l10n.deckActions,
        onSelected: (action) => switch (action) {
          _DeckAction.rename => _rename(context, ref),
          _DeckAction.delete => _delete(context, ref),
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: _DeckAction.rename, child: Text(l10n.rename)),
          PopupMenuItem(
            value: _DeckAction.delete,
            child: Text(l10n.deleteDeck),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(deckRepositoryProvider);
    final name = await showNameDialog(
      context,
      title: AppLocalizations.of(context).renameDeck,
      initial: deck.name,
    );
    if (name == null || !context.mounted) return;
    await reportingFailure(context, () => repository.renameDeck(deck.id, name));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(deckRepositoryProvider);
    await reportingFailure(context, () async {
      final cardCount = await repository.countCards(deck.id);
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(l10n.deleteDeckTitle(deck.name)),
            content: Text(l10n.deleteDeckBody(cardCount)),
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
      if (confirmed == true) {
        await repository.deleteDeck(deck.id);
      }
    });
  }
}
