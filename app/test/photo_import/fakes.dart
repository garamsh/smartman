import 'dart:async';

import 'package:flutter/widgets.dart';
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

/// A camera and a library that hand over [testPhoto], or fail as told.
final class FakePhotoSource implements PhotoSource {
  /// Thrown by [openCamera] instead of opening, when set.
  PhotoImportFailure? cameraFailure;

  /// What the library returns; null is a cancelled pick.
  JpegPhoto? libraryPhoto = testPhoto;

  /// Thrown by [pickFromLibrary] instead of returning, when set.
  PhotoImportFailure? libraryFailure;

  /// When set, each [openCamera] waits until [finishOpen] lets it finish.
  bool holdOpens = false;
  final _held = <Completer<void>>[];

  /// Calls to [openCamera], including those that fail or are held.
  int openCalls = 0;
  int opened = 0;
  int closed = 0;

  @override
  Future<CameraSession> openCamera() async {
    openCalls++;
    if (holdOpens) {
      final held = Completer<void>();
      _held.add(held);
      await held.future;
    }
    if (cameraFailure case final failure?) throw failure;
    opened++;
    return _FakeCamera(this);
  }

  /// Lets the oldest held open finish; it fails if [cameraFailure] is set.
  void finishOpen() => _held.removeAt(0).complete();

  @override
  Future<JpegPhoto?> pickFromLibrary() async {
    if (libraryFailure case final failure?) throw failure;
    return libraryPhoto;
  }
}

final class _FakeCamera implements CameraSession {
  _FakeCamera(this._source);

  final FakePhotoSource _source;

  @override
  Widget get preview =>
      const SizedBox(key: Key('camera preview'), width: 300, height: 400);

  @override
  Future<JpegPhoto> takePicture() async => testPhoto;

  @override
  Future<void> close() async => _source.closed++;
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

  /// Answers the last call with cards, front → meaning.
  void answer(Map<String, String> cards) => answerCards([
    for (final MapEntry(key: front, value: meaning) in cards.entries)
      CandidateCard(front: front, meaning: meaning),
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
        allowList: {...themeStorageKeys, ...detailLevelStorageKeys},
      ),
    ),
  ))!;
}
