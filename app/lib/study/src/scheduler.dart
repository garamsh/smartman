import 'failure.dart';
import 'model.dart';
import 'rust/api/engine.dart';
import 'rust/frb_generated.dart';

/// Schedules reviews with the Rust engine.
///
/// An engine refusal reaches the caller as [SchedulingFailure].
class Scheduler {
  const Scheduler._();

  /// Loads the engine library; the returned scheduler is ready to call.
  static Future<Scheduler> load() async {
    await RustLib.init();
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
  }) async {
    final seconds = _toSeconds(at);
    try {
      final scheduled = state == null
          ? await reviewNewCard(
              answer: answer,
              at: seconds,
              fuzzFactor: fuzz.value,
            )
          : await reviewCard(
              state: MemoryStateParts(
                stability: state.stability,
                difficulty: state.difficulty,
                lastReview: _toSeconds(state.lastReview),
              ),
              answer: answer,
              at: seconds,
              fuzzFactor: fuzz.value,
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

int _toSeconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

DateTime _fromSeconds(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
