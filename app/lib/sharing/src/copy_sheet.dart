import 'package:flutter/material.dart';

import '../../deck/deck.dart';
import '../../design/app_button.dart';
import '../../design/app_section_label.dart';
import '../../design/app_sheet.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'model.dart';
import 'sharing_service.dart';

/// Asks where to copy [deck]: into a new deck named after it (the default),
/// or into one of the user's decks with a duplicate option. Copies it and
/// returns the message saying what was added, or null when cancelled.
Future<String?> showCopySheet(
  BuildContext context, {
  required SharingService sharing,
  required PublicDeckSummary deck,
}) => showAppSheet<String>(
  context,
  builder: (_) => _CopySheet(sharing: sharing, deck: deck),
);

enum _Destination { newDeck, existingDeck }

class _CopySheet extends StatefulWidget {
  const _CopySheet({required this.sharing, required this.deck});

  final SharingService sharing;
  final PublicDeckSummary deck;

  @override
  State<_CopySheet> createState() => _CopySheetState();
}

class _CopySheetState extends State<_CopySheet> {
  late final Stream<List<Deck>> _decks = widget.sharing.decks.watchDecks();
  _Destination _destination = _Destination.newDeck;
  DeckId? _target;
  DuplicateChoice _onDuplicate = DuplicateChoice.skip;
  bool _saving = false;
  String? _error;

  Future<void> _save(AppLocalizations l10n, CopyTarget target) async {
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    String? done;
    final message = await describing(l10n, () async {
      final copied = await widget.sharing.copy(widget.deck, target);
      return done = l10n.copiedCards(
        copied.deck.name,
        copied.added + copied.merged,
      );
    });
    if (!mounted) return;
    if (done != null) {
      navigator.pop(done);
    } else {
      setState(() {
        _saving = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return StreamBuilder(
      stream: _decks,
      builder: (context, snapshot) {
        final decks = snapshot.data ?? const <Deck>[];
        // The chosen deck, while it still exists.
        final chosen = decks.any((deck) => deck.id == _target) ? _target : null;
        final target = switch ((_destination, chosen)) {
          (_Destination.newDeck, _) => const CopyIntoNewDeck(),
          (_Destination.existingDeck, final deck?) => CopyIntoDeck(
            deck,
            _onDuplicate,
          ),
          (_Destination.existingDeck, null) => null,
        };
        final error = _error;
        return AppSheet(
          title: l10n.copyToMyDecks,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpace.s12,
            children: [
              SegmentedButton<_Destination>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _Destination.newDeck,
                    label: Text(l10n.copyAsNewDeck),
                  ),
                  ButtonSegment(
                    value: _Destination.existingDeck,
                    label: Text(l10n.copyIntoExistingDeck),
                    enabled: decks.isNotEmpty,
                  ),
                ],
                selected: {_destination},
                onSelectionChanged: _saving
                    ? null
                    : (selected) =>
                          setState(() => _destination = selected.single),
              ),
              if (_destination == _Destination.newDeck)
                Text(
                  l10n.copyNewDeckHint(widget.deck.name),
                  style: AppType.secondary.copyWith(color: colors.muted),
                )
              else ...[
                DropdownMenu<DeckId>(
                  expandedInsets: EdgeInsets.zero,
                  label: Text(l10n.copyTargetDeck),
                  initialSelection: chosen,
                  enabled: !_saving,
                  onSelected: (deck) => setState(() => _target = deck),
                  dropdownMenuEntries: [
                    for (final deck in decks)
                      DropdownMenuEntry(value: deck.id, label: deck.name),
                  ],
                ),
                AppSectionLabel(l10n.copyDuplicates),
                RadioGroup<DuplicateChoice>(
                  groupValue: _onDuplicate,
                  onChanged: (choice) {
                    if (_saving || choice == null) return;
                    setState(() => _onDuplicate = choice);
                  },
                  child: Column(
                    children: [
                      for (final choice in DuplicateChoice.values)
                        RadioListTile<DuplicateChoice>(
                          value: choice,
                          contentPadding: EdgeInsets.zero,
                          title: Text(switch (choice) {
                            DuplicateChoice.skip => l10n.duplicateSkip,
                            DuplicateChoice.mergeBack =>
                              l10n.duplicateMergeBack,
                            DuplicateChoice.addNew => l10n.duplicateAddNew,
                          }, style: AppType.body),
                        ),
                    ],
                  ),
                ),
              ],
              if (error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: AppType.caption.copyWith(color: colors.dontKnowText),
                  ),
                ),
            ],
          ),
          actions: [
            AppButton(
              label: l10n.copyConfirm,
              size: AppButtonSize.cta,
              loading: _saving,
              onPressed: target == null ? null : () => _save(l10n, target),
            ),
          ],
        );
      },
    );
  }
}
