import 'failure.dart';

/// The id Supabase Auth gives an account, which owns its rows on the server.
extension type const UserId(String value) {}

/// Whether the user is signed in, as the account domain knows it.
sealed class AccountState {
  const AccountState();
}

/// No account is signed in.
final class SignedOut extends AccountState {
  const SignedOut();
}

/// An account is signed in. [email] is null for an account without one.
final class SignedIn extends AccountState {
  const SignedIn({required this.userId, required this.email});

  final UserId userId;
  final String? email;
}

/// Signing in cannot work in this build, for the reason [failure] gives.
final class AccountUnavailable extends AccountState {
  const AccountUnavailable(this.failure);

  final AccountMisconfigured failure;
}
