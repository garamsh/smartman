import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smartman/deck/deck.dart'
    show CardSense, OtherLabel, PartOfSpeech, PartOfSpeechLabel;
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

  /// What a pick of several returns in place of [libraryPhoto], each a
  /// photo or its failure; null picks [libraryPhoto] alone.
  List<Future<JpegPhoto>>? libraryPhotos;

  /// The limit of each library pick, in order.
  final libraryLimits = <int>[];

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
  Future<List<Future<JpegPhoto>>?> pickFromLibrary({int limit = 1}) async {
    libraryCalls++;
    libraryLimits.add(limit);
    if (libraryFailure case final failure?) throw failure;
    if (libraryPhotos case final photos?) return photos.take(limit).toList();
    return switch (libraryPhoto) {
      final photo? => [Future.value(photo)],
      null => null,
    };
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

  /// What [allowance] resolves to; null is one that cannot be read.
  ExtractionAllowance? todayAllowance;

  @override
  Future<ExtractionAllowance?> allowance() async => todayAllowance;

  /// The calls not yet answered or cancelled.
  Iterable<PendingExtraction> get open =>
      calls.where((call) => !call.answer.isCompleted && !call.cancelled);

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

  /// Answers the last call with vocabulary cards of one sense, front →
  /// meaning.
  void answer(Map<String, String> cards) => answerCards([
    for (final MapEntry(key: front, value: meaning) in cards.entries)
      word(front: front, meaning: meaning),
  ]);

  /// Answers the last call with [cards].
  void answerCards(List<CandidateCard> cards) =>
      calls.last.answer.complete(cards);

  /// Answers the last call with [failure].
  void fail(PhotoImportFailure failure) =>
      calls.last.answer.completeError(failure);
}

/// Device storage over memory that refuses every write, as a full disk does.
base class _RefusingPreferences extends InMemorySharedPreferencesAsync {
  _RefusingPreferences() : super.empty();

  @override
  Future<bool> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) => Future.error(PlatformException(code: 'full'));
}

/// Device storage over memory, opened as the composition site opens it,
/// holding [values]; with [refuseWrites], every write fails.
Future<SharedPreferencesWithCache> openPreferences(
  WidgetTester tester, [
  Map<String, Object> values = const {},
  bool refuseWrites = false,
]) async {
  SharedPreferencesAsyncPlatform.instance = refuseWrites
      ? _RefusingPreferences()
      : InMemorySharedPreferencesAsync.withData(values);
  return (await tester.runAsync(
    () => SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: {...themeStorageKeys, ...photoImportStorageKeys},
      ),
    ),
  ))!;
}

/// A vocabulary card of one sense, [meaning], under [partOfSpeech] when given,
/// such as `[동]`, in [topic].
CandidateCard word({
  required String front,
  required String meaning,
  String? partOfSpeech,
  String topic = 'Page',
}) {
  final label = partOfSpeech?.replaceAll(RegExp(r'^\[|\]$'), '');
  final category = PartOfSpeech.values
      .where((part) => part.short == label)
      .firstOrNull;
  return CandidateCard(
    front: front,
    answer: meaning,
    topic: topic,
    kind: CardKind.vocabulary,
    senses: [
      CardSense(
        labels: [
          if (category != null)
            PartOfSpeechLabel(category, label!)
          else if (label != null)
            OtherLabel(label),
        ],
        meaning: meaning,
      ),
    ],
  );
}
