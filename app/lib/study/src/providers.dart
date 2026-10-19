import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// The device storage that keeps whether the study screen's coach and the
/// first-run daily minutes step have shown. The composition site overrides it
/// with the storage it opens, opened to cache [studyStorageKeys].
final studyStorageProvider = Provider<SharedPreferencesWithCache>(
  (ref) => throw UnimplementedError(
    'studyStorageProvider is overridden at the composition site',
  ),
);

/// The keys [studyStorageProvider] must be opened to cache.
const studyStorageKeys = {studyCoachShownKey, dailyMinutesAskedKey};

/// Set once the study screen's coach has shown on this device.
const studyCoachShownKey = 'studyCoachShown';

/// Set once the first-run step that asks for the daily study minutes has
/// shown on this device.
const dailyMinutesAskedKey = 'dailyMinutesAsked';
