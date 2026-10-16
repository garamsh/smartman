import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../deck/deck.dart';
import '../../design/app_button.dart';
import '../../design/app_sheet.dart';
import '../../design/app_text_field.dart';
import '../../design/bottom_actions.dart';
import '../../design/theme.dart';
import 'hero.dart';
import 'option_sheet.dart';
import 'progress_bar.dart';
import '../../l10n/app_localizations.dart';
import '../../photo_import/photo_import.dart';
import '../../sharing/sharing.dart';
import '../../study/study.dart';

/// A deck's page: its tile, name and card count, the navy card that studies
/// it, and its cards, each answer hidden until tapped, searchable from the
/// top bar; adds a card, opens one for editing, and the deck for renaming or
/// deleting.
class DeckScreen extends ConsumerStatefulWidget {
  const DeckScreen({super.key, required this.deck});

  final Deck deck;

  @override
  ConsumerState<DeckScreen> createState() => _DeckScreenState();
}

enum _DeckAction { rename, publish, unpublish, delete }

class _DeckScreenState extends ConsumerState<DeckScreen> {
  late String _name = widget.deck.name;

  /// The card search, or null while it is closed.
  String? _query;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final cards = ref.watch(cardsProvider(widget.deck.id));
    final photoImport = ref.watch(photoImportProvider);
    final sharing = ref.watch(sharingServiceProvider);
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
    final query = _query;
    return Scaffold(
      appBar: AppBar(
        title: query == null
            ? null
            : AppTextField(
                hint: l10n.searchCards,
                prefixIcon: const Icon(LucideIcons.search),
                height: AppSize.search,
                autofocus: true,
                onChanged: (query) => setState(() => _query = query),
              ),
        actions: [
          if (query == null)
            IconButton(
              tooltip: l10n.searchCardsAction,
              icon: const Icon(LucideIcons.search),
              onPressed: () => setState(() => _query = ''),
            )
          else
            IconButton(
              tooltip: l10n.closeSearch,
              icon: const Icon(LucideIcons.x),
              onPressed: () => setState(() => _query = null),
            ),
          PopupMenuButton<_DeckAction>(
            tooltip: l10n.deckActions,
            icon: const Icon(LucideIcons.ellipsisVertical),
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
            Row(
              spacing: AppSpace.s12,
              children: [
                DeckTile(deck: current),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(_name, style: AppType.title),
                      ),
                      Text(
                        public
                            ? l10n.deckSummaryPublic(value.length)
                            : l10n.deckSummary(value.length),
                        style: AppType.secondary.copyWith(color: colors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s16),
            _DeckTodayCard(deck: widget.deck.id, onStudy: _study),
            const SizedBox(height: AppSpace.s12),
            if (value.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.s40),
                child: Text(
                  l10n.noCards,
                  textAlign: TextAlign.center,
                  style: AppType.body.copyWith(color: colors.muted),
                ),
              )
            else
              ..._rows(l10n, value),
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
          icon: LucideIcons.plus,
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.cta,
          onPressed: photoImport == null
              ? () => _open(null)
              : () => _addCard(photoImport),
        ),
      ),
    );
  }

  /// A row for each card whose front or back holds the search, ignoring case,
  /// its answer hidden until tapped.
  List<Widget> _rows(AppLocalizations l10n, List<Card> cards) {
    final query = (_query ?? '').trim().toLowerCase();
    final rows = [
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
        CardAnswerRow(
          key: ValueKey(row.card.id),
          front: row.front,
          back: row.back,
          onEdit: () => _open(row.card),
        ),
    ];
  }

  /// Offers the two ways to add a card: typing it in, or from a photo.
  Future<void> _addCard(Widget Function(DeckId? deck) photoImport) async {
    final l10n = AppLocalizations.of(context);
    final photo = await showOptionSheet(
      context,
      title: l10n.newCard,
      options: [
        (
          icon: LucideIcons.pencilLine,
          title: l10n.addCardManually,
          body: l10n.addCardManuallyBody,
          value: false,
        ),
        (
          icon: LucideIcons.camera,
          title: l10n.addCardPhoto,
          body: l10n.addCardPhotoBody,
          value: true,
        ),
      ],
    );
    if (!mounted) return;
    switch (photo) {
      case false:
        await _open(null);
      case true:
        await _importPhoto(photoImport);
      case null:
        return;
    }
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
      MaterialPageRoute<void>(builder: (_) => DeckScreen(deck: deck)),
    );
  }

  void _study() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => StudyScreen(decks: DeckSelection(widget.deck.id)),
    ),
  );

  Future<void> _open(Card? card) => Navigator.of(context).push(
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

/// The deck's navy card: today's count and its minutes, how many cards are
/// mastered, the progress bar, and the button that studies the deck.
class _DeckTodayCard extends StatelessWidget {
  const _DeckTodayCard({required this.deck, required this.onStudy});

  final DeckId deck;
  final VoidCallback onStudy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final quiet = AppType.secondary.copyWith(color: heroQuiet(colors));
    return Semantics(
      container: true,
      label: l10n.todayThisDeck,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.hero,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpace.s12,
            children: [
              TodayCounter(
                decks: DeckSelection(deck),
                builder: (context, count) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpace.s4,
                  children: [
                    Text(l10n.todayTitle, style: quiet),
                    switch (count) {
                      TodayCounted(:final total, :final minutes) => HeroCount(
                        count: total,
                        unit: l10n.todayCountMinutes(minutes),
                        semantics: l10n.todayCards(total),
                      ),
                      TodayUnavailable(:final message) => Text(
                        message,
                        style: quiet,
                      ),
                      TodayPending() => const SizedBox(
                        height: AppSpace.s40,
                      ),
                    },
                    if (count case TodayCounted(backlog: true))
                      Text(l10n.backlogPaused, style: quiet),
                  ],
                ),
              ),
              ProgressCounter(
                decks: DeckSelection(deck),
                builder: (context, progress) => progress == null
                    ? const SizedBox(height: AppSpace.s28)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: AppSpace.s8,
                        children: [
                          Text(
                            l10n.masteredOf(progress.mastered, progress.total),
                            style: quiet,
                          ),
                          ProgressBar(
                            progress: progress,
                            height: AppSpace.s8,
                            ink: colors.onHero,
                            track: heroTrack(colors),
                          ),
                        ],
                      ),
              ),
              AppButton(
                label: l10n.studyDeck,
                icon: LucideIcons.play,
                variant: AppButtonVariant.onHero,
                onPressed: onStudy,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
