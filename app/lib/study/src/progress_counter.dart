import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../deck/deck.dart' show DeckSelection, deckRepositoryProvider;
import 'overview.dart';
import 'providers.dart';
import 'queue.dart';

/// Builds what the caller shows of a selection's [DeckProgress], null while it
/// is read or when it cannot be.
typedef ProgressBuilder = Widget Function(
  BuildContext context,
  DeckProgress? progress,
);

/// Counts how many of [decks]' cards are mastered, learning and new, and
/// shows the count through [builder].
///
/// The count is read again when [decks] changes and whenever the route that
/// shows it comes back on top, as [TodayCounter]'s is.
class ProgressCounter extends ConsumerStatefulWidget {
  const ProgressCounter({
    super.key,
    required this.decks,
    required this.builder,
  });

  final DeckSelection decks;
  final ProgressBuilder builder;

  @override
  ConsumerState<ProgressCounter> createState() => _ProgressCounterState();
}

class _ProgressCounterState extends ConsumerState<ProgressCounter> {
  late Future<DeckProgress> _progress = _read();
  bool _onTop = true;

  Future<DeckProgress> _read() async {
    final (cards, states) = await readCards(
      widget.decks,
      ref.read(deckRepositoryProvider),
      ref.read(studyRepositoryProvider),
    );
    return DeckProgress.of(cards, states);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final onTop = ModalRoute.isCurrentOf(context) ?? true;
    if (onTop && !_onTop) _progress = _read();
    _onTop = onTop;
  }

  @override
  void didUpdateWidget(ProgressCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!setEquals(oldWidget.decks.ids, widget.decks.ids)) _progress = _read();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _progress,
    builder: (context, progress) => widget.builder(context, progress.data),
  );
}
