import 'package:flutter/material.dart';

import '../../design/app_button.dart';
import '../../design/app_section_label.dart';
import '../../design/app_sheet.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'deck_row.dart';
import 'model.dart';

/// Asks for [deck]'s icon and colour in the 덱 꾸미기 sheet, the pair
/// previewed on its tile; returns the pair on "저장", or null when the sheet
/// is dismissed.
Future<(DeckIcon, DeckColor)?> showDeckAppearanceSheet(
  BuildContext context, {
  required Deck deck,
}) => showAppSheet<(DeckIcon, DeckColor)>(
  context,
  builder: (_) => _AppearanceSheet(deck: deck),
);

class _AppearanceSheet extends StatefulWidget {
  const _AppearanceSheet({required this.deck});

  final Deck deck;

  @override
  State<_AppearanceSheet> createState() => _AppearanceSheetState();
}

class _AppearanceSheetState extends State<_AppearanceSheet> {
  late DeckIcon _icon = widget.deck.icon ?? DeckIcon.fallback;
  late DeckColor _color = widget.deck.color ?? defaultDeckColor(widget.deck.id);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return AppSheet(
      title: l10n.deckAppearance,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpace.s12,
        children: [
          Center(
            child: DeckTile(
              deck: widget.deck,
              icon: _icon,
              color: _color,
              size: AppSize.deckTile * 2,
            ),
          ),
          AppSectionLabel(l10n.deckAppearanceIcon),
          Wrap(
            spacing: AppSpace.s8,
            runSpacing: AppSpace.s8,
            children: [
              for (final icon in DeckIcon.values)
                _Option(
                  label: l10n.deckIconName(icon.key),
                  selected: icon == _icon,
                  onTap: () => setState(() => _icon = icon),
                  fill: icon == _icon ? colors.brandTint : null,
                  child: Icon(deckIconData(icon), color: colors.ink),
                ),
            ],
          ),
          AppSectionLabel(l10n.deckAppearanceColor),
          Wrap(
            spacing: AppSpace.s8,
            runSpacing: AppSpace.s8,
            children: [
              for (final color in DeckColor.values)
                _Option(
                  label: l10n.deckColorName(color.key),
                  selected: color == _color,
                  onTap: () => setState(() => _color = color),
                  fill: deckTileColor(colors, color),
                ),
            ],
          ),
        ],
      ),
      actions: [
        AppButton(
          label: l10n.save,
          size: AppButtonSize.cta,
          onPressed: () => Navigator.of(context).pop((_icon, _color)),
        ),
      ],
    );
  }
}

/// One choice in the sheet: a rounded target at least 48 square, named by
/// [label] and read as selected or not, ringed in ink while [selected].
class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
    this.fill,
    this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? fill;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final radius = BorderRadius.circular(AppRadius.field);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: fill ?? colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? colors.ink : colors.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: SizedBox.square(
            dimension: AppSize.tapTarget + AppSpace.s4,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
