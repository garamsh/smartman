import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_state.dart';
import 'config.dart';
import 'failure.dart';

/// Signs the user in and out, and reports whether they are signed in.
abstract interface class AccountService {
  /// The state now.
  AccountState get state;

  /// Every later change of [state].
  Stream<AccountState> get stateChanges;

  /// Opens the platform's Google account picker and starts a session for the
  /// account chosen. Returns normally, signed in or not, when the user cancels
  /// the picker; throws an [AccountFailure] otherwise.
  Future<void> signIn();

  /// Ends the session on this device, then tells the server. Throws an
  /// [AccountFailure] when the server cannot be told; the device is signed
  /// out either way.
  Future<void> signOut();
}

/// Connects to Supabase and Google with the configuration [defines] holds,
/// restoring the session a previous run stored. With a missing or malformed
/// configuration, the service it returns is [AccountUnavailable].
Future<AccountService> connectAccount(Map<String, String> defines) async {
  final AccountConfig config;
  try {
    config = AccountConfig.parse(defines);
  } on InvalidAccountConfig catch (error) {
    return UnavailableAccountService(AccountMisconfigured(error));
  }
  final supabase = await Supabase.initialize(
    url: config.supabaseUrl.toString(),
    publishableKey: config.publishableKey,
    // The browser OAuth flow is not used, so no deep link carries a session.
    authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
  );
  await GoogleSignIn.instance.initialize(
    // Android takes only the server client ID; iOS also needs its own.
    clientId: defaultTargetPlatform == TargetPlatform.iOS
        ? config.googleIosClientId.value
        : null,
    serverClientId: config.googleWebClientId.value,
  );
  return GoogleAccountService(supabase.client.auth, GoogleSignIn.instance);
}

/// Signs in with Google's native picker and exchanges the ID token it returns
/// for a Supabase session.
final class GoogleAccountService implements AccountService {
  GoogleAccountService(this._auth, this._google);

  final GoTrueClient _auth;
  final GoogleSignIn _google;

  static const _scopes = ['email', 'profile'];

  @override
  AccountState get state => _stateOf(_auth.currentSession);

  @override
  Stream<AccountState> get stateChanges => _auth.onAuthStateChange
      .map((change) => _stateOf(change.session))
      .handleError(_reportRefreshError);

  /// Reports a failed background refresh, which the stream carries as an
  /// error. One that could not reach the server is left out: the client keeps
  /// the session and retries it, so an offline device stays signed in.
  static void _reportRefreshError(Object error, StackTrace stackTrace) {
    if (error is AuthRetryableFetchException) return;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'account',
      ),
    );
  }

  @override
  Future<void> signIn() async {
    final GoogleSignInAccount user;
    final GoogleSignInClientAuthorization authorization;
    try {
      user = await _google.authenticate(scopeHint: _scopes);
      authorization =
          await user.authorizationClient.authorizationForScopes(_scopes) ??
          await user.authorizationClient.authorizeScopes(_scopes);
    } on GoogleSignInException catch (error) {
      final failure = classifyGoogleError(error);
      if (failure == null) return;
      throw failure;
    }
    final idToken = user.authentication.idToken;
    if (idToken == null) {
      throw const AccountRejected(MissingIdToken());
    }
    try {
      await _auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization.accessToken,
      );
    } on Exception catch (error) {
      throw classifyAuthError(error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on Exception catch (error) {
      throw classifyAuthError(error);
    } finally {
      // Without this, the next sign-in would reuse the account just left.
      await _google.signOut();
    }
  }

  static AccountState _stateOf(Session? session) => switch (session) {
    null => const SignedOut(),
    Session(:final user) => SignedIn(email: user.email),
  };
}

/// The service of a build whose configuration cannot sign anyone in.
final class UnavailableAccountService implements AccountService {
  const UnavailableAccountService(this.failure);

  final AccountMisconfigured failure;

  @override
  AccountState get state => AccountUnavailable(failure);

  @override
  Stream<AccountState> get stateChanges => const Stream.empty();

  @override
  Future<void> signIn() async => throw failure;

  @override
  Future<void> signOut() async {}
}

/// Google returned an account without an ID token.
final class MissingIdToken implements Exception {
  const MissingIdToken();

  @override
  String toString() => 'MissingIdToken: Google returned no ID token';
}

/// The failure a Google sign-in [error] means; null for a user who cancelled.
AccountFailure? classifyGoogleError(GoogleSignInException error) =>
    switch (error.code) {
      GoogleSignInExceptionCode.canceled => null,
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        AccountMisconfigured(error),
      GoogleSignInExceptionCode.interrupted ||
      GoogleSignInExceptionCode.uiUnavailable ||
      GoogleSignInExceptionCode.userMismatch ||
      GoogleSignInExceptionCode.unknownError => AccountRejected(error),
    };

/// The failure a Supabase Auth [error] means. The client wraps a request that
/// never reached the server, or that it failed with a 5xx, in
/// [AuthRetryableFetchException].
AccountFailure classifyAuthError(Exception error) => switch (error) {
  AuthRetryableFetchException() => AccountOffline(error),
  AuthApiException(code: 'provider_disabled') => AccountMisconfigured(error),
  _ => AccountRejected(error),
};
