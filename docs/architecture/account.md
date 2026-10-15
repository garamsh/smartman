# Account

The `account` domain: signing in with Google through Supabase Auth, the session it starts, deleting the account, and the configuration it reads.

## Current decisions

### Surface and location

- The domain lives in `app/lib/account/`; its public surface is `app/lib/account/account.dart`, with internals under `app/lib/account/src/` ([ADR 0002](adr/0002-domain-public-surface-and-shared-database.md)).
- The surface exports:
  - `connectAccount`, which returns an `AccountConnection`: the service, and the `SupabaseClient` it signs in through, null when the configuration cannot sign anyone in; and `accountDefines`;
  - `AccountService`, which signs in, signs out and deletes the account, and `accountServiceProvider`, which the composition site overrides;
  - the state: `AccountState`, `SignedOut`, `SignedIn` with the account's `UserId`, `AccountUnavailable`;
  - `AccountData`, `AccountDataNotCleared` and `accountDataProvider`, the device's data that sign-out pushes and clears, and `syncStatusProvider`, the sync status the screen shows; the composition site overrides both with the `sync` domain's, so this domain does not depend on it ([`sync.md`](sync.md));
  - the failures: `AccountFailure`, `AccountOffline`, `AccountMisconfigured`, `AccountRejected`;
  - `AccountGate`, the app's home, and `signedInHomeProvider`, the app it opens, which the composition site overrides with the deck list, so this domain does not depend on `deck` ([ADR 0017](adr/0017-require-sign-in-through-an-account-gate.md));
  - `AccountScreen`, and `AccountAvatar`, the account's initial in a circle, which the deck list shows through `accountAvatarProvider`;
  - `LegalLinks` and `legalLinksProvider`, the configured terms of service and privacy policy, and `appVersionProvider`, the version the account screen names; the composition site overrides both.
- It is the only domain that imports `google_sign_in` ([ADR 0006](adr/0006-account-native-google-sign-in.md)). `sync` and `sharing` also import `supabase_flutter`, for PostgREST with the client `connectAccount` returns ([ADR 0015](adr/0015-sync-protocol-and-conflict-policy.md), [ADR 0020](adr/0020-public-decks-in-a-sharing-domain.md)).
- `deck`'s list screen opens `AccountScreen` through `accountScreenProvider` and shows `AccountAvatar` through `accountAvatarProvider`, which the composition site overrides, so `deck` does not depend on this domain ([`deck.md`](deck.md)).

### Gate

- Sign-in is required: `AccountGate` shows `SignInScreen` while the state is `SignedOut` or `AccountUnavailable`, and the app only while it is `SignedIn` ([ADR 0017](adr/0017-require-sign-in-through-an-account-gate.md)).
- The gate shows the state the service holds now and never waits on the network: a session restored at start opens the app offline, expired or not, while its refresh runs in the background.
- When the state leaves `SignedIn`, by sign-out or by the client dropping the session, the gate closes every screen opened over the app, so the sign-in screen is the only one left.
- `SignInScreen` is the app's welcome ([ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)): the stacked lockup, 200 wide and read as the app's name, with the two lines "밀어서 답하고,\n잊을 때쯤 다시 만나는 암기 카드", centred on a ground-coloured panel whose bottom corners are rounded 40; below it, in thumb reach, Google's "Google로 계속하기" button and, quieter, a disabled "Apple로 계속하기 · 준비 중" text button that Apple sign-in (M4b) fills; then "계속하면 이용약관과 개인정보 처리방침에 동의하는 것으로 봐요." over the two links. With `AccountUnavailable` it shows the misconfiguration message in place of the buttons, and no app runs.
- The Google button is Google's own, drawn to its branding guidelines in the light or dark variant of the theme, with the "G" mark from Google's asset bundle ([`design.md`](design.md), [ADR 0024](adr/0024-one-voice-and-a-sheet-action-rule.md)).
- `AccountScreen` is reached only from the app, so it shows the signed-in account, the theme, sign-out and deletion:
  - a profile card: a 56 px `AccountAvatar`, the email, and the sync status under it, synced with a check;
  - "화면", the theme control on a rounded surface;
  - "계정", with "로그아웃" as an `AppListRow`, and below it "계정 삭제", a destructive `AppListRow` with the note "계정을 삭제하면 서버와 이 기기에 있는 카드와 기록이 모두 지워져요. 되돌릴 수 없어요."
  - a foot: the mascot at half opacity, "버전 x.y.z", and the two links.

### Sign-in and session

- Sign-in opens the platform's Google account picker (`GoogleSignIn.authenticate`), then passes the Google ID token and an access token for `email` and `profile` to Supabase's `signInWithIdToken`.
- Each run draws one random nonce when it initializes Google Sign-In: Google receives its SHA-256 as hex and puts it in the ID token, and `signInWithIdToken` receives the raw value, which Supabase checks against the token. Every sign-in in a run carries the same nonce, since Google Sign-In is initialized once per run ([ADR 0008](adr/0008-google-sign-in-nonce.md)).
- `supabase_flutter` stores the session on the device and restores it at start; the app then opens past the gate.
- Sign-out first asks `AccountData` to push every unsynced change. When some did not arrive, a confirmation sheet, "동기화되지 않은 변경이 있어요", offers "취소", which keeps the account signed in, and "그래도 로그아웃".
- It then ends the Supabase session on the device, tells the server, and signs out of Google so the next sign-in shows the picker again. Once the device is signed out, even after a failure telling the server, `AccountData` clears the device's data; a failure there is shown in a snack bar.
- The state is `SignedOut`, `SignedIn` with the account's email, or `AccountUnavailable` when the build's configuration cannot sign anyone in.

### Deletion

- "계정 삭제" asks first through `showAppConfirm`: "계정을 삭제할까요?", one sentence saying the decks, cards and study history go from the server and this device while decks others copied and the Google account stay, then "취소" and, last, a red "삭제" ([ADR 0026](adr/0026-delete-the-account-through-an-edge-function.md)).
- `AccountService.deleteAccount` posts to the `delete-account` Edge Function through the Supabase client's Edge Functions client, which sends the session's access token; the request names no user. The function deletes the token's user, and the server's cascade deletes every row it owns ([`server.md`](server.md)).
- Once the account is deleted, the screen signs out of Supabase and Google and clears the device's data through `AccountData`, as sign-out does but without pushing first. The gate then shows the sign-in screen.
- A failed deletion changes nothing: the account stays signed in with its data.
- Only the PM deploys the function, after the pull request that changes it merges; it lives in `supabase/functions/delete-account/` with its Deno tests, run by `make test` through `deno.sh` with Supabase Auth replaced by a fake `fetch`.

### Configuration

- `app/config/dev.json` holds the Supabase URL, the Supabase publishable key, the Google web client ID (passed as the server client ID) and the iOS client ID. The values are public. The Android client is matched by package name and signing certificate, so no Android client ID is configured.
- `make test`, `make build` and the README's `flutter run` pass the file with `--dart-define-from-file`; no Dart source holds a value.
- The values are parsed once at start. A missing or malformed value, or a key that is not a publishable key, makes the state `AccountUnavailable`, with the reasons in its `AccountMisconfigured`; the gate then shows the message and no app.
- `TERMS_URL` and `PRIVACY_URL` in the same file name where the terms of service and the privacy policy are published. Both are empty until the owner supplies them; an empty one's link opens a "준비 중" page in the app, and a set one opens in the platform's browser through `url_launcher`, with a snack bar when it does not open. A value that is not an https URL makes start-up fail, before the first frame ([ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)).
- The app's version comes from the platform through `package_info_plus`, read once before the first frame.
- `app/ios/Runner/Info.plist` holds the reversed iOS client ID as a URL scheme. `check-ios-client-id.sh`, run by `make lint`, fails when it differs from `app/config/dev.json`.
- `check-secrets.sh`, run by `make lint`, fails when any file the repository tracks or would track holds a Supabase secret key or service-role key.
- The Swift packages `google_sign_in_ios` brings are pinned in the committed `Package.resolved` files under `app/ios/` ([ADR 0006](adr/0006-account-native-google-sign-in.md)).
  - `.github/dependabot.yml` has no `swift` entry for them. Dependabot's `swift` updater reads an Xcode project's `Package.resolved` (`swift/lib/dependabot/swift/file_fetcher.rb` in dependabot-core at `3ac9b7af9e729e80c8d1ddfbf6ae3839675fa77e`). It takes the requirements from the `XCRemoteSwiftPackageReference` entries of `project.pbxproj` (`file_parser/pbxproj_parser.rb`, same revision), and `app/ios/Runner.xcodeproj/project.pbxproj` has none: it names only `FlutterGeneratedPluginSwiftPackage` under `app/ios/Flutter/ephemeral/`, which git ignores. Without those requirements, Dependabot would move the pins past what `google_sign_in_ios` accepts.
  - The mover is the PM. To re-resolve within the current requirements: delete both `Package.resolved` files, then in `app/` run `flutter build ios --config-only --no-codesign --dart-define-from-file=config/dev.json`, which rewrites the copy under `Runner.xcodeproj/`, and `xcodebuild -resolvePackageDependencies -workspace ios/Runner.xcworkspace -scheme Runner`, which rewrites the one under `Runner.xcworkspace/`. Commit both.
- Only the `dev` environment exists; flavors wait for M7 ([ADR 0006](adr/0006-account-native-google-sign-in.md)).

### Failures

- Cancelling the picker is not a failure: sign-in returns and nothing is shown.
- Each expected failure is an `AccountFailure`:
  - `AccountOffline` — Supabase could not be reached, or answered with a server error;
  - `AccountMisconfigured` — the configuration is missing or malformed, Google reports a client or provider configuration error, or Supabase has the Google provider disabled;
  - `AccountRejected` — Google or Supabase refused, the ID token included.
- A deletion that never reached the function, or that it answered with a 5xx, is `AccountOffline`; any other refusal, or a success other than 204, is `AccountRejected`.
- The sign-in screen shows a failure from sign-in, and the account screen one from sign-out or deletion, in a snack bar, as a localized message; a rejected deletion says the account could not be deleted. Any other error propagates.
- A background refresh that cannot reach Supabase is left to the client, which keeps the session and retries; any other refresh error goes to `FlutterError.reportError`.

### Interface

- Every string comes from the shared ARB set. The buttons and the sign-out row are labelled by their text, and the deletion row by its text and note; the Google mark and the avatar are excluded from semantics, the Apple slot is read out as a disabled button, the section labels are headings, the app's name on the sign-in screen is a heading, and the progress indicator shown while signing in or out, or deleting, carries a semantic label.
- The account screen's "화면" section picks the app theme: 시스템, 라이트 or 다크, in a segmented control. The choice belongs to the shared theme ([`design.md`](design.md)); this screen only shows it.

### Tests

- `app/test/account/account_gate_test.dart` composes the app through `composeApp`: signed out shows only the sign-in screen; signing in opens the deck list; signing out returns to the gate; signing out, and deleting the account, from the account screen the gate closes mid-flow still clear the device's database; each screen over the deck list closes when the session ends; a restored, expired session opens the deck list over a Supabase Auth client whose server never answers, with signed out as the control; and an unavailable build shows the message.
- `app/test/account/sign_in_screen_test.dart` drives the sign-in screen with a substitute `AccountService` (`app/test/account/fake_account_service.dart`): the welcome, the logo in the upper part and the buttons below it, the terms sentence with a link that opens the "준비 중" page and one that opens its URL through a substitute opener or says it did not, the progress while signing in, a cancelled sign-in, each failure, the disabled Apple slot below Google's button, and Google's light and dark buttons with the mark and the label, meeting the tap target and contrast guidelines in both themes.
- `app/test/account/account_screen_test.dart` drives the account screen with the same substitute and an `AccountData` (`app/test/account/fake_account_data.dart`): the profile card's initial and email, the order of the sections, the foot's version and links, sign-out with and without unsynced changes, a failed clear, a failed sign-out, the sync status shown only while signed in, and deletion: the red row and its note, the confirmation, cancelling, deleting without a push, each failure, a failed clear, and the tap target and contrast guidelines in both themes.
- `app/test/account/account_service_test.dart` runs the real service over a substitute Google Sign-In platform and a Supabase Auth client whose HTTP client is substituted. It checks that the raw nonce sent to Supabase hashes to the one Google was given, and that each start draws a new one; and, over a substituted Edge Functions client, that deletion posts no body and maps each answer to its failure.
- `app/test/account/config_test.dart` covers the configuration's parsing, the legal links' included, and checks that `app/config/dev.json` parses.

## Rationale

- [ADR 0006](adr/0006-account-native-google-sign-in.md) records the native flow, the sources it follows, the configuration approach, the duplicated URL scheme, and why flavors wait for M7.
- [ADR 0008](adr/0008-google-sign-in-nonce.md) records which platform sources show the nonce reaching the ID token, and why it is drawn per run rather than per sign-in.
- [ADR 0015](adr/0015-sync-protocol-and-conflict-policy.md) records why sign-out pushes and clears the device's data, and why the client reaches `sync`.
- [ADR 0017](adr/0017-require-sign-in-through-an-account-gate.md) records why sign-in is required, how the gate closes the app's screens, and why it never waits on the network.
- [ADR 0026](adr/0026-delete-the-account-through-an-edge-function.md) records why deletion goes through an Edge Function that deletes only the token's user, and why it clears the device without pushing.
- [ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md) records the sign-in and account screens' v2 design, and why the legal links are optional configuration.
- Issue #15 records the decisions made by the PM, issue #20 the nonce, issue #28 the gate, issue #26 deletion, and issue #72 the v2 screens and the legal links.

## Open questions

- None.
