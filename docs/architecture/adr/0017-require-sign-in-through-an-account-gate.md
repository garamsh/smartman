# ADR 0017: Require sign-in through an account gate at the app's root, which opens the app from the session the device holds

> Status: accepted
> Date: 2026-10-15

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- [ADR 0006](0006-account-native-google-sign-in.md) made sign-in optional: "no screen is gated on an account", and a build without configuration ran with sign-in unavailable.
- The owner decided on 2026-10-15 that an account is required to use the app. Issue #28 records the PM's decisions:
  - the root shows the account domain's sign-in screen while the state is `SignedOut`, and the deck list while it is `SignedIn`;
  - the sign-in screen follows the owner-approved design's "로그인 전" screen, retitled as the app's welcome: the app's name, one line on what it does, "Google로 로그인", and a disabled "Apple로 로그인" slot that M4b fills; its wording no longer says the app works without sign-in;
  - a restored session opens the app with no network, and the gate never waits on the network;
  - signing out returns to the gate;
  - with `AccountUnavailable`, the gate shows the misconfiguration message and no app;
  - the gate lives at the composition site through a provider the `account` domain exposes, so `deck` and `study` do not import `account`.
- The issue left sign-out's effect on local data to #24 "until #24 lands". #24 merged first ([ADR 0015](0015-sync-protocol-and-conflict-policy.md)): sign-out pushes, warns when it cannot, then clears the device's data, so that clause is moot and this decision keeps sign-out as ADR 0015 has it.
- Screens over the deck list are routes pushed on the app's one navigator. A session can end while one is open: through the account screen's sign-out, or when the client drops a session the server refused.
- `supabase_flutter` 2.18.3 sets the stored session on the client before `Supabase.initialize` returns, expired or not, and refreshes it afterwards (ADR 0006).

## Decision

- **Gate.** The `account` domain exports `AccountGate`, which `main.dart` makes the app's home. It shows the account domain's `SignInScreen` for `SignedOut` and `AccountUnavailable`, and for `SignedIn` the screen `signedInHomeProvider` builds, which the composition site overrides with the deck list. The provider sits in `account`, as `accountDataProvider` does, so `account` names no screen of `deck`, and `deck` and `study` import nothing of `account`.
- **Leaving.** When the state leaves `SignedIn`, the gate pops every route above the home, so no deck, study or account screen stays open over the sign-in screen.
- **No wait.** The gate reads the state the service holds now. A stored session, expired or not, is `SignedIn`, and its refresh runs in the background as before.
- **Sign-in screen.** The welcome takes the app's name and one line from the ARB set, "Google로 로그인" as an outlined button, and the Apple slot as a disabled button labelled "Apple로 로그인 (준비 중)". With `AccountUnavailable`, the misconfiguration message takes the buttons' place.
- **Account screen.** Sign-in leaves it: it is reached only from the app, so only while signed in. Sign-out stays as ADR 0015 has it.
- This supersedes ADR 0006's "no screen is gated on an account" and its "the rest of the app runs" for a misconfigured build.

## Consequences

- Nothing in the app runs without an account, so every row the local database holds belongs to the signed-in account, as sync assumes.
- A misconfigured build shows only the message; testing deck or study by hand needs a working configuration.
- A screen opened over the app needs nothing of its own to close at sign-out.
- An offline device with a stored session opens the app; one without a session cannot be used until it reaches the server.

## Signs the decision was wrong

- A route opened in a way that bypasses the app's navigator, such as a second navigator, stays on screen after sign-out.
- Users who reopen the app offline after their refresh token was revoked elsewhere see their decks until the device reaches the server, and that is found unacceptable.
- The gate needs to tell more states apart (an account being deleted, a forced update), and the switch in `AccountGate` grows a case for something that is not the account's.
