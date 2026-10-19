import '../../l10n/app_localizations.dart';
import 'failure.dart';

/// The message a user reads for [failure].
String describePhotoImportFailure(
  AppLocalizations l10n,
  PhotoImportFailure failure,
) => switch (failure) {
  ExtractionOffline() => l10n.extractionOffline,
  PhotoRefused() => l10n.photoRefused,
  NoCardsFound() => l10n.noCardsFound,
  AccountSuspendedFailure() => l10n.accountSuspended,
  DailyLimitReached(:final dailyLimit) => l10n.dailyLimitReachedOf(dailyLimit),
  ModelFailed() => l10n.modelFailed,
  SignInRequired() => l10n.signInRequired,
  ServiceFailed() => l10n.serviceFailed,
  PhotoUnreadable() => l10n.photoUnreadable,
  PhotoAccessDenied() => l10n.photoAccessDenied,
  CameraUnavailable() => l10n.cameraUnavailable,
};

/// Whether sending the same photo again can succeed.
bool isRetryable(PhotoImportFailure failure) => switch (failure) {
  ExtractionOffline() || ModelFailed() || ServiceFailed() => true,
  PhotoRefused() ||
  NoCardsFound() ||
  DailyLimitReached() ||
  AccountSuspendedFailure() ||
  SignInRequired() ||
  PhotoUnreadable() ||
  PhotoAccessDenied() ||
  CameraUnavailable() => false,
};

/// Whether a new photo can succeed where this one failed.
bool isRetakeable(PhotoImportFailure failure) => switch (failure) {
  DailyLimitReached() || SignInRequired() || AccountSuspendedFailure() => false,
  ExtractionOffline() ||
  ModelFailed() ||
  ServiceFailed() ||
  PhotoRefused() ||
  NoCardsFound() ||
  PhotoUnreadable() ||
  PhotoAccessDenied() ||
  CameraUnavailable() => true,
};
