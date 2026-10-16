import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The signed-in account's data on this device, which sign-out sends to the
/// server and then removes. The composition site overrides
/// [accountDataProvider] with the sync domain's, so this domain does not
/// depend on it.
abstract interface class AccountData {
  /// Sends every unsynced change to the server; whether all of them arrived.
  Future<bool> push();

  /// Removes the account's data from this device. Throws
  /// [AccountDataNotCleared] when the local database fails.
  Future<void> clear();
}

/// The device's data could not be removed after sign-out. Sync never pushes
/// it to another account: it clears it before that account's first pull.
final class AccountDataNotCleared implements Exception {
  const AccountDataNotCleared(this.cause);

  final Exception cause;

  @override
  String toString() => 'AccountDataNotCleared: $cause';
}

/// The account's data on this device; overridden at the composition site.
final accountDataProvider = Provider<AccountData>(
  (ref) => throw UnimplementedError(
    'accountDataProvider is overridden at the composition site',
  ),
);
