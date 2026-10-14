import 'failure.dart';

/// Where sync stands, as the account screen shows it.
sealed class SyncStatus {
  const SyncStatus();
}

/// No account is signed in, so nothing syncs.
final class SyncIdle extends SyncStatus {
  const SyncIdle();
}

/// A run is under way.
final class Syncing extends SyncStatus {
  const Syncing();
}

/// The last run finished.
final class Synced extends SyncStatus {
  const Synced();
}

/// The last run stopped with [failure]; another is scheduled.
final class SyncInterrupted extends SyncStatus {
  const SyncInterrupted(this.failure);

  final SyncFailure failure;
}
