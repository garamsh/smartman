import 'package:flutter/material.dart';

import '../../design/app_chip.dart';
import '../../design/app_list_row.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'model.dart';

/// A deck on a row: its tile, its name and card count with "공개" when it is
/// published and [today] beside them, and [progress] under them. A tap calls
/// [onOpen].
class DeckRow extends StatelessWidget {
  const DeckRow({
    super.key,
    required this.deck,
    required this.cardCount,
    required this.onOpen,
    this.today,
    this.progress,
  });

  final Deck deck;
  final int cardCount;

  /// Opens the deck.
  final VoidCallback onOpen;

  /// What the deck holds for today, as its caller draws it.
  final Widget? today;

  /// How far the deck's cards have come, as its caller draws it.
  final Widget? progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return MergeSemantics(
      child: AppRowSurface(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.s16,
            AppSpace.s12,
            AppSpace.s12,
            AppSpace.s12,
          ),
          child: Row(
            spacing: AppSpace.s12,
            children: [
              DeckTile(deck: deck),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: AppSpace.s4,
                  children: [
                    Row(
                      spacing: AppSpace.s8,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            spacing: AppSpace.s8,
                            children: [
                              Flexible(
                                child: Text(
                                  deck.name,
                                  style: AppType.bodyStrong,
                                ),
                              ),
                              Text(
                                l10n.deckRowCards(cardCount),
                                style: AppType.caption.copyWith(
                                  color: colors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (deck.visibility is PublicDeck)
                          AppChip(label: l10n.publicChip),
                        ?today,
                      ],
                    ),
                    ?progress,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The deck name's first letter on a rounded tile, in one of the four tints,
/// the same one for a deck every time; decorative, beside the name.
class DeckTile extends StatelessWidget {
  const DeckTile({super.key, required this.deck});

  final Deck deck;

  @override
  Widget build(BuildContext context) {
    final tints = AppColors.of(context).deckTints;
    final name = deck.name.trim();
    return ExcludeSemantics(
      child: Container(
        width: AppSize.deckTile,
        height: AppSize.deckTile,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tints[deckTintIndex(deck.id, tints.length)],
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
        child: Text(
          name.isEmpty ? '' : name.characters.first.toUpperCase(),
          style: AppType.headline,
        ),
      ),
    );
  }
}

/// Which of [count] tints a deck's tile takes: the sum of its id's UTF-16
/// code units, modulo [count]. The web app computes the same.
int deckTintIndex(DeckId deck, int count) =>
    deck.value.codeUnits.fold(0, (sum, unit) => sum + unit) % count;
