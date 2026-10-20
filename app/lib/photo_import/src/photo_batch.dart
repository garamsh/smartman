import 'dart:async';

import 'extraction_client.dart';
import 'failure.dart';
import 'photo.dart';

/// The most photos one import reads, the first pick and every later one
/// together.
const maxPhotosPerImport = 10;

/// The most photos read at once; the rest wait their turn.
const photosReadAtOnce = 2;

/// Where one photo of a batch stands.
sealed class PhotoState {
  const PhotoState();
}

/// Waiting for its turn, or for the photo to be prepared.
final class PhotoWaiting extends PhotoState {
  const PhotoWaiting();
}

/// Being read by `extract-cards`.
final class PhotoReading extends PhotoState {
  const PhotoReading();
}

/// Read, with the cards found on it.
final class PhotoRead extends PhotoState {
  const PhotoRead(this.cards);

  final List<CandidateCard> cards;
}

/// Not read, for [failure].
final class PhotoFailed extends PhotoState {
  const PhotoFailed(this.failure);

  final PhotoImportFailure failure;
}

/// One photo of a batch: the photo once it is prepared, and its state.
final class PhotoJob {
  PhotoJob(this._prepared);

  final Future<JpegPhoto> _prepared;

  /// The photo, once prepared; null until then, or when it cannot be read.
  JpegPhoto? photo;

  PhotoState state = const PhotoWaiting();

  Completer<void>? _cancel;
}

/// Photos read by [extract] at most [photosReadAtOnce] at a time, in the
/// order given. A photo that fails waits for [retry] or [drop]; the others
/// go on. [onChanged] is called after every change of state.
final class PhotoBatch {
  PhotoBatch(
    List<Future<JpegPhoto>> photos, {
    required this.extract,
    required this.onChanged,
  }) : jobs = [for (final photo in photos) PhotoJob(photo)];

  /// Reads one photo, or resolves to null when [cancel] completes first.
  final Future<List<CandidateCard>?> Function(
    JpegPhoto photo, {
    required Future<void> cancel,
  })
  extract;

  final void Function() onChanged;

  final List<PhotoJob> jobs;

  var _cancelled = false;

  /// Whether every photo is read: none waits, is being read, or has failed.
  bool get finished => jobs.every((job) => job.state is PhotoRead);

  int get reading => jobs.where((job) => job.state is PhotoReading).length;

  /// Starts reading as many waiting photos as the limit allows.
  void start() {
    for (final job in jobs) {
      if (_cancelled || reading >= photosReadAtOnce) return;
      if (job.state is PhotoWaiting && job._cancel == null) {
        unawaited(_run(job));
      }
    }
  }

  /// Reads [job] again after a failure.
  void retry(PhotoJob job) {
    job.state = const PhotoWaiting();
    onChanged();
    start();
  }

  /// Leaves [job] out of the import.
  void drop(PhotoJob job) {
    jobs.remove(job);
    job._cancel?.complete();
    onChanged();
    start();
  }

  /// Stops every read in progress and starts no other.
  void cancel() {
    _cancelled = true;
    for (final job in jobs) {
      final cancel = job._cancel;
      if (cancel != null && !cancel.isCompleted) cancel.complete();
    }
  }

  Future<void> _run(PhotoJob job) async {
    final cancel = job._cancel = Completer<void>();
    job.state = const PhotoReading();
    onChanged();
    PhotoState next;
    try {
      final photo = job.photo ??= await job._prepared;
      final cards = await extract(photo, cancel: cancel.future);
      if (cards == null) return;
      next = PhotoRead(cards);
    } on PhotoImportFailure catch (failure) {
      next = PhotoFailed(failure);
    } finally {
      job._cancel = null;
    }
    if (_cancelled || !jobs.contains(job)) return;
    job.state = next;
    onChanged();
    start();
  }
}
