import 'package:flutter/material.dart';

import '../../deck/deck.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../study/study.dart';

/// The 기록 tab: `study`'s [StatsView] over every deck, under the tab's
/// title.
class RecordTab extends StatelessWidget {
  const RecordTab({super.key, required this.decks});

  final List<Deck> decks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final all = DeckSelection.of([for (final deck in decks) deck.id]);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: all == null
            ? const SizedBox.shrink()
            : StatsView(
                decks: all,
                title: Semantics(
                  header: true,
                  child: Text(
                    l10n.tabRecord,
                    style: AppType.deckTitle.copyWith(color: colors.ink),
                  ),
                ),
              ),
      ),
    );
  }
}
