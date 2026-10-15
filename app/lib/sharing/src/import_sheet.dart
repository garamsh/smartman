import 'package:flutter/material.dart';

import '../../deck/deck.dart';
import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import 'model.dart';
import 'sharing_service.dart';

/// Asks where to copy [deck]: into a new deck named after it (the default),
/// or into one of the user's decks with a duplicate option. Copies it and
/// returns the message saying what was added, or null when cancelled.
Future<String?> showImportSheet(
  BuildContext context, {
  required SharingService sharing,
  required PublicDeckSummary deck,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ImportSheet(sharing: sharing, deck: deck),
);

enum _Destination { newDeck, existingDeck }

class _ImportSheet extends StatefulWidget {
  const _ImportSheet({required this.sharing, required this.deck});

  final SharingService sharing;
  final PublicDeckSummary deck;

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  late final Stream<List<Deck>> _decks = widget.sharing.decks.watchDecks();
  _Destination _destination = _Destination.newDeck;
  DeckId? _target;
  DuplicateChoice _onDuplicate = DuplicateChoice.skip;
  bool _saving = false;
  String? _error;

  Future<void> _save(AppLocalizations l10n) async {
    final target = switch ((_destination, _target)) {
      (_Destination.newDeck, _) => const CopyIntoNewDeck(),
      (_Destination.existingDeck, final deck?) => CopyIntoDeck(
        deck,
        _onDuplicate,
      ),
      (_Destination.existingDeck, null) => null,
    };
    if (target == null) return;
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    String? done;
    final message = await describing(l10n, () async {
      final imported = await widget.sharing.copy(widget.deck, target);
      return done = l10n.copiedCards(
        imported.deck.name,
        imported.added + imported.merged,
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
    final textTheme = Theme.of(context).textTheme;
    final error = _error;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: StreamBuilder(
          stream: _decks,
          builder: (context, snapshot) {
            final decks = snapshot.data ?? const <Deck>[];
            // The chosen deck, while it still exists.
            final target = decks.any((deck) => deck.id == _target)
                ? _target
                : null;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.importToMyDecks,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SegmentedButton<_Destination>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: _Destination.newDeck,
                      label: Text(l10n.importAsNewDeck),
                    ),
                    ButtonSegment(
                      value: _Destination.existingDeck,
                      label: Text(l10n.importIntoExistingDeck),
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
                    l10n.importNewDeckHint(widget.deck.name),
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.of(context).muted,
                    ),
                  )
                else ...[
                  DropdownMenu<DeckId>(
                    expandedInsets: EdgeInsets.zero,
                    label: Text(l10n.importTargetDeck),
                    initialSelection: target,
                    enabled: !_saving,
                    onSelected: (deck) => setState(() => _target = deck),
                    dropdownMenuEntries: [
                      for (final deck in decks)
                        DropdownMenuEntry(value: deck.id, label: deck.name),
                    ],
                  ),
                  Text(l10n.importDuplicates, style: textTheme.titleSmall),
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
                            }),
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
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.of(context).dontKnowText,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed:
                      _saving ||
                          (_destination == _Destination.existingDeck &&
                              target == null)
                      ? null
                      : () => _save(l10n),
                  child: Text(l10n.importConfirm),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
