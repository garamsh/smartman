import 'dart:async';

import 'package:flutter/painting.dart';
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

/// A small prepared photo [width] wide, which a call's photo is told apart
/// by.
JpegPhoto photoOfWidth(int width) =>
    downscalePhoto(img.encodePng(img.Image(width: width, height: 6)));

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

  /// How many picked photos were prepared, which a pick does only as each
  /// one's turn comes.
  int prepared = 0;

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
  Future<List<PickedPhoto>?> pickFromLibrary({int limit = 1}) async {
    libraryCalls++;
    libraryLimits.add(limit);
    if (libraryFailure case final failure?) throw failure;
    if (libraryPhotos case final photos?) {
      return [
        for (final photo in photos.take(limit))
          () {
            prepared++;
            return photo;
          },
      ];
    }
    return switch (libraryPhoto) {
      final photo? => [
        () async {
          prepared++;
          return photo;
        },
      ],
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
  PendingExtraction(this.photo, this.cancel, this.cursor);

  final JpegPhoto photo;
  final Future<void> cancel;

  /// The cursor the call read on from; null for a first read.
  final String? cursor;

  final answer = Completer<List<CandidateCard>?>();

  /// The cursor the answer carries, to read the page on from.
  String? nextCursor;

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

  /// The calls the function counts against the user's limit: those without
  /// a cursor (ADR 0138).
  int get usages => calls.where((call) => call.cursor == null).length;

  @override
  Future<Extracted?> extract(
    JpegPhoto photo, {
    String? cursor,
    required Future<void> cancel,
  }) {
    final call = PendingExtraction(photo, cancel, cursor);
    calls.add(call);
    unawaited(cancel.then((_) => call.cancelled = true));
    return call.answer.future.then(
      (cards) => cards == null ? null : (cards: cards, cursor: call.nextCursor),
    );
  }

  /// Answers the last call with vocabulary cards of one sense, front →
  /// meaning.
  void answer(Map<String, String> cards) => answerCards([
    for (final MapEntry(key: front, value: meaning) in cards.entries)
      word(front: front, meaning: meaning),
  ]);

  /// Answers the last call with [cards], and a [cursor] to read on from when
  /// the page was left unread past them.
  void answerCards(List<CandidateCard> cards, {String? cursor}) {
    calls.last.nextCursor = cursor;
    calls.last.answer.complete(cards);
  }

  /// Answers the last call with [failure].
  void fail(PhotoImportFailure failure) =>
      calls.last.answer.completeError(failure);
}

/// A photo import job's store in memory, for a test that reads what a job
/// kept, or restores it as a closed app's next open does. It fails as the
/// device's files do when asked, and can hold each write until the test
/// releases it.
final class MemoryImportJobStore implements ImportJobStore {
  final photos = <String, Uint8List>{};
  String? state;
  var _next = 0;

  /// From which photo, counted from 0 in the order kept, [putPhoto] fails, as
  /// on a full disk; none fails while null.
  int? refusePutsFrom;

  /// From which photo, counted from 0 in the order kept, [photo] fails, as
  /// when the kept files are gone; none fails while null.
  int? goneFrom;

  /// Whether [writeState] waits in [heldWrites] until a test releases it, so
  /// the test decides the order the writes finish in.
  bool holdWrites = false;

  /// The writes waiting, oldest first; each lands once its release completes.
  final heldWrites = <({String state, Completer<void> release})>[];

  @override
  Future<String> putPhoto(Uint8List jpeg) async {
    if (refusePutsFrom case final from? when _next >= from) {
      throw const PhotoNotKept('disk full');
    }
    final key = 'photo${_next++}';
    photos[key] = jpeg;
    return key;
  }

  @override
  Future<Uint8List> photo(String key) async {
    if (goneFrom case final from?
        when int.parse(key.substring('photo'.length)) >= from) {
      throw const PhotoNotKept('gone');
    }
    return photos[key] ?? (throw PhotoNotKept('No photo kept under $key.'));
  }

  @override
  ImageProvider image(String key, {int? width}) => ResizeImage.resizeIfNeeded(
    width,
    null,
    MemoryImage(photos[key] ?? (throw StateError('No photo kept under $key.'))),
  );

  @override
  Future<String?> readState() async => state;

  @override
  Future<void> writeState(String state) async {
    if (holdWrites) {
      final release = Completer<void>();
      heldWrites.add((state: state, release: release));
      await release.future;
    }
    this.state = state;
  }

  @override
  Future<void> clear() async {
    photos.clear();
    state = null;
  }
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
