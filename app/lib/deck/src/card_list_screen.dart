import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import 'bottom_actions.dart';
import 'card_editor_screen.dart';
import 'content.dart';
import 'failure_message.dart';
import 'model.dart';
import 'name_dialog.dart';
import 'providers.dart';

/// A deck's cards, searchable, under the action that studies them; opens a
/// card for editing and the deck for renaming or deleting.
class CardListScreen extends ConsumerStatefulWidget {
  const CardListScreen({super.key, required this.deck});

  final Deck deck;

  @override
  ConsumerState<CardListScreen> createState() => _CardListScreenState();
}

enum _DeckAction { rename, delete }

class _CardListScreenState extends ConsumerState<CardListScreen> {
  late String _name = widget.deck.name;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final cards = ref.watch(cardsProvider(widget.deck.id));
    final photoImport = ref.watch(photoImportProvider);
    final deck = DeckSelection(widget.deck.id);
    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<_DeckAction>(
            tooltip: l10n.deckActions,
            onSelected: (action) => switch (action) {
              _DeckAction.rename => _rename(),
              _DeckAction.delete => _delete(),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _DeckAction.rename,
                child: Text(l10n.rename),
              ),
              PopupMenuItem(
                value: _DeckAction.delete,
                child: Text(l10n.deleteDeck),
              ),
            ],
          ),
        ],
      ),
      body: switch (cards) {
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Semantics(
              header: true,
              child: Text(
                _name,
                style: textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            ref.watch(todayProvider)(
              deck,
              (context, count) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  Text(
                    switch (count) {
                      TodayCounted(:final review, :final fresh) =>
                        l10n.deckSummary(value.length, review, fresh),
                      TodayUnavailable(:final message) => message,
                      TodayPending() => l10n.cardCount(value.length),
                    },
                    style: textTheme.bodyMedium?.copyWith(color: colors.muted),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.know,
                      foregroundColor: colors.onKnow,
                    ),
                    onPressed: switch (count) {
                      TodayCounted(:final total) when total > 0 => _study,
                      _ => null,
                    },
                    child: Text(
                      l10n.studyCount(switch (count) {
                        TodayCounted(:final total) => total,
                        _ => 0,
                      }),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (value.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Text(l10n.noCards, textAlign: TextAlign.center),
              )
            else ...[
              TextField(
                onChanged: (query) => setState(() => _query = query),
                decoration: InputDecoration(
                  hintText: l10n.searchCards,
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              ..._rows(l10n, value),
            ],
          ],
        ),
        AsyncError(:final error, :final stackTrace) => Center(
          child: Text(describeProviderError(l10n, error, stackTrace)),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
      bottomNavigationBar: BottomActions(
        secondary: OutlinedButton(
          onPressed: () => _open(null),
          child: Text(l10n.newCard),
        ),
        primary: photoImport == null
            ? null
            : FilledButton(
                onPressed: () => _importPhoto(photoImport),
                child: Text(l10n.addFromPhoto),
              ),
      ),
    );
  }

  /// A row for each card whose front or back holds the search, ignoring case.
  List<Widget> _rows(AppLocalizations l10n, List<Card> cards) {
    final query = _query.trim().toLowerCase();
    final rows =
        [
          for (final card in cards)
            (
              card: card,
              front: describeContent(l10n, card.front),
              back: describeContent(l10n, card.back),
            ),
        ].where(
          (row) =>
              row.front.toLowerCase().contains(query) ||
              row.back.toLowerCase().contains(query),
        );
    if (rows.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text(l10n.noMatches, textAlign: TextAlign.center),
        ),
      ];
    }
    return [
      for (final row in rows)
        _CardRow(
          front: row.front,
          back: row.back,
          onTap: () => _open(row.card),
        ),
    ];
  }

  /// Opens photo import for this deck. When it saved into another deck, that
  /// deck's list replaces this one.
  Future<void> _importPhoto(Widget Function(DeckId? deck) photoImport) async {
    final navigator = Navigator.of(context);
    final deck = await navigator.push(
      MaterialPageRoute<Deck>(builder: (_) => photoImport(widget.deck.id)),
    );
    if (deck == null || deck.id == widget.deck.id || !mounted) return;
    await navigator.pushReplacement(
      MaterialPageRoute<void>(builder: (_) => CardListScreen(deck: deck)),
    );
  }

  void _study() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          ref.read(studyScreenProvider)(DeckSelection(widget.deck.id)),
    ),
  );

  void _open(Card? card) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CardEditorScreen(
        deck: Deck(
          id: widget.deck.id,
          name: _name,
          createdAt: widget.deck.createdAt,
          updatedAt: widget.deck.updatedAt,
        ),
        card: card,
      ),
    ),
  );

  Future<void> _rename() async {
    final repository = ref.read(deckRepositoryProvider);
    final name = await showNameDialog(
      context,
      title: AppLocalizations.of(context).renameDeck,
      initial: _name,
    );
    if (name == null || !mounted) return;
    await reportingFailure(context, () async {
      await repository.renameDeck(widget.deck.id, name);
      if (mounted) setState(() => _name = name);
    });
  }

  Future<void> _delete() async {
    final repository = ref.read(deckRepositoryProvider);
    await reportingFailure(context, () async {
      final cardCount = await repository.countCards(widget.deck.id);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(l10n.deleteDeckTitle(_name)),
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
      if (confirmed != true) return;
      await repository.deleteDeck(widget.deck.id);
      if (mounted) Navigator.of(context).pop();
    });
  }
}

/// A card as two columns, front and back, split by a thin divider.
class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.front,
    required this.back,
    required this.onTap,
  });

  final String front;
  final String back;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.row),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.row),
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(front, style: textTheme.bodyLarge),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      back,
                      style: textTheme.bodyLarge?.copyWith(color: colors.muted),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
