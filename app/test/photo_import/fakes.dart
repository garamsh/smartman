import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smartman/design/theme_choice.dart';
import 'package:smartman/photo_import/photo_import.dart';
import 'package:smartman/photo_import/src/photo.dart';

/// A small prepared photo.
final testPhoto = downscalePhoto(img.encodePng(img.Image(width: 8, height: 6)));

/// A system camera and a library that hand over [testPhoto], or fail as
/// told, and a settings page that opens as told.
final class FakePhotoSource implements PhotoSource {
  /// What the camera returns; null is a cancelled shot.
  JpegPhoto? cameraPhoto = testPhoto;

  /// Thrown by [takePhoto] instead of returning, when set.
  PhotoImportFailure? cameraFailure;

  /// What the library returns; null is a cancelled pick.
  JpegPhoto? libraryPhoto = testPhoto;

  /// Thrown by [pickFromLibrary] instead of returning, when set.
  PhotoImportFailure? libraryFailure;

  /// What [openSettings] resolves to.
  bool settingsOpen = true;

  int cameraCalls = 0;
  int libraryCalls = 0;
  int settingsCalls = 0;

  @override
  Future<JpegPhoto?> takePhoto() async {
    cameraCalls++;
    if (cameraFailure case final failure?) throw failure;
    return cameraPhoto;
  }

  @override
  Future<JpegPhoto?> pickFromLibrary() async {
    libraryCalls++;
    if (libraryFailure case final failure?) throw failure;
    return libraryPhoto;
  }

  @override
  Future<bool> openSettings() async {
    settingsCalls++;
    return settingsOpen;
  }
}

/// One extraction the test answers.
final class PendingExtraction {
  PendingExtraction(this.photo, this.cancel);

  final JpegPhoto photo;
  final Future<void> cancel;
  final answer = Completer<List<CandidateCard>?>();

  bool cancelled = false;
}

/// An extraction client whose every call waits for the test to answer it.
final class FakeExtractionClient implements ExtractionClient {
  final calls = <PendingExtraction>[];

  @override
  Future<List<CandidateCard>?> extract(
    JpegPhoto photo, {
    required Future<void> cancel,
  }) {
    final call = PendingExtraction(photo, cancel);
    calls.add(call);
    unawaited(cancel.then((_) => call.cancelled = true));
    return call.answer.future;
  }

  /// Answers the last call with vocabulary cards at step 1, front → answer.
  void answer(Map<String, String> cards) => answerCards([
    for (final MapEntry(key: front, value: answer) in cards.entries)
      CandidateCard(front: front, answer: answer),
  ]);

  /// Answers the last call with [cards].
  void answerCards(List<CandidateCard> cards) =>
      calls.last.answer.complete(cards);

  /// Answers the last call with [failure].
  void fail(PhotoImportFailure failure) =>
      calls.last.answer.completeError(failure);
}

/// Device storage over memory, opened as the composition site opens it,
/// holding [values].
Future<SharedPreferencesWithCache> openPreferences(
  WidgetTester tester, [
  Map<String, Object> values = const {},
]) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(values);
  return (await tester.runAsync(
    () => SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: {...themeStorageKeys, ...photoImportStorageKeys},
      ),
    ),
  ))!;
}
