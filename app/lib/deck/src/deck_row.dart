import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_chip.dart';
import '../../design/app_list_row.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'model.dart';

/// A deck on a row: its tile, its name with "공개" when it is published and
/// [today] beside them, and [progress] under them, or its card count while
/// [progress] is null. A tap calls [onOpen].
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
                          child: Text(deck.name, style: AppType.bodyStrong),
                        ),
                        if (deck.visibility is PublicDeck)
                          AppChip(label: l10n.publicChip),
                        ?today,
                      ],
                    ),
                    progress ??
                        Text(
                          l10n.cardCount(cardCount),
                          style: AppType.caption.copyWith(color: colors.muted),
                        ),
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

/// The deck's icon on its colour, on a rounded tile; decorative, beside the
/// name. A deck that holds no icon or colour this build knows shows
/// [DeckIcon.fallback] on the colour its id selects ([deckTintIndex]).
///
/// [icon] and [color] are drawn in place of the deck's own, as the 덱 꾸미기
/// sheet previews a choice; [size] is the tile's side.
class DeckTile extends StatelessWidget {
  const DeckTile({
    super.key,
    required this.deck,
    this.icon,
    this.color,
    this.size = AppSize.deckTile,
  });

  final Deck deck;
  final DeckIcon? icon;
  final DeckColor? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final shown = color ?? deck.color ?? defaultDeckColor(deck.id);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: deckTileColor(colors, shown),
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
        child: Icon(
          deckIconData(icon ?? deck.icon ?? DeckIcon.fallback),
          size: size / 2,
          color: colors.ink,
        ),
      ),
    );
  }
}

/// The colour a deck with none chosen takes, selected by its id.
DeckColor defaultDeckColor(DeckId deck) =>
    DeckColor.values[deckTintIndex(deck, DeckColor.values.length)];

/// The line icon drawn for [icon].
IconData deckIconData(DeckIcon icon) => switch (icon) {
  DeckIcon.layers => LucideIcons.layers,
  DeckIcon.book => LucideIcons.bookOpen,
  DeckIcon.languages => LucideIcons.languages,
  DeckIcon.pencil => LucideIcons.pencil,
  DeckIcon.flask => LucideIcons.flaskConical,
  DeckIcon.calculator => LucideIcons.calculator,
  DeckIcon.globe => LucideIcons.globe,
  DeckIcon.music => LucideIcons.music,
  DeckIcon.palette => LucideIcons.palette,
  DeckIcon.brain => LucideIcons.brain,
  DeckIcon.code => LucideIcons.code,
  DeckIcon.landmark => LucideIcons.landmark,
  DeckIcon.briefcase => LucideIcons.briefcase,
  DeckIcon.star => LucideIcons.star,
};

/// The tile's fill for [color], from the theme's deck palette.
Color deckTileColor(AppColors colors, DeckColor color) => switch (color) {
  // TODO(worker-382): the palette tokens, once #384 frees theme.dart.
  DeckColor.blue => colors.tintBlue,
  DeckColor.sky => colors.brandTint,
  DeckColor.violet => colors.brandTint,
  DeckColor.sand => colors.brandTint,
  DeckColor.amber => colors.tintAmber,
  DeckColor.slate => colors.hairline,
};

/// Which of [count] colours a deck's tile takes by default: the sum of its id's UTF-16
/// code units, modulo [count]. The web app computes the same.
int deckTintIndex(DeckId deck, int count) =>
    deck.value.codeUnits.fold(0, (sum, unit) => sum + unit) % count;
