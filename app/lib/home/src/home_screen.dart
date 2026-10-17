import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../deck/deck.dart';
import '../../design/app_button.dart';
import '../../design/mascot.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../photo_import/photo_import.dart';
import '../../sharing/sharing.dart';
import 'decks_tab.dart';
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
    final photoImport = ref.watch(photoImportProvider);
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
                  onPhoto: photoImport == null
                      ? null
                      : () => importDeckFromPhoto(context, photoImport),
                  onCreate: () => createDeckByHand(context, ref),
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
                      TodayTab(decks: decks),
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
