import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../deck/deck.dart';
import '../../design/app_button.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../sharing/sharing.dart';
import 'decks_tab.dart';
import 'first_run.dart';
import 'new_deck_sheet.dart';
import 'record_tab.dart';
import 'today_tab.dart';

/// The signed-in app: the 오늘, 덱 and 기록 tabs over the user's decks, or the
/// first-run home before the first deck. Back on another tab returns to 오늘.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  /// Whether the 기록 tab was shown: it reads every review, so not before.
  bool _recordShown = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final sharing = ref.watch(sharingServiceProvider);
    return switch ((ref.watch(decksProvider), ref.watch(cardCountsProvider))) {
      (AsyncData(value: final decks), AsyncData(value: final counts)) =>
        decks.isEmpty
            ? Scaffold(
                appBar: AppBar(
                  titleSpacing: AppSpace.gutter,
                  title: const BrandTitle(),
                  actions: const [AccountButton()],
                ),
                body: _EmptyHome(
                  onCreate: () => showNewDeckSheet(context, ref),
                  onBrowse: sharing == null
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => sharing.browseScreen(),
                          ),
                        ),
                ),
              )
            : PopScope(
                canPop: _tab == 0,
                onPopInvokedWithResult: (popped, _) {
                  if (!popped) setState(() => _tab = 0);
                },
                child: Scaffold(
                  body: IndexedStack(
                    index: _tab,
                    children: [
                      TodayTab(
                        decks: decks,
                        counts: counts,
                        onShowDecks: () => setState(() => _tab = 1),
                      ),
                      DecksTab(decks: decks, counts: counts),
                      if (_recordShown)
                        RecordTab(decks: decks)
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                  bottomNavigationBar: _TabBar(
                    selected: _tab,
                    onSelect: (tab) => setState(() {
                      _tab = tab;
                      _recordShown |= tab == 2;
                    }),
                  ),
                ),
              ),
      (AsyncError(:final error, :final stackTrace), _) ||
      (_, AsyncError(:final error, :final stackTrace)) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.gutter),
            child: Text(
              describeProviderError(l10n, error, stackTrace),
              style: AppType.body.copyWith(color: colors.ink),
            ),
          ),
        ),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

/// The three tabs at the foot of the screen, on the surface over a hairline:
/// the selected one in ink, the others muted.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final tabs = [
      (icon: LucideIcons.sun, label: l10n.tabToday),
      (icon: LucideIcons.layers, label: l10n.tabDecks),
      (icon: LucideIcons.chartColumn, label: l10n.tabRecord),
    ];
    return Semantics(
      container: true,
      label: l10n.tabsLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              for (final (index, tab) in tabs.indexed)
                Expanded(
                  child: Semantics(
                    selected: index == selected,
                    button: true,
                    child: InkWell(
                      onTap: () => onSelect(index),
                      child: SizedBox(
                        height: AppSize.cta + AppSpace.s8,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          spacing: AppSpace.s4,
                          children: [
                            Icon(
                              tab.icon,
                              color: index == selected
                                  ? colors.ink
                                  : colors.muted,
                            ),
                            Text(
                              tab.label,
                              style: AppType.micro.copyWith(
                                color: index == selected
                                    ? colors.ink
                                    : colors.muted,
                                fontWeight: index == selected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The first-run home: the mascot, what to do first, "덱 만들기", which opens
/// the new-deck sheet with every way to start one, and, with sharing, the
/// public decks.
class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.onCreate, required this.onBrowse});

  final VoidCallback onCreate;
  final VoidCallback? onBrowse;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onBrowse = this.onBrowse;
    return FirstRun(
      title: l10n.emptyHomeTitle,
      body: l10n.emptyHomeBody,
      actions: [
        AppButton(
          label: l10n.makeDeck,
          icon: LucideIcons.plus,
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
    );
  }
}
