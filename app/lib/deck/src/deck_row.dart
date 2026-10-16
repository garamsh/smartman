import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_chip.dart';
import '../../design/app_list_row.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'model.dart';

/// A deck on a row: its tile, name and card count, "공개" when it is
/// published, [today] beside them, and a chevron that [onOpen] follows; in
/// selection mode, a check in place of the tile and the chevron.
class DeckRow extends StatelessWidget {
  const DeckRow({
    super.key,
    required this.deck,
    required this.cardCount,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    this.today,
  });

  final Deck deck;
  final int cardCount;

  /// Whether the deck is selected, or null outside selection mode.
  final bool? selected;

  /// Enters selection mode with this deck, or toggles it once there.
  final VoidCallback onSelect;

  /// Opens the deck, outside selection mode.
  final VoidCallback onOpen;

  /// What the deck holds for today, as its caller draws it.
  final Widget? today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final selected = this.selected;
    return AppListRow(
      title: deck.name,
      subtitle: l10n.cardCount(cardCount),
      selected: selected,
      leading: selected == null
          ? _DeckTile(deck: deck)
          : SizedBox.square(
              dimension: AppSize.deckTile,
              child: Icon(
                selected ? LucideIcons.circleCheck : LucideIcons.circle,
                color: selected ? colors.ink : colors.muted,
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpace.s8,
        children: [
          if (deck.visibility is PublicDeck) AppChip(label: l10n.publicChip),
          ?today,
          if (selected == null)
            Icon(LucideIcons.chevronRight, color: colors.muted),
        ],
      ),
      onTap: selected == null ? onOpen : onSelect,
      onLongPress: onSelect,
    );
  }
}

/// The deck name's first letter on a rounded tile, in one of the four tints,
/// the same one for a deck every time.
class _DeckTile extends StatelessWidget {
  const _DeckTile({required this.deck});

  final Deck deck;

  @override
  Widget build(BuildContext context) {
    final tints = AppColors.of(context).deckTints;
    final name = deck.name.trim();
    return Container(
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
    );
  }
}

/// Which of [count] tints a deck's tile takes: the sum of its id's UTF-16
/// code units, modulo [count]. The web app computes the same.
int deckTintIndex(DeckId deck, int count) =>
    deck.value.codeUnits.fold(0, (sum, unit) => sum + unit) % count;
