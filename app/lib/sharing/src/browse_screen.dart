import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'model.dart';
import 'public_deck_screen.dart';
import 'sharing_service.dart';

/// Other users' public decks, searchable by name and description and sorted
/// by newest or most copied; opens one for a preview.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.sharing});

  final SharingService sharing;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  /// How long typing pauses before the search runs.
  static const _searchDelay = Duration(milliseconds: 300);

  late final StreamSubscription<bool> _online;

  /// Whether the device is online; null until the first report.
  bool? _isOnline;
  String _search = '';
  BrowseSort _sort = BrowseSort.newest;
  Future<List<PublicDeckSummary>>? _decks;
  Timer? _typing;

  @override
  void initState() {
    super.initState();
    _online = widget.sharing.watchOnline().listen((online) {
      final cameOnline = online && _isOnline != true;
      setState(() => _isOnline = online);
      if (cameOnline) _load();
    });
  }

  @override
  void dispose() {
    _typing?.cancel();
    _online.cancel();
    super.dispose();
  }

  void _load() => setState(() {
    // The builder shows a failure, but subscribes only at the next frame.
    _decks = widget.sharing.listDecks(_search, _sort)..ignore();
  });

  void _onSearch(String search) {
    _typing?.cancel();
    _typing = Timer(_searchDelay, () {
      _search = search;
      _load();
    });
  }

  Future<void> _open(PublicDeckSummary deck) async {
    final blocked = await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => PublicDeckScreen(sharing: widget.sharing, deck: deck),
      ),
    );
    if (blocked == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Semantics(
              header: true,
              child: Text(
                l10n.browse,
                style: textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          TextField(
            onChanged: _onSearch,
            onSubmitted: (search) {
              _typing?.cancel();
              _search = search;
              _load();
            },
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l10n.searchPublicDecks,
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<BrowseSort>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: BrowseSort.newest,
                label: Text(l10n.sortNewest),
              ),
              ButtonSegment(
                value: BrowseSort.mostCopied,
                label: Text(l10n.sortMostCopied),
              ),
            ],
            selected: {_sort},
            onSelectionChanged: (selected) {
              _sort = selected.single;
              _load();
            },
          ),
          const SizedBox(height: 16),
          ..._results(l10n),
        ],
      ),
    );
  }

  List<Widget> _results(AppLocalizations l10n) {
    if (_isOnline == false) {
      return [_Message(l10n.browseOffline, icon: Icons.cloud_off)];
    }
    final decks = _decks;
    if (decks == null) return [_progress(l10n)];
    return [
      FutureBuilder(
        future: decks,
        builder: (context, snapshot) => switch (snapshot) {
          AsyncSnapshot(hasData: true, :final data?) when data.isEmpty =>
            _Message(
              _search.trim().isEmpty
                  ? l10n.noPublicDecks
                  : l10n.noPublicMatches,
            ),
          AsyncSnapshot(hasData: true, :final data?) => Column(
            children: [
              for (final deck in data)
                _DeckRow(deck: deck, onTap: () => _open(deck)),
            ],
          ),
          AsyncSnapshot(:final error?, :final stackTrace) => _Message(
            switch (error) {
              SharingFailure() => describeSharingFailure(l10n, error),
              _ => Error.throwWithStackTrace(
                error,
                stackTrace ?? StackTrace.current,
              ),
            },
            icon: error is SharingOffline ? Icons.cloud_off : null,
            onRetry: _load,
          ),
          _ => _progress(l10n),
        },
      ),
    ];
  }

  Widget _progress(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Center(
      child: CircularProgressIndicator(semanticsLabel: l10n.loading),
    ),
  );
}

/// A public deck: its name, its owner's display name, and its card and copy
/// counts.
class _DeckRow extends StatelessWidget {
  const _DeckRow({required this.deck, required this.onTap});

  final PublicDeckSummary deck;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MergeSemantics(
        child: Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.row),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.row),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                spacing: 12,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          deck.name,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          l10n.publicDeckLine(
                            deck.ownerName.value,
                            deck.cardCount,
                            deck.importCount,
                          ),
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colors.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A state in place of the list: what happened, and a retry when [onRetry]
/// is given.
class _Message extends StatelessWidget {
  const _Message(this.text, {this.icon, this.onRetry});

  final String text;
  final IconData? icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final onRetry = this.onRetry;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        spacing: 12,
        children: [
          if (icon != null) Icon(icon, color: AppColors.of(context).muted),
          Text(text, textAlign: TextAlign.center),
          if (onRetry != null)
            OutlinedButton(
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context).retry),
            ),
        ],
      ),
    );
  }
}
