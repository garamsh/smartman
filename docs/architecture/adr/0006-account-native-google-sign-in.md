# ADR 0006: Sign in with native Google Sign-In through Supabase Auth in an `account` domain, configured per environment from `app/config/`

> Status: accepted
> Date: 2026-10-14

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #15 (M4a) adds optional Google sign-in. The PM decided there:
  - native sign-in: `google_sign_in` obtains a Google ID token and `supabase_flutter` exchanges it with `signInWithIdToken`; the browser OAuth flow is not used;
  - a new domain `account` owns the session state and the sign-in and sign-out actions, and no other domain imports Supabase or Google packages;
  - no screen is gated on an account;
  - the Supabase URL, the publishable key and the Google client IDs reach the app through `--dart-define-from-file`, from one file per environment under `app/config/`, and are not hardcoded in Dart;
  - only a `dev` environment exists; native flavors are deferred to M7, since each would need its own OAuth clients.
- The owner created the OAuth clients for `sh.garam.smartman` and enabled the Google provider on the Supabase project `jaxltcczmioxrineznfu` (issue #15).
- Sources read, at the current stable releases (pub.dev, 2026-10-14):
  - Supabase's "Login with Google" guide, `apps/docs/content/guides/auth/social-login/auth-google.mdx` in `supabase/supabase` at commit `71d652483e449af35c6430e9aba9ebb855dcd1b0`, tabs "Flutter (iOS and Android)". Its sample initializes `GoogleSignIn.instance` with the web client as `serverClientId` and the iOS client as `clientId`, gets the ID token and an access token for the `email` and `profile` scopes, and passes both to `signInWithIdToken`. It asks for a `CFBundleURLTypes` entry holding the reversed iOS client ID, and for iOS the dashboard's "Skip nonce check".
  - The `google_sign_in` 7.2.0 README (tag `google_sign_in-v7.2.0`, commit `f2a65fdceb4a62eafd7dafbd25421283b441623d`): `initialize` once, then `authenticate` where `supportsAuthenticate()` is true.
  - The `google_sign_in_ios` 6.3.7 README (tag `google_sign_in_ios-v6.3.7`, commit `63bc5cd289920cd2e66b54f84051905b69a0c4a3`): the client IDs go in `Info.plist` or are passed to initialization in Dart, and the URL scheme in `Info.plist` is required either way.
  - The `google_sign_in_android` 7.2.18 README (tag `google_sign_in_android-v7.2.18`, commit `eb259296262860cc4a6de8054f28d7fd56649d9d`): without `google-services.json`, the web client ID is passed as `serverClientId`; the Android client is matched by package name and signing SHA-1, not passed.
  - `supabase_flutter` 2.18.3: `Supabase.initialize` takes `publishableKey` (`anonKey` is deprecated), stores the session with `shared_preferences`, and restores it after `initialize` returns without waiting for the network.
- Flutter 3.47.7 hands dart-defines to Xcode only base64-encoded, in the `DART_DEFINES` build setting (`packages/flutter_tools/lib/src/build_info.dart`). `Info.plist` cannot expand one of them without a build phase that decodes them into a configuration file, which Xcode reads before any build phase runs, so the value would lag one build behind.

## Decision

- **Domain.** `app/lib/account/` holds the session state, sign-in and sign-out, behind the surface `app/lib/account/account.dart`. It is the only domain importing `supabase_flutter` or `google_sign_in`.
- **Flow.** Sign-in calls `GoogleSignIn.authenticate`, which opens the platform's account picker, takes an access token for `email` and `profile`, and passes the ID token and access token to `signInWithIdToken`, as Supabase's guide shows. Sign-out signs out of Supabase, which clears the device's session before telling the server, and then of Google. The session `supabase_flutter` stores is restored at start.
- **Configuration.** `app/config/dev.json` holds `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `GOOGLE_WEB_CLIENT_ID` and `GOOGLE_IOS_CLIENT_ID`, and `make test`, `make build` and `flutter run` pass it with `--dart-define-from-file`. These values are public. The account domain parses them once; a missing or malformed value, a secret key among them, leaves sign-in unavailable with a typed `AccountMisconfigured`, and the rest of the app runs.
- **No secret in the repository.** `make lint` runs `check-secrets.sh`, which fails on a Supabase secret key (`sb_secret_`) or a service-role JWT in any file the repository tracks or would track.
- **Native pins.** `google_sign_in_ios` brings Google Sign-In for iOS as Swift packages, which Xcode pins by commit in `app/ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved` and its copy under `Runner.xcodeproj/`; both are committed. A `google_sign_in_ios` bump from Dependabot that changes the requirement re-resolves them on the next `flutter build ios`; within an unchanged requirement the PM re-resolves them.
- **One environment.** Only `dev` exists, pointing at the current project. Native flavors, with an application ID and OAuth clients per environment, are deferred to M7.

### Departures from the documented setup

- **The iOS client ID is passed in Dart, not set as `GIDClientID` in `Info.plist`.** Both forms are documented; passing it keeps `app/config/dev.json` its one source.
- **The URL scheme is the one value duplicated.** `Info.plist` holds the reversed iOS client ID, which it cannot read from the dart-defines (Context). `make lint` runs `check-ios-client-id.sh`, which fails when it differs from `GOOGLE_IOS_CLIENT_ID` in `app/config/dev.json`.
- **No nonce is sent.** Supabase's Flutter sample sends none and asks for "Skip nonce check" on iOS, a dashboard setting the owner holds.
- **`detectSessionInUri` is off.** No browser flow returns a session through a deep link.

## Consequences

- Deck and study need no account and import nothing of it; the account screen is opened from the deck list through a provider the composition site overrides, as `study`'s screen is.
- A build without `--dart-define-from-file` still runs, with sign-in unavailable and saying so.
- A second environment means a second file under `app/config/`, and, because `Info.plist` holds one URL scheme, the flavors that M7 brings.
- Changing the iOS client ID means changing `app/config/dev.json` and `Info.plist` together, or `make lint` fails.
- The Google provider's dashboard settings, the nonce check among them, are the owner's and are not in this repository.

## Signs the decision was wrong

- Sign-in on iOS fails on the nonce once Supabase or Google stops accepting an ID token without one.
- A second environment is needed before M7, and switching `app/config/` files by hand breaks iOS sign-in through the single URL scheme.
- Other domains need the session (M5 sync) and the `account` surface grows to export Supabase's client or types.
- Users report being signed out after offline periods, which would mean the restored session is not kept while a refresh cannot reach the server.
