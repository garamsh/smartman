# ADR 0008: Send Google sign-in a nonce drawn once per run, its SHA-256 hex to Google and the raw value to Supabase

> Status: accepted
> Date: 2026-10-15

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

Supersedes the "No nonce is sent" departure of [ADR 0006](0006-account-native-google-sign-in.md); the rest of ADR 0006 stands.

## Context

- Issue #20. ADR 0006 sends no nonce, so the owner turned on "Skip nonce checks" for the Google provider (2026-10-14). With it on, Supabase accepts an ID token whatever nonce it carries.
- Supabase Auth `v2.197.0` (commit `4eee58f296d9698a1c2c0ae14d7a0b379c7622d3`), `internal/api/token_oidc.go`: with the check on, the ID token and the request must both carry a nonce or both lack one, and when both do, the token's `nonce` claim must equal the SHA-256 of the request's value as lowercase hex (`fmt.Sprintf("%x", sha256.Sum256(...))`).
- Sources read, at the current stable releases on pub.dev (2026-10-15), each identical to the copy in the pub cache:
  - `google_sign_in` 7.2.0 (tag `google_sign_in-v7.2.0`, commit `f2a65fdceb4a62eafd7dafbd25421283b441623d`), `lib/google_sign_in.dart`: `initialize` takes `nonce` and passes it "as part of any authentication requests"; it must be called "exactly once", and calling it more than once "will result in undefined behavior".
  - `google_sign_in_ios` 6.3.7 (tag `google_sign_in_ios-v6.3.7`, commit `63bc5cd289920cd2e66b54f84051905b69a0c4a3`): `init` stores the nonce, and every interactive sign-in passes it to `GIDSignIn.signIn(withPresenting:hint:additionalScopes:nonce:)` (`GoogleSignInPlugin.swift`).
  - GoogleSignIn-iOS 9.2.0 (commit `08d8dcecafb575f98879ffdbb8302c1b9ad65d19`, the version `app/ios/` pins), `GoogleSignIn/Sources/GIDSignIn.m`: a nonce becomes the `nonce` of the OpenID Connect authorization request, which the ID token issued for it carries.
  - `google_sign_in_android` 7.2.18 (tag `google_sign_in_android-v7.2.18`, commit `eb259296262860cc4a6de8054f28d7fd56649d9d`): `init` stores the nonce, and every credential request passes it to `setNonce` of `GetSignInWithGoogleOption` (the flow `authenticate` uses) or `GetGoogleIdOption` (`GoogleSignInPlugin.kt`). Those builders belong to the closed-source `googleid` 1.2.0; Android's "Implement Sign in with Google" guide (developer.android.com, read 2026-10-15) documents `setNonce` as the nonce a server verifies against the ID token.
- Both platforms therefore carry the nonce. Each fixes it at `init`, so a fresh one per sign-in means re-initializing, which `google_sign_in` leaves undefined.

## Decision

- **A nonce per run.** `GoogleAccountService.start` draws 32 bytes from `Random.secure`, base64url-encodes them as the raw nonce, and initializes Google Sign-In with its SHA-256 as lowercase hex. It is called once, from `connectAccount`, so every sign-in in that run carries the same nonce.
- **The raw value goes to Supabase.** Sign-in passes it as `nonce` to `signInWithIdToken`, which Supabase checks against the token's claim.
- **Both platforms take this path.** Neither source shows a platform that drops the nonce.

### Rejected

- **A nonce per sign-in by calling `initialize` again.** `google_sign_in` documents a second call as undefined behaviour.
- **A nonce per sign-in by calling the platform's `init` directly**, past `GoogleSignIn`. It reaches into the platform interface the app-facing package hides, and holds only while each implementation's `init` stays a plain assignment.

## Consequences

- Once the owner turns "Skip nonce checks" off, Supabase rejects a Google ID token whose nonce does not hash to the raw value sent with it, so an ID token taken from elsewhere cannot be exchanged without the raw nonce of the run that requested it.
- Within one run, the raw nonce is reused across sign-ins; a run's ID tokens share it.
- `package:crypto` becomes a direct dependency of the app.
- The nonce check is a dashboard setting the owner holds; this repository cannot show whether it is on.

## Signs the decision was wrong

- With "Skip nonce checks" off, sign-in fails on one platform with "Nonces mismatch" or "Passed nonce and nonce in id_token should either both exist or not", which would mean that platform's ID token does not carry the nonce as its source reads.
- A later `google_sign_in` documents a per-request nonce, or a re-initialization that is defined, and the per-run nonce is kept anyway.
