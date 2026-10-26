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

/// The picked image or audio could not be read, or the camera, the photo
/// library, the file picker or the recorder could not be opened.
final class MediaUnreadable extends MediaFailure {
  const MediaUnreadable(super.cause);

  @override
  String toString() => 'MediaUnreadable: $cause';
}

/// The picked audio plays longer, or holds more bytes, than a stored audio
/// file may (ADR 0112).
final class MediaTooLarge extends MediaFailure {
  const MediaTooLarge(super.cause);

  @override
  String toString() => 'MediaTooLarge: $cause';
}

/// The user has not let the app use the microphone.
final class MicrophoneDenied extends MediaFailure {
  const MicrophoneDenied(super.cause);

  @override
  String toString() => 'MicrophoneDenied: $cause';
}
