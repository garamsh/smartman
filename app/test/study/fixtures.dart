import 'package:smartman/deck/deck.dart';
import 'package:smartman/study/src/model.dart';

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
