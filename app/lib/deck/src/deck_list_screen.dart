import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import '../../shared/ui/app_button.dart';
import '../../shared/ui/app_chip.dart';
import '../../shared/ui/app_list_row.dart';
import '../../shared/ui/app_section_label.dart';
import 'bottom_actions.dart';
import 'card_list_screen.dart';
import 'failure_message.dart';
import 'model.dart';
import 'name_sheet.dart';
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
            padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter,
              0,
              AppSpace.gutter,
              AppSpace.s16,
            ),
            children: [
              _LargeTitle(l10n.decksTitle),
              if (decks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.s40),
                  child: Text(
                    l10n.noDecks,
                    textAlign: TextAlign.center,
                    style: AppType.body.copyWith(
                      color: AppColors.of(context).muted,
                    ),
                  ),
                )
              else if (DeckSelection.of([for (final d in decks) d.id])
                  case final all?) ...[
                ref.watch(todayProvider)(
                  all,
                  (context, count) =>
                      _TodayHeader(count: count, onStudy: () => _study(all)),
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
            padding: const EdgeInsets.all(AppSpace.gutter),
            child: Text(describeProviderError(l10n, error, stackTrace)),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
      bottomNavigationBar: BottomActions(
        secondary: AppButton(
          label: l10n.newDeck,
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.cta,
          onPressed: _create,
        ),
        primary: photoImport == null
            ? null
            : AppButton(
                label: l10n.createFromPhoto,
                size: AppButtonSize.cta,
                onPressed: () => _importPhoto(photoImport),
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
        Padding(
          padding: const EdgeInsets.only(right: AppSpace.s12),
          child: AppButton(
            label: l10n.studySelected(selected.length),
            variant: AppButtonVariant.text,
            onPressed: study == null ? null : () => _study(study),
          ),
        ),
      ],
    );
  }

  void _study(DeckSelection decks) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ref.read(studyScreenProvider)(decks),
    ),
  );

  /// Opens photo import for a new deck, then the deck it saved into.
  Future<void> _importPhoto(Widget Function(DeckId? deck) photoImport) async {
    final navigator = Navigator.of(context);
    final deck = await navigator.push(
      MaterialPageRoute<Deck>(builder: (_) => photoImport(null)),
    );
    if (deck == null || !mounted) return;
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => CardListScreen(deck: deck)),
    );
  }

  /// Enters selection mode with [deck], or adds or removes it once there.
  void _toggle(DeckId deck) => setState(() {
    final selected = _selected ??= {};
    if (!selected.remove(deck)) selected.add(deck);
  });

  Future<void> _create() async {
    final repository = ref.read(deckRepositoryProvider);
    final l10n = AppLocalizations.of(context);
    final name = await showNameSheet(
      context,
      title: l10n.newDeck,
      action: l10n.create,
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
    padding: const EdgeInsets.only(bottom: AppSpace.s20),
    child: Semantics(header: true, child: Text(text, style: AppType.display)),
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
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.s24),
      padding: const EdgeInsets.all(AppSpace.s20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadow.card(colors),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpace.s4,
        children: [
          ...switch (count) {
            TodayCounted(:final review, :final fresh, :final total) => [
              Text(l10n.todayCards(total), style: AppType.title),
              Text(
                l10n.todayBreakdown(review, fresh),
                style: AppType.secondary.copyWith(color: colors.muted),
              ),
            ],
            TodayUnavailable(:final message) => [
              Text(message, style: AppType.body),
            ],
            // The two lines' height, so the header does not jump.
            TodayPending() => [
              const SizedBox(height: AppSpace.s32 + AppSpace.s20),
            ],
          },
          const SizedBox(height: AppSpace.s12),
          AppButton(
            label: l10n.studyAll,
            variant: AppButtonVariant.study,
            onPressed: onStudy,
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
    return AppSectionLabel(
      l10n.myDecks(count),
      trailing: showHint
          ? Text(
              l10n.selectHint,
              style: AppType.micro.copyWith(color: AppColors.of(context).muted),
            )
          : null,
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
    final selected = this.selected;
    return AppListRow(
      title: deck.name,
      subtitle: l10n.cardCount(cardCount),
      selected: selected,
      leading: selected == null
          ? null
          : Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? colors.know : colors.muted,
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpace.s8,
        children: [
          ref.watch(todayProvider)(
            DeckSelection(deck.id),
            (context, count) => _TodayChip(count: count),
          ),
          if (selected == null) Icon(Icons.chevron_right, color: colors.muted),
        ],
      ),
      onTap: selected == null
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CardListScreen(deck: deck),
              ),
            )
          : onSelect,
      onLongPress: onSelect,
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
      TodayCounted(:final total) when total > 0 => AppChip(
        label: AppLocalizations.of(context).todayChip(total),
        tone: AppChipTone.know,
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
