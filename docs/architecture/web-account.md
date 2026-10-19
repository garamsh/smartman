# Web account

The web's `account` feature: the sign-in page with Google's button, the code exchange, the account page and sign-out. The session and the proxy every route reads are [`web.md`](web.md)'s; the app's `account` domain is [`account.md`](account.md).

## Current decisions

### Sign-in

- `/login` follows the phone's sign-in screen and the SignIn artboard: the stacked lockup, 200 wide, as the heading and the phone's welcome sentence on the ground's panel, rounded at the foot, then on the surface Google's button, "Google로 로그인", and the consent line with the legal links. The button calls the browser client's `signInWithOAuth` for Google, with `redirectTo` the page's origin plus `/auth/callback`; while it starts, progress takes the mark's place and the button cannot be pressed again, and a failure to start is shown beneath it.
- The button is Google's, drawn to its branding guidelines (developers.google.com/identity/branding-guidelines, last updated 2026-07-07, re-read 2026-10-16) as the phone draws it ([ADR 0024](adr/0024-one-voice-and-a-sheet-action-rule.md), [ADR 0031](adr/0031-keep-the-web-theme-choice-in-the-browser-draw-google-sign-in-at-the-app-height-and-hold-each-page-with-a-skeleton.md)): the light button in the light theme and the dark one in the dark, with `GoogleButtonStyle`'s fill, 1 px stroke and label colours and its 14/20 medium label as `@theme` tokens (`google-*`), the guidelines' Android and web spacing, 12 px, 10 px and 12 px, and 56 high with the 16 px radius, the app's, since the guidelines name no height. Its "G" mark is `web/public/google/g-mark-light.png` and `g-mark-dark.png`, byte for byte the app's `app/assets/google/4.0x/` PNGs from Google's bundle ([`design.md`](design.md)), drawn at 20 px.
- `/auth/callback` is a Route Handler. It exchanges the code for the session cookie and opens `/`, or opens `/login?error=cancelled` when no code arrives, `/login?error=suspended` when Supabase Auth answers `user_banned` for a suspended account ([ADR 0072](adr/0072-suspend-a-user-through-supabase-auth-s-ban-and-restrictive-write-policies-remove-a-public-deck-from-sharing-for-good-and-read-any-deck-in-the-admin-area.md)), and `/login?error=failed` when the exchange fails otherwise; `/login` shows the matching sentence.
- Each origin the app is served from must be in Supabase Auth's allowed redirect URLs as `<origin>/auth/callback`. Only the owner changes that list.

### Account page and sign-out

- `/account` reads the session on the server and shows the account's initial and email and "로그아웃", or that the server cannot be reached; the shell's account link opens it.
- `/account` shows "계정과 설정", the profile card, "화면" with the theme choice, "계정" with "로그아웃", and the mascot and the legal links at its foot;
- Sign-out is the Server Action `signOut`, through the `account` feature's `actions.ts`; while it runs, the row shows progress in place of its icon and cannot be pressed again. It revokes this browser's session alone (`scope: "local"`), so the phone stays signed in, and opens `/login`. When Supabase cannot be reached it returns the sentence the form shows.

### Tests

Each line names a file and what it covers; the file holds the cases.

- `web/src/app/login/__tests__/login.test.tsx` — the login page's logo, sentence, button and consent line with its legal links.
- `web/src/features/account/__tests__/sign-in-button.test.tsx` — the button's two marks, its pending state and its failures; `web/src/features/account/__tests__/google-mark.test.ts` — each web mark byte for byte the app's 4x PNG.
- `web/src/app/auth/callback/__tests__/route.test.ts` — the code exchange and each error it opens `/login` with; `web/src/app/login/__tests__/` — the sentence `/login` shows for each.
- `web/src/features/account/__tests__/` — sign-out.
- `web/src/app/(shell)/account/__tests__/account.test.tsx` — the account page's profile, the shell's account link, the legal links, the unreachable state and the redirect without a session.

## Rationale

- [ADR 0019](adr/0019-web-app-stack-portability-and-sign-in.md) records why sign-in starts in the browser and why sign-out is local.
- [ADR 0031](adr/0031-keep-the-web-theme-choice-in-the-browser-draw-google-sign-in-at-the-app-height-and-hold-each-page-with-a-skeleton.md) records why the web's Google button takes the app's height.
- [ADR 0024](adr/0024-one-voice-and-a-sheet-action-rule.md) records why sign-in is drawn as Google's branded button.
- [ADR 0072](adr/0072-suspend-a-user-through-supabase-auth-s-ban-and-restrictive-write-policies-remove-a-public-deck-from-sharing-for-good-and-read-any-deck-in-the-admin-area.md) records the suspended account's sentence.
- Issue #80 records the first screens and Google's button.

## Open questions

- None.
