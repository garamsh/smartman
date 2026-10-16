import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../account/account.dart';
import '../../deck/deck.dart';
import '../../design/app_button.dart';
import '../../design/app_chip.dart';
import '../../design/app_section_label.dart';
import '../../design/bottom_actions.dart';
import '../../design/mascot.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../photo_import/photo_import.dart';
import '../../sharing/sharing.dart';
import '../../study/study.dart';
import '../../sync/sync.dart';
import 'deck_screen.dart';

/// Lists decks under today's count and creates them. A long-press enters a
/// selection mode that studies several decks in one session.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// The decks selected, or null outside selection mode.
  Set<DeckId>? _selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final decks = ref.watch(decksProvider);
    final counts = ref.watch(cardCountsProvider);
    final photoImport = ref.watch(photoImportProvider);
    final sharing = ref.watch(sharingServiceProvider);
    // A deck deleted while selected drops out of the selection.
    final selected = switch ((_selected, decks)) {
      (final selected?, AsyncData(:final value)) => {
        for (final deck in value)
          if (selected.contains(deck.id)) deck.id,
      },
      (final selected, _) => selected,
    };
    final colors = AppColors.of(context);
    final empty = switch (decks) {
      AsyncData(:final value) => value.isEmpty,
      _ => false,
    };
    return Scaffold(
      appBar: selected == null
          ? AppBar(
              titleSpacing: AppSpace.gutter,
              title: Semantics(
                header: true,
                image: true,
                label: l10n.appTitle,
                child: Image.asset(
                  AppBrand.lockup(Theme.of(context).brightness),
                  height: AppSize.lockupHeight,
                  excludeFromSemantics: true,
                ),
              ),
              actions: [
                if (sharing != null)
                  IconButton(
                    tooltip: l10n.browse,
                    icon: const Icon(LucideIcons.compass),
                    onPressed: () => _browse(sharing),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: AppSpace.s12),
                  child: IconButton(
                    tooltip: l10n.account,
                    icon: const AccountAvatar(size: AppSize.smallAvatar),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AccountScreen(
                          syncStatus: SyncStatusView(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : _selectionBar(l10n, selected),
      body: switch ((decks, counts)) {
        (AsyncData(value: final decks), AsyncData(value: final counts)) =>
          decks.isEmpty
              ? _EmptyHome(
                  onPhoto: photoImport == null
                      ? null
                      : () => _importPhoto(photoImport),
                  onCreate: _create,
                  onBrowse: sharing == null ? null : () => _browse(sharing),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.gutter,
                    AppSpace.s8,
                    AppSpace.gutter,
                    AppSpace.s16,
                  ),
                  children: [
                    if (DeckSelection.of([for (final d in decks) d.id])
                        case final all?)
                      TodayCounter(
                        decks: all,
                        builder: (context, count) => _TodayCard(
                          count: count,
                          onStudy: () => _study(all),
                        ),
                      ),
                    const SizedBox(height: AppSpace.sectionGap),
                    _DecksLabel(
                      count: decks.length,
                      showHint: selected == null,
                    ),
                    for (final deck in decks)
                      DeckRow(
                        deck: deck,
                        cardCount: counts[deck.id] ?? 0,
                        selected: selected?.contains(deck.id),
                        onSelect: () => _toggle(deck.id),
                        onOpen: () => _open(deck),
                        today: TodayCounter(
                          decks: DeckSelection(deck.id),
                          builder: (context, count) => _TodayChip(count: count),
                        ),
                      ),
                  ],
                ),
        (AsyncError(:final error, :final stackTrace), _) ||
        (_, AsyncError(:final error, :final stackTrace)) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.gutter),
            child: Text(
              describeProviderError(l10n, error, stackTrace),
              style: AppType.body.copyWith(color: colors.ink),
            ),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
      bottomNavigationBar: empty
          ? null
          : BottomActions(
              secondary: AppButton(
                label: l10n.newDeck,
                icon: LucideIcons.plus,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.cta,
                onPressed: _create,
              ),
              primary: photoImport == null
                  ? null
                  : AppButton(
                      label: l10n.createFromPhoto,
                      icon: LucideIcons.camera,
                      size: AppButtonSize.cta,
                      onPressed: () => _importPhoto(photoImport),
                    ),
            ),
    );
  }

  void _browse(SharingService sharing) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => sharing.browseScreen()));

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
            onPressed: study == null ? null : () => _study(study),
          ),
        ),
      ],
    );
  }

  void _study(DeckSelection decks) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => StudyScreen(decks: decks)),
  );

  void _open(Deck deck) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => DeckScreen(deck: deck)));

  /// Opens photo import for a new deck, then the deck it saved into.
  Future<void> _importPhoto(Widget Function(DeckId? deck) photoImport) async {
    final navigator = Navigator.of(context);
    final deck = await navigator.push(
      MaterialPageRoute<Deck>(builder: (_) => photoImport(null)),
    );
    if (deck == null || !mounted) return;
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => DeckScreen(deck: deck)),
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
      title: l10n.newDeckTitle,
      body: l10n.newDeckBody,
      action: l10n.create,
    );
    if (name == null || !mounted) return;
    await reportingFailure(context, () => repository.createDeck(name));
  }
}

/// The first-run home: the mascot, what to do first, and the three ways to
/// start a deck, each shown only when the app offers it.
class _EmptyHome extends StatelessWidget {
  const _EmptyHome({
    required this.onPhoto,
    required this.onCreate,
    required this.onBrowse,
  });

  final VoidCallback? onPhoto;
  final VoidCallback onCreate;
  final VoidCallback? onBrowse;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final onPhoto = this.onPhoto;
    final onBrowse = this.onBrowse;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.s40,
        AppSpace.gutter,
        AppSpace.s24,
      ),
      children: [
        Center(
          child: Mascot(size: AppSize.mascotLarge, fill: colors.surface),
        ),
        const SizedBox(height: AppSpace.s24),
        Semantics(
          header: true,
          child: Text(
            l10n.emptyHomeTitle,
            textAlign: TextAlign.center,
            style: AppType.title,
          ),
        ),
        const SizedBox(height: AppSpace.s8),
        Text(
          l10n.emptyHomeBody,
          textAlign: TextAlign.center,
          style: AppType.secondary.copyWith(color: colors.muted),
        ),
        const SizedBox(height: AppSpace.s32),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpace.s8,
          children: [
            if (onPhoto != null)
              AppButton(
                label: l10n.createFromPhoto,
                icon: LucideIcons.camera,
                size: AppButtonSize.cta,
                onPressed: onPhoto,
              ),
            AppButton(
              label: l10n.createManually,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.cta,
              onPressed: onCreate,
            ),
            if (onBrowse != null)
              AppButton(
                label: l10n.browsePublicDecks,
                variant: AppButtonVariant.text,
                onPressed: onBrowse,
              ),
          ],
        ),
      ],
    );
  }
}

/// Today's cards over every deck on the brand's navy card: the count, its
/// split into due and new with the minutes it takes, and the action that
/// studies them, with the symbol faint in the corner; with none, that today's
/// cards are done, and the action that keeps studying.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.count, required this.onStudy});

  final TodayCount count;
  final VoidCallback onStudy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final quiet = AppType.secondary.copyWith(color: colors.onHero);
    final done = switch (count) {
      TodayCounted(total: 0) => true,
      _ => false,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.hero,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadow.card(colors),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Stack(
          children: [
            Positioned(
              top: -AppSpace.s16,
              right: -AppSpace.s16,
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: 0.12,
                  child: Image.asset(
                    AppBrand.symbol(Brightness.dark),
                    width: AppSize.heroSymbol,
                    height: AppSize.heroSymbol,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.s24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!done) ...[
                    Text(
                      l10n.todayTitle,
                      style: AppType.section.copyWith(color: colors.onHero),
                    ),
                    const SizedBox(height: AppSpace.s4),
                  ],
                  ...switch (count) {
                    TodayCounted(total: 0) => [
                      Semantics(
                        header: true,
                        child: Text(
                          l10n.todayDone,
                          style: AppType.title.copyWith(color: colors.onHero),
                        ),
                      ),
                    ],
                    TodayCounted(
                      :final review,
                      :final fresh,
                      :final total,
                      :final minutes,
                      :final backlog,
                    ) =>
                      [
                        Semantics(
                          container: true,
                          label: l10n.todayCards(total),
                          excludeSemantics: true,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: '$total', style: AppType.figure),
                                const TextSpan(text: ' '),
                                TextSpan(
                                  text: l10n.todayCountUnit,
                                  style: AppType.headline,
                                ),
                              ],
                            ),
                            style: TextStyle(color: colors.onHero),
                          ),
                        ),
                        const SizedBox(height: AppSpace.s4),
                        Text(
                          l10n.todayBreakdown(review, fresh, minutes),
                          style: quiet,
                        ),
                        if (backlog) Text(l10n.backlogPaused, style: quiet),
                      ],
                    TodayUnavailable(:final message) => [
                      Text(message, style: quiet),
                    ],
                    // The count's and the line's height, so the card does
                    // not jump.
                    TodayPending() => [
                      const SizedBox(height: AppSpace.s40 + AppSpace.s28),
                    ],
                  },
                  // With nothing left the card says so and still offers a
                  // session, which opens on the completion card or on
                  // nothing to study.
                  const SizedBox(height: AppSpace.s20),
                  AppButton(
                    label: done ? l10n.todayKeepStudying : l10n.studyAll,
                    icon: LucideIcons.play,
                    variant: AppButtonVariant.onHero,
                    onPressed: onStudy,
                  ),
                ],
              ),
            ),
          ],
        ),
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

/// A brand-tint "오늘 n" when a session over the deck would study any card
/// now.
class _TodayChip extends StatelessWidget {
  const _TodayChip({required this.count});

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
