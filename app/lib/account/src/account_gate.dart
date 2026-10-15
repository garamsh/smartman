import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_state.dart';
import 'providers.dart';
import 'sign_in_screen.dart';

/// Builds the app the gate opens while an account is signed in; the
/// composition site overrides it, so this domain does not depend on the
/// domains behind it.
final signedInHomeProvider = Provider<Widget Function()>(
  (ref) => throw UnimplementedError(
    'signedInHomeProvider is overridden at the composition site',
  ),
);

/// The app's root: the sign-in screen until an account is signed in, then the
/// app. It shows whichever state the account is in now, so a restored session
/// opens the app without waiting on the network.
class AccountGate extends ConsumerWidget {
  const AccountGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(accountStateProvider, (previous, next) {
      // Every screen opened over the app leaves with the account.
      if (previous is SignedIn && next is! SignedIn) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    return switch (ref.watch(accountStateProvider)) {
      SignedIn() => ref.watch(signedInHomeProvider)(),
      SignedOut() || AccountUnavailable() => const SignInScreen(),
    };
  }
}
