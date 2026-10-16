import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../deck/deck.dart';
import '../../design/app_button.dart';
import '../../design/app_chip.dart';
import '../../design/app_text_field.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../sharing/sharing.dart';
import '../../study/study.dart';
import 'deck_screen.dart';
import 'new_deck_sheet.dart';
import 'progress_bar.dart';

/// The 덱 tab: "내 덱 n" with 새 덱 and 선택, a search by name, a row per deck
/// with its progress and today's count, and the public decks. 선택 enters a
/// selection mode that studies several decks in one session.
class DecksTab extends ConsumerStatefulWidget {
  const DecksTab({super.key, required this.decks, required this.counts});

  final List<Deck> decks;
  final Map<DeckId, int> counts;

  @override
  ConsumerState<DecksTab> createState() => _DecksTabState();
}

class _DecksTabState extends ConsumerState<DecksTab> {
  /// The decks selected, or null outside selection mode.
  Set<DeckId>? _selected;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final sharing = ref.watch(sharingServiceProvider);
    // A deck deleted while selected drops out of the selection.
    final selected = switch (_selected) {
      final selected? => {
        for (final deck in widget.decks)
          if (selected.contains(deck.id)) deck.id,
      },
      null => null,
    };
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final deck in widget.decks)
        if (deck.name.toLowerCase().contains(query)) deck,
    ];
    return Scaffold(
      appBar: selected == null
          ? AppBar(
              toolbarHeight: AppSize.cta + AppSpace.s8,
              titleSpacing: AppSpace.gutter,
              title: Semantics(
                header: true,
                child: Text(
                  l10n.myDecks(widget.decks.length),
                  style: AppType.deckTitle,
                ),
              ),
              actions: [
                AppButton(
                  label: l10n.selectDecks,
                  variant: AppButtonVariant.text,
                  onPressed: () => setState(() => _selected = {}),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: AppSpace.gutter),
                  child: AppButton(
                    label: l10n.newDeck,
                    icon: LucideIcons.plus,
                    onPressed: () => showNewDeckSheet(context, ref),
                  ),
                ),
              ],
            )
          : _selectionBar(l10n, selected),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.s8,
          AppSpace.gutter,
          AppSpace.s16,
        ),
        children: [
          AppTextField(
            hint: l10n.searchDecks,
            prefixIcon: const Icon(LucideIcons.search),
            height: AppSize.search,
            onChanged: (query) => setState(() => _query = query),
          ),
          const SizedBox(height: AppSpace.s12),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.s32),
              child: Text(
                l10n.noDeckMatches,
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(color: colors.muted),
              ),
            ),
          for (final deck in shown)
            DeckRow(
              deck: deck,
              cardCount: widget.counts[deck.id] ?? 0,
              selected: selected?.contains(deck.id),
              onSelect: () => _toggle(deck.id),
              onOpen: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => DeckScreen(deck: deck)),
              ),
              today: TodayCounter(
                decks: DeckSelection(deck.id),
                builder: (context, count) => TodayChip(count: count),
              ),
              progress: ProgressCounter(
                decks: DeckSelection(deck.id),
                builder: (context, progress) => _DeckProgress(
                  progress: progress,
                  cardCount: widget.counts[deck.id] ?? 0,
                ),
              ),
            ),
          if (sharing != null && selected == null) ...[
            const SizedBox(height: AppSpace.s8),
            _BrowseEntry(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => sharing.browseScreen()),
              ),
            ),
          ],
        ],
      ),
    );
  }

  AppBar _selectionBar(AppLocalizations l10n, Set<DeckId> selected) {
    final study = DeckSelection.of(selected);
    return AppBar(
      leading: IconButton(
        tooltip: l10n.clearSelection,
        icon: const Icon(LucideIcons.x),
        onPressed: () => setState(() => _selected = null),
      ),
      title: Text(l10n.decksSelected(selected.length)),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpace.s12),
          child: AppButton(
            label: l10n.studySelected(selected.length),
            variant: AppButtonVariant.text,
            onPressed: study == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => StudyScreen(decks: study),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  /// Enters selection mode with [deck], or adds or removes it once there.
  void _toggle(DeckId deck) => setState(() {
    final selected = _selected ??= {};
    if (!selected.remove(deck)) selected.add(deck);
  });
}

/// A brand-tint "오늘 n" when a session over the deck would study any card
/// now, and the reason when the count cannot be read.
class TodayChip extends StatelessWidget {
  const TodayChip({super.key, required this.count});

  final TodayCount count;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return switch (count) {
      TodayCounted(:final total) when total > 0 => AppChip(
        label: AppLocalizations.of(context).todayChip(total),
        tone: AppChipTone.brand,
      ),
      TodayUnavailable(:final message) => Tooltip(
        message: message,
        child: Icon(
          LucideIcons.circleAlert,
          color: colors.muted,
          semanticLabel: message,
        ),
      ),
      TodayCounted() || TodayPending() => const SizedBox.shrink(),
    };
  }
}

/// A deck row's progress bar and "n장 중 m장 익힘"; the card count alone while
/// the progress is read.
class _DeckProgress extends StatelessWidget {
  const _DeckProgress({required this.progress, required this.cardCount});

  final DeckProgress? progress;
  final int cardCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final quiet = AppType.caption.copyWith(color: AppColors.of(context).muted);
    final progress = this.progress;
    if (progress == null) return Text(l10n.cardCount(cardCount), style: quiet);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpace.s4,
      children: [
        ExcludeSemantics(child: ProgressBar(progress: progress)),
        Text(l10n.deckMastered(progress.total, progress.mastered), style: quiet),
      ],
    );
  }
}

/// The way to other users' public decks, on a dashed outline.
class _BrowseEntry extends StatelessWidget {
  const _BrowseEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final radius = BorderRadius.circular(AppRadius.row);
    return MergeSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: colors.outline, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.s16),
              child: Row(
                spacing: AppSpace.s12,
                children: [
                  Icon(LucideIcons.compass, color: colors.ink),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.browsePublicDecks, style: AppType.bodyStrong),
                        Text(
                          l10n.browsePublicDecksBody,
                          style: AppType.caption.copyWith(color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(LucideIcons.chevronRight, color: colors.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
