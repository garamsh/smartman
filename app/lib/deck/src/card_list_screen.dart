import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import '../../shared/ui/app_button.dart';
import '../../shared/ui/app_chip.dart';
import '../../shared/ui/app_list_row.dart';
import '../../shared/ui/app_sheet.dart';
import '../../shared/ui/app_text_field.dart';
import 'bottom_actions.dart';
import 'card_editor_screen.dart';
import 'content.dart';
import 'failure_message.dart';
import 'model.dart';
import 'name_sheet.dart';
import 'providers.dart';

/// A deck's cards, searchable, under the action that studies them; opens a
/// card for editing and the deck for renaming or deleting.
class CardListScreen extends ConsumerStatefulWidget {
  const CardListScreen({super.key, required this.deck});

  final Deck deck;

  @override
  ConsumerState<CardListScreen> createState() => _CardListScreenState();
}

enum _DeckAction { rename, publish, unpublish, delete }

class _CardListScreenState extends ConsumerState<CardListScreen> {
  late String _name = widget.deck.name;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final cards = ref.watch(cardsProvider(widget.deck.id));
    final photoImport = ref.watch(photoImportProvider);
    final sharing = ref.watch(deckSharingProvider);
    final online = switch (ref.watch(onlineProvider)) {
      AsyncData(:final value) => value,
      _ => false,
    };
    // The deck as stored now, so a publish made here or synced in shows.
    final current = switch (ref.watch(deckProvider(widget.deck.id))) {
      AsyncData(value: final deck?) => deck,
      _ => widget.deck,
    };
    final public = current.visibility is PublicDeck;
    final deck = DeckSelection(widget.deck.id);
    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<_DeckAction>(
            tooltip: l10n.deckActions,
            onSelected: (action) => switch (action) {
              _DeckAction.rename => _rename(),
              _DeckAction.publish => sharing?.publish(context, current),
              _DeckAction.unpublish => sharing?.unpublish(context, current),
              _DeckAction.delete => _delete(),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _DeckAction.rename,
                child: Text(l10n.rename),
              ),
              if (sharing != null)
                PopupMenuItem(
                  value: public ? _DeckAction.unpublish : _DeckAction.publish,
                  enabled: online,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    enabled: online,
                    title: Text(public ? l10n.unpublish : l10n.publish),
                    subtitle: online ? null : Text(l10n.publishNeedsNetwork),
                  ),
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
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            0,
            AppSpace.gutter,
            AppSpace.s16,
          ),
          children: [
            Wrap(
              spacing: AppSpace.s12,
              runSpacing: AppSpace.s4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  header: true,
                  child: Text(_name, style: AppType.title),
                ),
                if (public) AppChip(label: l10n.publicChip),
              ],
            ),
            const SizedBox(height: AppSpace.s4),
            ref.watch(todayProvider)(
              deck,
              (context, count) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpace.s16,
                children: [
                  Text(switch (count) {
                    TodayCounted(:final review, :final fresh) =>
                      l10n.deckSummary(value.length, review, fresh),
                    TodayUnavailable(:final message) => message,
                    TodayPending() => l10n.cardCount(value.length),
                  }, style: AppType.secondary.copyWith(color: colors.muted)),
                  AppButton(
                    label: l10n.studyCount(switch (count) {
                      TodayCounted(:final total) => total,
                      _ => 0,
                    }),
                    variant: AppButtonVariant.primary,
                    onPressed: switch (count) {
                      TodayCounted(:final total) when total > 0 => _study,
                      _ => null,
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.s24),
            if (value.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.s40),
                child: Text(
                  l10n.noCards,
                  textAlign: TextAlign.center,
                  style: AppType.body.copyWith(color: colors.muted),
                ),
              )
            else ...[
              AppTextField(
                hint: l10n.searchCards,
                prefixIcon: const Icon(Icons.search),
                onChanged: (query) => setState(() => _query = query),
              ),
              const SizedBox(height: AppSpace.s12),
              ..._rows(l10n, value),
            ],
          ],
        ),
        AsyncError(:final error, :final stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.gutter),
            child: Text(describeProviderError(l10n, error, stackTrace)),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
      bottomNavigationBar: BottomActions(
        secondary: AppButton(
          label: l10n.newCard,
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.cta,
          onPressed: () => _open(null),
        ),
        primary: photoImport == null
            ? null
            : AppButton(
                label: l10n.addFromPhoto,
                size: AppButtonSize.cta,
                onPressed: () => _importPhoto(photoImport),
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
          padding: const EdgeInsets.symmetric(vertical: AppSpace.s32),
          child: Text(
            l10n.noMatches,
            textAlign: TextAlign.center,
            style: AppType.body.copyWith(color: AppColors.of(context).muted),
          ),
        ),
      ];
    }
    return [
      for (final row in rows)
        CardSplitRow(
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
    final l10n = AppLocalizations.of(context);
    final name = await showNameSheet(
      context,
      title: l10n.renameDeck,
      action: l10n.save,
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
      final l10n = AppLocalizations.of(context);
      final confirmed = await showAppConfirm(
        context,
        title: l10n.deleteDeckTitle(_name),
        consequence: l10n.deleteDeckBody(cardCount),
        confirmLabel: l10n.delete,
      );
      if (!confirmed) return;
      await repository.deleteDeck(widget.deck.id);
      if (mounted) Navigator.of(context).pop();
    });
  }
}

/// A card as two columns, front and back, split by a thin divider; read-only
/// without [onTap].
class CardSplitRow extends StatelessWidget {
  const CardSplitRow({
    super.key,
    required this.front,
    required this.back,
    this.onTap,
  });

  final String front;
  final String back;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AppRowSurface(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.s16),
                child: Text(front, style: AppType.body),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.s16),
                child: Text(
                  back,
                  style: AppType.body.copyWith(color: colors.muted),
                ),
              ),
            ),
          ],
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
