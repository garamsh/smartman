/// A failure of photo import that the user is shown.
sealed class PhotoImportFailure implements Exception {
  const PhotoImportFailure();
}

/// The extraction service could not be reached.
final class ExtractionOffline extends PhotoImportFailure {
  const ExtractionOffline(this.cause);

  final Exception cause;

  @override
  String toString() => 'ExtractionOffline: $cause';
}

/// The service refused the photo as too large (`413`) or of a type it does
/// not read (`415`).
final class PhotoRefused extends PhotoImportFailure {
  const PhotoRefused(this.status);

  final int status;

  @override
  String toString() => 'PhotoRefused: HTTP $status';
}

/// The model found no card on the page (`422`).
final class NoCardsFound extends PhotoImportFailure {
  const NoCardsFound();

  @override
  String toString() => 'NoCardsFound';
}

/// The user has made today's extractions (`429`).
final class DailyLimitReached extends PhotoImportFailure {
  const DailyLimitReached();

  @override
  String toString() => 'DailyLimitReached';
}

/// The model failed or answered invalidly twice (`502`).
final class ModelFailed extends PhotoImportFailure {
  const ModelFailed();

  @override
  String toString() => 'ModelFailed';
}

/// No session, or one the service does not accept (`401`).
final class SignInRequired extends PhotoImportFailure {
  const SignInRequired();

  @override
  String toString() => 'SignInRequired';
}

/// The service answered with a status or body the contract does not give
/// this request: `400`, `405`, `500`, `503`, or an unreadable success.
final class ServiceFailed extends PhotoImportFailure {
  const ServiceFailed(this.reason);

  final String reason;

  @override
  String toString() => 'ServiceFailed: $reason';
}

/// The chosen file could not be decoded as an image.
final class PhotoUnreadable extends PhotoImportFailure {
  const PhotoUnreadable(this.cause);

  final Object cause;

  @override
  String toString() => 'PhotoUnreadable: $cause';
}

/// The user, or a restriction, has not let the app use the camera or the
/// photo library.
final class PhotoAccessDenied extends PhotoImportFailure {
  const PhotoAccessDenied(this.cause);

  final Object cause;

  @override
  String toString() => 'PhotoAccessDenied: $cause';
}

/// The device has no camera the system can open.
final class CameraUnavailable extends PhotoImportFailure {
  const CameraUnavailable(this.cause);

  final Object cause;

  @override
  String toString() => 'CameraUnavailable: $cause';
}
