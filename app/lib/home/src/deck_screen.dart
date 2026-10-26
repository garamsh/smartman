import 'dart:async';

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
import '../../design/word_break.dart';

/// A deck's page: its tile, name and card count, the white card that studies
/// it, and its cards under a pinned row whose "뜻 보기" switch shows or hides
/// every back, each back also toggled by a tap, searchable from the top
/// bar; adds a card, opens one for editing, and the deck for renaming or
/// deleting. While the deck holds no card, adding one is its one primary
/// action and there is nothing to study.
class DeckScreen extends ConsumerStatefulWidget {
  const DeckScreen({super.key, required this.deck, this.addingCard = false});

  final Deck deck;

  /// Whether the screen opens on adding a card, as when the 오늘 tab's
  /// "카드 추가" opened it.
  final bool addingCard;

  @override
  ConsumerState<DeckScreen> createState() => _DeckScreenState();
}

enum _DeckAction { rename, appearance, publish, unpublish, delete }

/// The ways the add sheet offers to add a card.
enum _Add { byHand, camera, album }

class _DeckScreenState extends ConsumerState<DeckScreen> {
  /// The card search, or null while it is closed.
  String? _query;

  /// The "뜻 보기" switch, off each time the page opens.
  bool _showAll = false;

  /// The cards a tap has set apart from the switch since it last changed.
  final Set<CardId> _flipped = {};

  @override
  void initState() {
    super.initState();
    if (widget.addingCard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final photoImport = ref.read(photoImportProvider);
        photoImport == null ? _open(null) : _addCard(photoImport);
      });
    }
  }

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
    final current = _stored(ref.watch(deckProvider(widget.deck.id)));
    final public = current.visibility is PublicDeck;
    final empty = switch (cards) {
      AsyncData(:final value) => value.isEmpty,
      _ => false,
    };
    final query = _query;
    // An open search closes on the back, and a second back leaves.
    return PopScope(
      canPop: query == null,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) setState(() => _query = null);
      },
      child: Scaffold(
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
                _DeckAction.appearance => _customize(current),
                _DeckAction.publish => sharing?.publish(context, current),
                _DeckAction.unpublish => sharing?.unpublish(context, current),
                _DeckAction.delete => _delete(),
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _DeckAction.rename,
                  child: Text(l10n.rename),
                ),
                PopupMenuItem(
                  value: _DeckAction.appearance,
                  child: Text(l10n.deckAppearance),
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
                  child: Text(
                    l10n.deleteDeck,
                    style: TextStyle(color: colors.dontKnowText),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: switch (cards) {
          AsyncData(:final value) => CustomScrollView(
            slivers: [
              // While searching, the matches start under the top bar.
              if (query == null)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.gutter,
                  ),
                  sliver: SliverList.list(
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
                                  child: Text(
                                    current.name,
                                    style: AppType.title,
                                  ),
                                ),
                                Text(
                                  public
                                      ? l10n.deckSummaryPublic(value.length)
                                      : l10n.deckSummary(value.length),
                                  style: AppType.secondary.copyWith(
                                    color: colors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.s16),
                      // With no card, the empty line and "카드 추가" are the
                      // screen's content, with no count of zeros above them.
                      if (!empty) ...[
                        _DeckTodayCard(deck: widget.deck.id, onStudy: _study),
                        const SizedBox(height: AppSpace.s12),
                      ],
                    ],
                  ),
                ),
              if (value.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.gutter,
                    vertical: AppSpace.s40,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      keepWords(l10n.noCards),
                      semanticsLabel: l10n.noCards,
                      textAlign: TextAlign.center,
                      style: AppType.body.copyWith(color: colors.muted),
                    ),
                  ),
                )
              else
                ..._cardList(l10n, value),
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
            // With no card, adding one is the screen's one primary action.
            variant: empty
                ? AppButtonVariant.primary
                : AppButtonVariant.secondary,
            size: AppButtonSize.cta,
            onPressed: photoImport == null
                ? () => _open(null)
                : () => _addCard(photoImport),
          ),
        ),
      ),
    );
  }

  /// The pinned "카드 n" row with its "뜻 보기" switch, then a row for each
  /// card whose front or back holds the search, ignoring case, its back
  /// shown as the switch and the card's own taps leave it.
  List<Widget> _cardList(AppLocalizations l10n, List<Card> cards) {
    final query = (_query ?? '').trim().toLowerCase();
    final rows =
        [
              for (final card in cards)
                (
                  card: card,
                  front: describeContent(l10n, card.front),
                  back: describeContent(l10n, card.back),
                ),
            ]
            .where(
              (row) =>
                  row.front.toLowerCase().contains(query) ||
                  row.back.toLowerCase().contains(query),
            )
            .toList();
    const gutter = EdgeInsets.symmetric(horizontal: AppSpace.gutter);
    return [
      PinnedHeaderSliver(
        child: _CardListHeader(
          count: rows.length,
          showAll: _showAll,
          onShowAll: (show) => setState(() {
            _showAll = show;
            _flipped.clear();
          }),
        ),
      ),
      SliverPadding(
        padding: gutter.copyWith(bottom: AppSpace.s16),
        sliver: rows.isEmpty
            ? SliverPadding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.s32),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    keepWords(l10n.noMatches),
                    semanticsLabel: l10n.noMatches,
                    textAlign: TextAlign.center,
                    style: AppType.body.copyWith(
                      color: AppColors.of(context).muted,
                    ),
                  ),
                ),
              )
            : SliverList.list(
                children: [
                  for (final row in rows)
                    CardBackRow(
                      key: ValueKey(row.card.id),
                      front: row.card.front,
                      back: row.card.back,
                      shown: _showAll != _flipped.contains(row.card.id),
                      onToggle: () => setState(() {
                        if (!_flipped.remove(row.card.id)) {
                          _flipped.add(row.card.id);
                        }
                      }),
                      onEdit: () => _open(row.card),
                    ),
                ],
              ),
      ),
    ];
  }

  /// Offers the ways to add a card, named as the new-deck sheet names them:
  /// by hand, or from a photo taken with the camera or picked from the album.
  Future<void> _addCard(PhotoImport photoImport) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showOptionSheet<_Add>(
      context,
      title: l10n.newCard,
      options: [
        (
          icon: LucideIcons.pencilLine,
          title: l10n.createManually,
          body: l10n.addCardManuallyBody,
          value: _Add.byHand,
        ),
        (
          icon: LucideIcons.camera,
          title: l10n.photoCamera,
          body: l10n.photoCameraBody,
          value: _Add.camera,
        ),
        (
          icon: LucideIcons.images,
          title: l10n.photoAlbum,
          body: l10n.photoAlbumBody,
          value: _Add.album,
        ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case _Add.byHand:
        await _open(null);
      case _Add.camera:
        await _importPhoto(photoImport, PhotoOrigin.camera);
      case _Add.album:
        await _importPhoto(photoImport, PhotoOrigin.album);
      case null:
        return;
    }
  }

  /// Starts photo import for this deck from a photo by [origin]. When it
  /// saved into another deck, that deck's list replaces this one.
  Future<void> _importPhoto(PhotoImport photoImport, PhotoOrigin origin) async {
    final navigator = Navigator.of(context);
    final deck = await photoImport(context, widget.deck.id, origin);
    if (deck == null || deck.id == widget.deck.id || !mounted) return;
    await navigator.pushReplacement(
      MaterialPageRoute<void>(builder: (_) => DeckScreen(deck: deck)),
    );
  }

  /// The deck as [stored] holds it now, so a rename or a publish made here
  /// or synced in shows; the deck the screen opened on until it is read.
  Deck _stored(AsyncValue<Deck?> stored) => switch (stored) {
    AsyncData(value: final deck?) => deck,
    _ => widget.deck,
  };

  /// The deck's name as stored now.
  String get _name => _stored(ref.read(deckProvider(widget.deck.id))).name;

  void _study() => unawaited(openStudy(context, DeckSelection(widget.deck.id)));

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
    });
  }

  /// Opens 덱 꾸미기 on [deck] as stored now, and stores the pair chosen.
  Future<void> _customize(Deck deck) async {
    final repository = ref.read(deckRepositoryProvider);
    final chosen = await showDeckAppearanceSheet(context, deck: deck);
    if (chosen == null || !mounted) return;
    final (icon, color) = chosen;
    await reportingFailure(context, () async {
      await repository.setAppearance(deck.id, icon, color);
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

/// The row pinned above the card list: how many cards it lists, and the
/// "뜻 보기" switch, whose label stays while the switch shows its state.
class _CardListHeader extends StatelessWidget {
  const _CardListHeader({
    required this.count,
    required this.showAll,
    required this.onShowAll,
  });

  final int count;
  final bool showAll;
  final ValueChanged<bool> onShowAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    // At the right, the switch's own margin brings its track to the gutter.
    return ColoredBox(
      color: colors.ground,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.s4,
          AppSpace.s16,
          AppSpace.s4,
        ),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(l10n.cardListTitle(count), style: AppType.label),
              ),
            ),
            MergeSemantics(
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => onShowAll(!showAll),
                    child: Text(
                      l10n.showMeanings,
                      style: AppType.secondary.copyWith(color: colors.ink2),
                    ),
                  ),
                  Switch(value: showAll, onChanged: onShowAll),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The deck's white card: today's count and its minutes, "n장 중 m장 익힘" over
/// the progress bar, and the button that studies the deck.
class _DeckTodayCard extends StatelessWidget {
  const _DeckTodayCard({required this.deck, required this.onStudy});

  final DeckId deck;
  final VoidCallback onStudy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final quiet = AppType.secondary.copyWith(color: colors.muted);
    return Semantics(
      container: true,
      label: l10n.todayThisDeck,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppShadow.card(colors),
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
                      TodayPending() => const SizedBox(height: AppSpace.s40),
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
                            l10n.deckMastered(
                              progress.total,
                              progress.mastered,
                            ),
                            style: quiet,
                          ),
                          ProgressBar(progress: progress, height: AppSpace.s8),
                        ],
                      ),
              ),
              AppButton(
                label: l10n.studyDeck,
                icon: LucideIcons.play,
                onPressed: onStudy,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
