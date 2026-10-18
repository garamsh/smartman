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
  return {for (final (index, id) in ids.indexed) id: list[index]};
}

int _seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;
