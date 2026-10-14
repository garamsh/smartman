import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Stands in for the platform's Google Sign-In: [authenticate] answers with
/// [result], or throws [error] when one is set.
class FakeGoogleSignIn extends GoogleSignInPlatform
    with MockPlatformInterfaceMixin {
  AuthenticationResults? result;
  GoogleSignInException? error;
  String accessToken = 'google-access-token';
  int signOuts = 0;

  static AuthenticationResults signedIn({
    String? idToken = 'google-id-token',
  }) => AuthenticationResults(
    user: const GoogleSignInUserData(email: 'ada@example.com', id: '1'),
    authenticationTokens: AuthenticationTokenData(idToken: idToken),
  );

  @override
  Future<void> init(InitParameters params) async {}

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) => null;

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async {
    if (error case final error?) throw error;
    return result!;
  }

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async => ClientAuthorizationTokenData(accessToken: accessToken);

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async => null;

  @override
  Future<void> signOut(SignOutParams params) async => signOuts++;

  @override
  Future<void> disconnect(DisconnectParams params) async {}
}
