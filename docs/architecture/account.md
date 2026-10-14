# Account

The `account` domain: signing in with Google through Supabase Auth, the session it starts, and the configuration it reads.

## Current decisions

### Surface and location

- The domain lives in `app/lib/account/`; its public surface is `app/lib/account/account.dart`, with internals under `app/lib/account/src/` ([ADR 0002](adr/0002-domain-public-surface-and-shared-database.md)).
- The surface exports:
  - `connectAccount` and `accountDefines`, with which the composition site builds the service;
  - `AccountService`, and `accountServiceProvider`, which the composition site overrides;
  - the state: `AccountState`, `SignedOut`, `SignedIn`, `AccountUnavailable`;
  - the failures: `AccountFailure`, `AccountOffline`, `AccountMisconfigured`, `AccountRejected`;
  - `AccountScreen`.
- It is the only domain that imports `supabase_flutter` or `google_sign_in` ([ADR 0006](adr/0006-account-native-google-sign-in.md)).
- `deck`'s list screen opens `AccountScreen` through `accountScreenProvider`, which the composition site overrides, so `deck` does not depend on this domain ([`deck.md`](deck.md)).

### Sign-in and session

- Sign-in is optional: no screen waits for it, and deck and study work without it.
- Sign-in opens the platform's Google account picker (`GoogleSignIn.authenticate`), then passes the Google ID token and an access token for `email` and `profile` to Supabase's `signInWithIdToken`.
- Each run draws one random nonce when it initializes Google Sign-In: Google receives its SHA-256 as hex and puts it in the ID token, and `signInWithIdToken` receives the raw value, which Supabase checks against the token. Every sign-in in a run carries the same nonce, since Google Sign-In is initialized once per run ([ADR 0008](adr/0008-google-sign-in-nonce.md)).
- `supabase_flutter` stores the session on the device and restores it at start; the screen then opens signed in.
- Sign-out ends the Supabase session on the device first, then tells the server, then signs out of Google so the next sign-in shows the picker again.
- The state is `SignedOut`, `SignedIn` with the account's email, or `AccountUnavailable` when the build's configuration cannot sign anyone in.

### Configuration

- `app/config/dev.json` holds the Supabase URL, the Supabase publishable key, the Google web client ID (passed as the server client ID) and the iOS client ID. The values are public. The Android client is matched by package name and signing certificate, so no Android client ID is configured.
- `make test`, `make build` and the README's `flutter run` pass the file with `--dart-define-from-file`; no Dart source holds a value.
- The values are parsed once at start. A missing or malformed value, or a key that is not a publishable key, makes the state `AccountUnavailable`, with the reasons in its `AccountMisconfigured`.
- `app/ios/Runner/Info.plist` holds the reversed iOS client ID as a URL scheme. `check-ios-client-id.sh`, run by `make lint`, fails when it differs from `app/config/dev.json`.
- `check-secrets.sh`, run by `make lint`, fails when any file the repository tracks or would track holds a Supabase secret key or service-role key.
- The Swift packages `google_sign_in_ios` brings are pinned in the committed `Package.resolved` files under `app/ios/` ([ADR 0006](adr/0006-account-native-google-sign-in.md)).
- Only the `dev` environment exists; flavors wait for M7 ([ADR 0006](adr/0006-account-native-google-sign-in.md)).

### Failures

- Cancelling the picker is not a failure: sign-in returns and nothing is shown.
- Each expected failure is an `AccountFailure`:
  - `AccountOffline` — Supabase could not be reached, or answered with a server error;
  - `AccountMisconfigured` — the configuration is missing or malformed, Google reports a client or provider configuration error, or Supabase has the Google provider disabled;
  - `AccountRejected` — Google or Supabase refused, the ID token included.
- The account screen shows a failure from sign-in or sign-out in a snack bar, as a localized message. Any other error propagates.
- A background refresh that cannot reach Supabase is left to the client, which keeps the session and retries; any other refresh error goes to `FlutterError.reportError`.

### Interface

- Every string comes from the shared ARB set. The buttons are labelled by their text, and the progress indicator shown while signing in or out carries a semantic label.
- The screen's "화면" section picks the app theme: 시스템, 라이트 or 다크, in a segmented control. The choice belongs to the shared theme ([`design.md`](design.md)); this screen only shows it.

### Tests

- `app/test/account/account_screen_test.dart` drives the screen with a substitute `AccountService` (`app/test/account/fake_account_service.dart`): both states, a cancelled sign-in, each failure, and sign-out.
- `app/test/account/account_service_test.dart` runs the real service over a substitute Google Sign-In platform and a Supabase Auth client whose HTTP client is substituted. It checks that the raw nonce sent to Supabase hashes to the one Google was given, and that each start draws a new one.
- `app/test/account/config_test.dart` covers the configuration's parsing and checks that `app/config/dev.json` parses.

## Rationale

- [ADR 0006](adr/0006-account-native-google-sign-in.md) records the native flow, the sources it follows, the configuration approach, the duplicated URL scheme, and why flavors wait for M7.
- [ADR 0008](adr/0008-google-sign-in-nonce.md) records which platform sources show the nonce reaching the ID token, and why it is drawn per run rather than per sign-in.
- Issue #15 records the decisions made by the PM, and issue #20 the nonce.

## Open questions

- None.
