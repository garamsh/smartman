/// An expected failure of the media domain.
sealed class MediaFailure implements Exception {
  const MediaFailure(this.cause);

  final Object cause;
}

/// The server could not be reached, did not answer in time, or refused the
/// request. A transfer that fails so is retried on the next run.
final class MediaTransferFailed extends MediaFailure {
  const MediaTransferFailed(super.cause);

  @override
  String toString() => 'MediaTransferFailed: $cause';
}

/// The picked image could not be read, or the camera or the photo library
/// could not be opened.
final class MediaUnreadable extends MediaFailure {
  const MediaUnreadable(super.cause);

  @override
  String toString() => 'MediaUnreadable: $cause';
}
