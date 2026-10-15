import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/deck/src/deck_list_screen.dart';

void main() {
  test('a deck takes the same tint every time, and four decks spread over the four', () {
    // web/src/features/decks/__tests__/deck-tint.test.ts expects the same
    // indexes for the same ids, so a deck looks alike on both clients.
    final indexes = [
      for (final id in [
        '00000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-000000000002',
        '00000000-0000-4000-8000-000000000003',
        '00000000-0000-4000-8000-000000000004',
      ])
        deckTintIndex(DeckId(id), 4),
    ];

    expect(indexes, [1, 2, 3, 0]);
    expect(
      deckTintIndex(const DeckId('00000000-0000-4000-8000-000000000001'), 4),
      indexes.first,
    );
  });
}
