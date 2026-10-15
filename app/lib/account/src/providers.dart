import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_service.dart';
import 'account_state.dart';

/// The account service. The composition site overrides it with the service
/// it connects.
final accountServiceProvider = Provider<AccountService>(
  (ref) => throw UnimplementedError(
    'accountServiceProvider is overridden at the composition site',
  ),
);

/// The app's version, as the platform reports it. The composition site
/// overrides it with the version it reads before the first frame.
final appVersionProvider = Provider<String>(
  (ref) => throw UnimplementedError(
    'appVersionProvider is overridden at the composition site',
  ),
);

/// The account state, kept current.
final accountStateProvider =
    NotifierProvider<AccountStateNotifier, AccountState>(
      AccountStateNotifier.new,
    );

/// Follows [AccountService.stateChanges] from the state it starts in.
class AccountStateNotifier extends Notifier<AccountState> {
  @override
  AccountState build() {
    final service = ref.watch(accountServiceProvider);
    // Subscribing before reading the state misses no change between the two.
    final subscription = service.stateChanges.listen((next) => state = next);
    ref.onDispose(subscription.cancel);
    return service.state;
  }
}
