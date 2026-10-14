import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import 'bottom_actions.dart';
import 'card_list_screen.dart';
import 'failure_message.dart';
import 'model.dart';
import 'name_dialog.dart';
import 'providers.dart';

/// Lists decks under today's count and creates them. A long-press enters a
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
    final counts = ref.watch(cardCountsProvider);
    final photoImport = ref.watch(photoImportProvider);
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
      body: switch ((decks, counts)) {
        (AsyncData(value: final decks), AsyncData(value: final counts)) =>
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _LargeTitle(l10n.decksTitle),
              if (decks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Text(l10n.noDecks, textAlign: TextAlign.center),
                )
              else ...[
                ref.watch(todayProvider)(
                  DeckSelection(decks.first.id, decks.skip(1).map((d) => d.id)),
                  (context, count) => _TodayHeader(
                    count: count,
                    onStudy: () => _study(
                      DeckSelection(
                        decks.first.id,
                        decks.skip(1).map((d) => d.id),
                      ),
                    ),
                  ),
                ),
                _DecksLabel(count: decks.length, showHint: selected == null),
                for (final deck in decks)
                  _DeckRow(
                    deck: deck,
                    cardCount: counts[deck.id] ?? 0,
                    selected: selected?.contains(deck.id),
                    onSelect: () => _toggle(deck.id),
                  ),
              ],
            ],
          ),
        (AsyncError(:final error, :final stackTrace), _) ||
        (_, AsyncError(:final error, :final stackTrace)) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(describeProviderError(l10n, error, stackTrace)),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
      bottomNavigationBar: BottomActions(
        secondary: OutlinedButton(
          onPressed: _create,
          child: Text(l10n.newDeck),
        ),
        primary: photoImport == null
            ? null
            : FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => photoImport(null)),
                ),
                child: Text(l10n.createFromPhoto),
              ),
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
          onPressed: study == null ? null : () => _study(study),
          child: Text(l10n.studySelected(selected.length)),
        ),
      ],
    );
  }

  void _study(DeckSelection decks) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ref.read(studyScreenProvider)(decks),
    ),
  );

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

/// A screen's large title, read as a heading.
class _LargeTitle extends StatelessWidget {
  const _LargeTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.headlineLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

/// How many cards a session over every deck would study now, split into due
/// and new, and the action that studies them.
class _TodayHeader extends StatelessWidget {
  const _TodayHeader({required this.count, required this.onStudy});

  final TodayCount count;
  final VoidCallback onStudy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          ...switch (count) {
            TodayCounted(:final review, :final fresh, :final total) => [
              Text(
                l10n.todayCards(total),
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                l10n.todayBreakdown(review, fresh),
                style: textTheme.bodyMedium?.copyWith(color: colors.muted),
              ),
            ],
            TodayUnavailable(:final message) => [Text(message)],
            TodayPending() => [const SizedBox(height: 56)],
          },
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.know,
              foregroundColor: colors.onKnow,
            ),
            onPressed: onStudy,
            child: Text(l10n.studyAll),
          ),
        ],
      ),
    );
  }
}

/// "내 덱 n" above the rows, with the hint that a long-press selects.
class _DecksLabel extends StatelessWidget {
  const _DecksLabel({required this.count, required this.showHint});

  final int count;
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.myDecks(count),
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (showHint)
            Text(
              l10n.selectHint,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.of(context).muted,
              ),
            ),
        ],
      ),
    );
  }
}

class _DeckRow extends ConsumerWidget {
  const _DeckRow({
    required this.deck,
    required this.cardCount,
    required this.selected,
    required this.onSelect,
  });

  final Deck deck;
  final int cardCount;

  /// Whether the deck is selected, or null outside selection mode.
  final bool? selected;

  /// Enters selection mode with this deck, or toggles it once there.
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final selected = this.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MergeSemantics(
        child: Semantics(
          selected: selected,
          child: Material(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.row),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.row),
              onTap: selected == null
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CardListScreen(deck: deck),
                      ),
                    )
                  : onSelect,
              onLongPress: onSelect,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  spacing: 12,
                  children: [
                    if (selected != null)
                      Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: selected ? colors.know : colors.muted,
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 2,
                        children: [
                          Text(
                            deck.name,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            l10n.cardCount(cardCount),
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ref.watch(todayProvider)(
                      DeckSelection(deck.id),
                      (context, count) => _TodayChip(count: count),
                    ),
                    if (selected == null)
                      Icon(Icons.chevron_right, color: colors.muted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A green "오늘 n" when a session over the deck would study any card now.
class _TodayChip extends StatelessWidget {
  const _TodayChip({required this.count});

  final TodayCount count;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return switch (count) {
      TodayCounted(:final total) when total > 0 => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: colors.know,
          borderRadius: BorderRadius.circular(AppRadius.row),
        ),
        child: Text(
          AppLocalizations.of(context).todayChip(total),
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: colors.onKnow, fontWeight: FontWeight.w600),
        ),
      ),
      TodayUnavailable(:final message) => Tooltip(
        message: message,
        child: Icon(
          Icons.error_outline,
          color: colors.muted,
          semanticLabel: message,
        ),
      ),
      TodayCounted() || TodayPending() => const SizedBox.shrink(),
    };
  }
}
