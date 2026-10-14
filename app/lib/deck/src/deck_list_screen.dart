import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/app_localizations.dart';
import 'card_list_screen.dart';
import 'failure_message.dart';
import 'model.dart';
import 'name_dialog.dart';
import 'providers.dart';

/// Lists decks and creates, renames, and deletes them. A long-press enters a
/// selection mode that studies several decks in one session.
class DeckListScreen extends ConsumerStatefulWidget {
  const DeckListScreen({super.key});

  @override
  ConsumerState<DeckListScreen> createState() => _DeckListScreenState();
}

class _DeckListScreenState extends ConsumerState<DeckListScreen> {
  /// The decks selected, or null outside selection mode.
  Set<DeckId>? _selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final decks = ref.watch(decksProvider);
    // A deck deleted while selected drops out of the selection.
    final selected = switch ((_selected, decks)) {
      (final selected?, AsyncData(:final value)) => {
        for (final deck in value)
          if (selected.contains(deck.id)) deck.id,
      },
      (final selected, _) => selected,
    };
    return Scaffold(
      appBar: selected == null
          ? AppBar(
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
            )
          : _selectionBar(l10n, selected),
      body: switch (decks) {
        AsyncData(:final value) when value.isEmpty => Center(
          child: Text(l10n.noDecks),
        ),
        AsyncData(:final value) => ListView(
          children: [
            ref.watch(todayCardProvider)(
              DeckSelection(value.first.id, value.skip(1).map((d) => d.id)),
            ),
            for (final deck in value)
              _DeckTile(
                deck: deck,
                selected: selected?.contains(deck.id),
                onSelect: () => _toggle(deck.id),
              ),
          ],
        ),
        AsyncError(:final error, :final stackTrace) => Center(
          child: Text(describeProviderError(l10n, error, stackTrace)),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.newDeck,
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
    );
  }

  AppBar _selectionBar(AppLocalizations l10n, Set<DeckId> selected) {
    final study = DeckSelection.of(selected);
    return AppBar(
      leading: IconButton(
        tooltip: l10n.clearSelection,
        icon: const Icon(Icons.close),
        onPressed: () => setState(() => _selected = null),
      ),
      title: Text(l10n.decksSelected(selected.length)),
      actions: [
        TextButton(
          onPressed: study == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ref.read(studyScreenProvider)(study),
                  ),
                ),
          child: Text(l10n.studySelected(selected.length)),
        ),
      ],
    );
  }

  /// Enters selection mode with [deck], or adds or removes it once there.
  void _toggle(DeckId deck) => setState(() {
    final selected = _selected ??= {};
    if (!selected.remove(deck)) selected.add(deck);
  });

  Future<void> _create() async {
    final repository = ref.read(deckRepositoryProvider);
    final name = await showNameDialog(
      context,
      title: AppLocalizations.of(context).newDeck,
    );
    if (name == null || !mounted) return;
    await reportingFailure(context, () => repository.createDeck(name));
  }
}

enum _DeckAction { rename, delete }

class _DeckTile extends ConsumerWidget {
  const _DeckTile({
    required this.deck,
    required this.selected,
    required this.onSelect,
  });

  final Deck deck;

  /// Whether the deck is selected, or null outside selection mode.
  final bool? selected;

  /// Enters selection mode with this deck, or toggles it once there.
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = this.selected;
    if (selected != null) {
      return ListTile(
        selected: selected,
        leading: Icon(
          selected ? Icons.check_circle : Icons.radio_button_unchecked,
        ),
        title: Text(deck.name),
        onTap: onSelect,
        onLongPress: onSelect,
      );
    }
    return ListTile(
      title: Text(deck.name),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => CardListScreen(deck: deck)),
      ),
      onLongPress: onSelect,
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
