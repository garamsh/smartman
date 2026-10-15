import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
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

  int opened = 0;
  int closed = 0;

  @override
  Future<CameraSession> openCamera() async {
    if (cameraFailure case final failure?) throw failure;
    opened++;
    return _FakeCamera(this);
  }

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

  /// Answers the last call with cards, front → back.
  void answer(Map<String, String> cards) => calls.last.answer.complete([
    for (final MapEntry(key: front, value: back) in cards.entries)
      CandidateCard(front: front, back: back),
  ]);

  /// Answers the last call with [failure].
  void fail(PhotoImportFailure failure) =>
      calls.last.answer.completeError(failure);
}
