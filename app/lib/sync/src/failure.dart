/// A failure of a sync run. None blocks the user: sync retries it with
/// backoff, and the account screen shows it.
sealed class SyncFailure implements Exception {
  const SyncFailure();
}

/// The server could not be reached, or did not answer in time.
final class SyncOffline extends SyncFailure {
  const SyncOffline(this.cause);

  final Object cause;

  @override
  String toString() => 'SyncOffline: $cause';
}

/// The server refused the request: the session is no longer valid, or a row
/// is not the signed-in account's.
final class SyncRejected extends SyncFailure {
  const SyncRejected(this.cause);

  final Exception cause;

  @override
  String toString() => 'SyncRejected: $cause';
}

/// The server answered with something sync cannot apply, or the local
/// database failed.
final class SyncFailed extends SyncFailure {
  const SyncFailed(this.cause);

  final Exception cause;

  @override
  String toString() => 'SyncFailed: $cause';
}
