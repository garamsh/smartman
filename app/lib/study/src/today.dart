import '../../deck/deck.dart';
import 'model.dart';
import 'queue.dart';
import 'rust/api/engine.dart';

/// An answer as today's list reads it.
typedef DayAnswer = ({CardId card, Answer answer, DateTime at});

/// Where each of [cards] stands in [day]'s list, through the engine's `today`
/// (`engine.md`): from the due time of its stored state in [states], none for
/// a card never reviewed, and its [answers] of the day, in any order.
///
/// A card is [Today.left] when its latest answer in the day is "Don't know",
/// or when it has none and falls due before the day ends; [Today.done] when
/// its latest answer in the day is "Know"; otherwise [Today.absent]. The
/// engine counts time in whole seconds, so each time is truncated.
Map<CardId, Today> todayOf(
  Iterable<CardId> cards,
  Map<CardId, CardState> states,
  Iterable<DayAnswer> answers,
  StudyDay day,
) {
  final ids = cards.toList();
  final reviews = <CardId, List<ReviewRecord>>{};
  for (final answer in answers) {
    (reviews[answer.card] ??= []).add(
      ReviewRecord(answer: answer.answer, at: _seconds(answer.at)),
    );
  }
  final list = todaysList(
    cards: [
      for (final id in ids)
        TodayCard(
          due: switch (states[id]) {
            final state? => _seconds(state.due),
            null => null,
          },
          reviews: reviews[id] ?? const [],
        ),
    ],
    dayStart: _seconds(day.start),
    dayEnd: _seconds(day.end),
  );
  if (list.length != ids.length) {
    throw StateError(
      "today's list placed ${list.length} cards of the ${ids.length} given",
    );
  }
  return {for (final (index, id) in ids.indexed) id: list[index]};
}

int _seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

/// A study day over a selection of decks, as today's list places its cards:
/// the queue the rules select, the cards still on "Don't know" that the rules
/// did not select, and the cards done. The session, `TodayCounter` and the 오늘
/// tab's daily goal all count from it, so they agree.
final class DayPlan {
  const DayPlan({
    required this.selected,
    required this.relearn,
    required this.done,
  });

  /// What the queue rules select ([selectQueue]).
  final SelectedQueue selected;

  /// The cards today's list keeps left that the rules did not select: those
  /// answered "Don't know" last today, which their state no longer makes due.
  final List<Card> relearn;

  /// The cards answered "Know" last today.
  final Set<CardId> done;

  /// The cards left today: the selection and those still on "Don't know".
  int get left => selected.cards.length + relearn.length;
}

/// The [DayPlan] of [day] over [cards], from their stored [states] and the
/// [answers] given to them in it.
DayPlan dayPlanOf(
  List<Card> cards,
  Map<CardId, CardState> states,
  StudyDay day,
  Iterable<DayAnswer> answers,
) {
  final places = todayOf(
    [for (final card in cards) card.id],
    states,
    answers,
    day,
  );
  final selected = selectQueue(cards, states, day);
  final chosen = {for (final card in selected.cards) card.id};
  return DayPlan(
    selected: selected,
    relearn: [
      for (final card in cards)
        if (places[card.id] == Today.left && !chosen.contains(card.id)) card,
    ],
    done: {
      for (final MapEntry(:key, :value) in places.entries)
        if (value == Today.done) key,
    },
  );
}
