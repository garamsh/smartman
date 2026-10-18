import '../../database/database.dart';
import 'failure.dart';
import 'model.dart';
import 'rust/api/engine.dart';
import 'rust/api/engine.dart' as engine show retrievability;
import 'rust/frb_generated.dart';

/// Schedules reviews with the Rust engine.
///
/// An engine refusal reaches the caller as [SchedulingFailure].
class Scheduler {
  const Scheduler._();

  /// Loads the engine library, unless it is loaded already; the returned
  /// scheduler is ready to call.
  static Future<Scheduler> load() async {
    if (!RustLib.instance.initialized) await RustLib.init();
    return const Scheduler._();
  }

  /// The state of a card in [state] (null for a new card) after [answer] at
  /// [at], its interval fuzzed by [fuzz]. The engine counts time in whole
  /// seconds, so [at] is truncated.
  Future<CardState> review(
    CardState? state,
    Answer answer,
    DateTime at, {
    required FuzzFactor fuzz,
  }) => _review(state, answer, at, fuzz.value);

  /// The state a new card reaches after its stored [reviews], taken in
  /// `reviewed_at` order, each scheduled with its own fuzz factor and a null
  /// factor as none; null when there are no reviews.
  Future<CardState?> fold(List<ReviewRow> reviews) async =>
      (await history(reviews)).lastOrNull;

  /// The states a new card passes through over its stored [reviews], one
  /// after each, taken in `reviewed_at` order as [fold] takes them.
  Future<List<CardState>> history(List<ReviewRow> reviews) async {
    final ordered = [...reviews]
      ..sort((a, b) => a.reviewedAt.compareTo(b.reviewedAt));
    final states = <CardState>[];
    for (final review in ordered) {
      states.add(
        await _review(
          states.lastOrNull,
          answerOf(review.rating),
          review.reviewedAt,
          review.fuzzFactor,
        ),
      );
    }
    return states;
  }

  /// The probability of recall at [at] of a card in [state]. The engine
  /// counts time in whole seconds, so [at] is truncated.
  Future<double> retrievability(CardState state, DateTime at) async {
    try {
      return await engine.retrievability(
        state: _parts(state),
        at: _toSeconds(at),
      );
    } on EngineError catch (cause, stackTrace) {
      Error.throwWithStackTrace(SchedulingFailure(cause), stackTrace);
    }
  }

  Future<CardState> _review(
    CardState? state,
    Answer answer,
    DateTime at,
    double? fuzz,
  ) async {
    final seconds = _toSeconds(at);
    try {
      final scheduled = state == null
          ? await reviewNewCard(answer: answer, at: seconds, fuzzFactor: fuzz)
          : await reviewCard(
              state: _parts(state),
              answer: answer,
              at: seconds,
              fuzzFactor: fuzz,
            );
      return CardState(
        stability: scheduled.state.stability,
        difficulty: scheduled.state.difficulty,
        lastReview: _fromSeconds(scheduled.state.lastReview),
        due: _fromSeconds(scheduled.due),
      );
    } on EngineError catch (cause, stackTrace) {
      Error.throwWithStackTrace(SchedulingFailure(cause), stackTrace);
    }
  }
}

MemoryStateParts _parts(CardState state) => MemoryStateParts(
  stability: state.stability,
  difficulty: state.difficulty,
  lastReview: _toSeconds(state.lastReview),
);

int _toSeconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

DateTime _fromSeconds(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
