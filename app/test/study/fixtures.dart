import 'dart:async';
import 'dart:math';

import 'package:smartman/deck/deck.dart';
import 'package:smartman/study/src/model.dart';
import 'package:smartman/study/src/queue.dart';
import 'package:smartman/study/src/session.dart';

/// A text card named [name] created at [createdAt]; its front reads
/// "[name] front" and its back "[name] back".
Card textCard(String name, {required DateTime createdAt}) => Card(
  id: CardId(name),
  deckId: const DeckId('deck'),
  front: [TextContent('$name front')],
  back: [TextContent('$name back')],
  cardKey: CardKey.fromFront('$name front'),
  source: CardSource.manual,
  createdAt: createdAt,
  updatedAt: createdAt,
);

/// A reviewed card's state, due at [due].
CardState dueAt(DateTime due) => CardState(
  stability: 3,
  difficulty: 5,
  lastReview: due.subtract(const Duration(days: 3)),
  due: due,
);

/// Completes once [session] has read its queue.
Future<void> untilLoaded(StudySession session) {
  final loaded = Completer<void>();
  void check() {
    if (session.state is! SessionLoading && !loaded.isCompleted) {
      loaded.complete();
    }
  }

  session.addListener(check);
  check();
  return loaded.future.whenComplete(() => session.removeListener(check));
}

/// Draws 0 every time, so a session keeps its queue in the order selected and
/// puts a card back after [reshowGapMin] other cards.
class FirstDraw implements Random {
  @override
  int nextInt(int max) => 0;

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
}
