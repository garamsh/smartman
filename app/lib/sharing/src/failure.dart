/// A failure of sharing that the user is shown.
sealed class SharingFailure implements Exception {
  const SharingFailure();
}

/// The server could not be reached, or did not answer in time.
final class SharingOffline extends SharingFailure {
  const SharingOffline(this.cause);

  final Object cause;

  @override
  String toString() => 'SharingOffline: $cause';
}

/// The server refused the request: the session is no longer valid, or a
/// row-level security policy refused it.
final class SharingRejected extends SharingFailure {
  const SharingRejected(this.cause);

  final Exception cause;

  @override
  String toString() => 'SharingRejected: $cause';
}

/// The server answered with something the app cannot read, or a constraint
/// it refused.
final class SharingFailed extends SharingFailure {
  const SharingFailed(this.cause);

  final Exception cause;

  @override
  String toString() => 'SharingFailed: $cause';
}

/// The deck is no longer public: its owner made it private or deleted it, or
/// it was hidden after reports.
final class DeckNoLongerPublic extends SharingFailure {
  const DeckNoLongerPublic();

  @override
  String toString() => 'DeckNoLongerPublic';
}
