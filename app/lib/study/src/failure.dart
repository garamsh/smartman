import 'rust/api/engine.dart';

/// A failure the study domain reports to its caller.
sealed class StudyFailure implements Exception {
  const StudyFailure();
}

/// The local database failed while reading scheduling state.
final class StudyStorageFailure extends StudyFailure {
  const StudyStorageFailure(this.cause);

  final Exception cause;

  @override
  String toString() => 'StudyStorageFailure: $cause';
}

/// The local database failed to store an answer; the card's stored state is
/// unchanged.
final class AnswerNotSaved extends StudyFailure {
  const AnswerNotSaved(this.cause);

  final Exception cause;

  @override
  String toString() => 'AnswerNotSaved: $cause';
}

/// The local database failed to store the daily study minutes; the stored
/// setting is unchanged.
final class SettingNotSaved extends StudyFailure {
  const SettingNotSaved(this.cause);

  final Exception cause;

  @override
  String toString() => 'SettingNotSaved: $cause';
}

/// The engine refused to schedule a review.
final class SchedulingFailure extends StudyFailure {
  const SchedulingFailure(this.cause);

  final EngineError cause;

  @override
  String toString() => 'SchedulingFailure: $cause';
}
