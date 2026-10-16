import 'package:supabase_flutter/supabase_flutter.dart';

/// Runs [step] until it completes within [bound] in all, trying again while
/// the auth server answers that the request may be retried. [step] is told
/// whether an earlier attempt failed.
Future<T> withinBound<T>(
  Duration bound,
  Future<T> Function(bool retry) step,
) async {
  final elapsed = Stopwatch()..start();
  for (var retry = false; ; retry = true) {
    try {
      return await step(retry).timeout(bound - elapsed.elapsed);
    } on AuthRetryableFetchException {
      if (elapsed.elapsed >= bound) rethrow;
    }
  }
}

/// Signs [client] up as a new account with [email] within [bound].
Future<AuthResponse> signUpWithinBound(
  SupabaseClient client,
  String email,
  String password,
  Duration bound,
) =>
    // A timed-out sign-up may have created the account, so a retry signs in.
    withinBound(
      bound,
      (retry) => retry
          ? _signInOrUp(client, email, password)
          : client.auth.signUp(email: email, password: password),
    );

/// Signs [client] in to [email]'s account, creating it if no account has it.
Future<AuthResponse> _signInOrUp(
  SupabaseClient client,
  String email,
  String password,
) async {
  try {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  } on AuthApiException catch (error) {
    if (error.code != 'invalid_credentials') rethrow;
    return client.auth.signUp(email: email, password: password);
  }
}
