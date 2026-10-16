import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'queue.dart';
import 'scheduler.dart';
import 'study_repository.dart';

/// The study repository. The composition site overrides it with the instance
/// it constructs.
final studyRepositoryProvider = Provider<StudyRepository>(
  (ref) => throw UnimplementedError(
    'studyRepositoryProvider is overridden at the composition site',
  ),
);

/// The engine scheduler. The composition site overrides it once the engine
/// has loaded.
final schedulerProvider = Provider<Scheduler>(
  (ref) => throw UnimplementedError(
    'schedulerProvider is overridden at the composition site',
  ),
);

/// The clock that times answers and decides what is due.
final studyClockProvider = Provider<DateTime Function()>(
  (ref) => throw UnimplementedError(
    'studyClockProvider is overridden at the composition site',
  ),
);

/// The time zone the study day is read in: the offset from UTC at an
/// instant.
final studyZoneProvider = Provider<UtcOffsetAt>(
  (ref) => throw UnimplementedError(
    'studyZoneProvider is overridden at the composition site',
  ),
);

/// The source of every random choice a session makes, given the time the
/// session starts.
final studyRandomProvider = Provider<Random Function(DateTime start)>(
  (ref) => throw UnimplementedError(
    'studyRandomProvider is overridden at the composition site',
  ),
);
