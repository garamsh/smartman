import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartman/account/account.dart';
import 'package:smartman/account/src/account_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_google_sign_in.dart';

const _url = 'https://example.test/auth/v1';

Map<String, Object?> _session({String email = 'ada@example.com'}) => {
  'access_token': 'supabase-access-token',
  'expires_in': 3600,
  'refresh_token': 'supabase-refresh-token',
  'token_type': 'bearer',
  'user': {
    'id': '00000000-0000-4000-8000-000000000001',
    'aud': 'authenticated',
    'email': email,
    'app_metadata': <String, Object?>{},
    'user_metadata': <String, Object?>{},
    'created_at': '2026-10-14T00:00:00Z',
  },
};

void main() {
  late FakeGoogleSignIn google;
  late List<http.Request> requests;

  setUpAll(() async {
    google = FakeGoogleSignIn();
    GoogleSignInPlatform.instance = google;
    await GoogleSignIn.instance.initialize();
  });

  setUp(() {
    google
      ..result = FakeGoogleSignIn.signedIn()
      ..error = null
      ..signOuts = 0;
    requests = [];
  });

  /// A service over a Supabase Auth client whose server answers with
  /// [respond].
  GoogleAccountService serviceAnswering(
    Future<http.Response> Function(http.Request) respond,
  ) {
    final auth = GoTrueClient(
      url: _url,
      autoRefreshToken: false,
      httpClient: MockClient((request) {
        requests.add(request);
        return respond(request);
      }),
    );
    return GoogleAccountService(auth, GoogleSignIn.instance);
  }

  Future<http.Response> grant(http.Request request) async =>
      http.Response(jsonEncode(_session()), 200);

  Future<AccountFailure?> failureOf(Future<void> Function() action) async {
    try {
      await action();
    } on AccountFailure catch (failure) {
      return failure;
    }
    return null;
  }

  test('sign-in exchanges the Google ID token for a session', () async {
    final service = serviceAnswering(grant);
    expect(service.state, isA<SignedOut>());

    await service.signIn();

    final request = requests.single;
    expect(request.url.path, '/auth/v1/token');
    expect(request.url.queryParameters['grant_type'], 'id_token');
    expect(
      jsonDecode(request.body),
      allOf(
        containsPair('provider', 'google'),
        containsPair('id_token', 'google-id-token'),
        containsPair('access_token', 'google-access-token'),
      ),
    );
    expect(
      service.state,
      isA<SignedIn>().having((s) => s.email, 'email', 'ada@example.com'),
    );
  });

  test('a stored session is restored as signed in', () async {
    final auth = GoTrueClient(url: _url, autoRefreshToken: false);
    await auth.recoverSession(jsonEncode(_session(email: 'grace@example.com')));

    final service = GoogleAccountService(auth, GoogleSignIn.instance);

    expect(
      service.state,
      isA<SignedIn>().having((s) => s.email, 'email', 'grace@example.com'),
    );
  });

  test(
    'a cancelled picker returns quietly and asks Supabase nothing',
    () async {
      google.error = const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      );
      final service = serviceAnswering(grant);

      expect(await failureOf(service.signIn), isNull);
      expect(requests, isEmpty);
      expect(service.state, isA<SignedOut>());
    },
  );

  test('Google refusing the app configuration is a misconfiguration', () async {
    google.error = const GoogleSignInException(
      code: GoogleSignInExceptionCode.clientConfigurationError,
    );

    expect(
      await failureOf(serviceAnswering(grant).signIn),
      isA<AccountMisconfigured>(),
    );
  });

  test('Google failing the sign-in otherwise is a rejection', () async {
    google.error = const GoogleSignInException(
      code: GoogleSignInExceptionCode.unknownError,
    );

    expect(
      await failureOf(serviceAnswering(grant).signIn),
      isA<AccountRejected>(),
    );
  });

  test('an account without an ID token is a rejection', () async {
    google.result = FakeGoogleSignIn.signedIn(idToken: null);
    final service = serviceAnswering(grant);

    expect(await failureOf(service.signIn), isA<AccountRejected>());
    expect(requests, isEmpty);
  });

  test('Supabase out of reach is offline', () async {
    final service = serviceAnswering(
      (_) async => throw http.ClientException('no route to host'),
    );

    expect(await failureOf(service.signIn), isA<AccountOffline>());
    expect(service.state, isA<SignedOut>());
  });

  test('Supabase refusing the ID token is a rejection', () async {
    final service = serviceAnswering(
      (_) async => http.Response(
        jsonEncode({
          'code': 400,
          'error_code': 'bad_jwt',
          'msg': 'Unacceptable audience in id_token',
        }),
        400,
      ),
    );

    expect(await failureOf(service.signIn), isA<AccountRejected>());
    expect(service.state, isA<SignedOut>());
  });

  test(
    'Supabase with the Google provider disabled is a misconfiguration',
    () async {
      final service = serviceAnswering(
        (_) async => http.Response(
          jsonEncode({
            'code': 400,
            'error_code': 'provider_disabled',
            'msg': 'Provider is not enabled',
          }),
          400,
        ),
      );

      expect(await failureOf(service.signIn), isA<AccountMisconfigured>());
    },
  );

  test('sign-out ends the session and the Google sign-in', () async {
    final service = serviceAnswering(
      (request) async => request.url.path.endsWith('/logout')
          ? http.Response('', 204)
          : grant(request),
    );
    await service.signIn();
    expect(service.state, isA<SignedIn>());
    final changes = expectLater(
      service.stateChanges,
      emitsThrough(isA<SignedOut>()),
    );

    await service.signOut();

    expect(service.state, isA<SignedOut>());
    expect(google.signOuts, 1);
    await changes;
  });

  test('sign-out offline signs the device out and reports offline', () async {
    var online = true;
    final service = serviceAnswering((request) async {
      if (!online) throw http.ClientException('no route to host');
      return grant(request);
    });
    await service.signIn();
    online = false;

    expect(await failureOf(service.signOut), isA<AccountOffline>());
    expect(service.state, isA<SignedOut>());
  });

  test('a build without configuration is unavailable, not a crash', () async {
    final service = await connectAccount(const {});

    expect(
      service.state,
      isA<AccountUnavailable>().having(
        (s) => s.failure.cause.toString(),
        'cause',
        contains('SUPABASE_URL is missing'),
      ),
    );
    expect(await failureOf(service.signIn), isA<AccountMisconfigured>());
  });
}
