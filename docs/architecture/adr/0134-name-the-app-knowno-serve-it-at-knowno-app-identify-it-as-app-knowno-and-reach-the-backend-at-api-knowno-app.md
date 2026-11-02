# ADR 0134: Name the app knowno, 알아몰라 in Korean, serve it at knowno.app, identify it as app.knowno, and reach the backend at api.knowno.app

> Status: accepted; its unchanged marks superseded by ADR-0139
> Date: 2026-11-01

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #522**, the owner's decisions of 2026-11-01: the project is renamed knowno, and its Korean name is 알아몰라, after the 안다/모른다 grading. The owner bought `knowno.app` and retires `smartman.garam.sh`. The web's primary address is `https://knowno.app`, with `www` redirecting to it. The bundle ID becomes `app.knowno` before any store release.
- **The backend's custom domain**: Supabase's custom domain `api.knowno.app` is active for the project (PM check of 2026-11-01 in #522), and the MCP server already answers there ([ADR 0133](0133-serve-the-mcp-server-at-api-knowno-app-name-a-listed-host-as-its-resource-and-auth-s-issuer-as-its-authorization-server.md)).
- **Where the old name and host were read**: the app's `appTitle`, iOS's `CFBundleDisplayName` and `CFBundleName`, Android's label, the web's titles, marks' alt text, manifest and legal pages, the MCP server's `resource_name`, `serverInfo` and instructions, and the app's legal links to `https://smartman.garam.sh/terms` and `/privacy` ([ADR 0032](0032-publish-the-legal-documents-on-the-web-and-link-both-clients-to-them.md)).
- **Google sign-in is bound to the identifiers**: the iOS OAuth client is created for one bundle ID, and the Android client is matched by package name and signing certificate ([ADR 0006](0006-account-native-google-sign-in.md)). On 2026-11-01 the owner edited the existing iOS client, `201216613268-0kgom9mhkgnqqi92bd10slg8o50a73sv`, changing its bundle ID to `app.knowno` (PM's message on #530); the Android client for `app.knowno` is the owner's to create.
- **The session's storage key follows the Supabase URL's first host label**: `supabase_flutter` 2.18.3 (`lib/src/supabase.dart`) and `@supabase/supabase-js` 2.118.0 (`defaultStorageKey`) both store it as `sb-<first label>-auth-token`, so moving from `jaxltcczmioxrineznfu.supabase.co` to `api.knowno.app` changes the key from `sb-jaxltcczmioxrineznfu-auth-token` to `sb-api-auth-token`.
- **Alternatives considered:**
  - **One name in both languages.** The owner chose a Korean name that reads the grading, and the platforms localise the display name.
  - **Keeping the bundle ID `sh.garam.smartman`.** It would carry the retired domain into the stores for good; nothing is released, so the change costs one reinstall now and none later.
  - **Keeping the project's Supabase URL in the clients.** It keeps working, but the issue retires every dependence on hosts other than knowno.app's.
  - **Renaming the internal identifiers in the same change**: the Dart package, the crates, the web package, the images, the cookies' and local storage's keys and the asset files. Users never read them, and renaming the stored keys would drop each browser's theme and pending forms; they are #523.

## Decision

- **The name**: 알아몰라 wherever a user reads the name in Korean, knowno in English and as the brand.
  - The app's `appTitle` is `knowno` in English and `알아몰라` in Korean; iOS's display name comes from `InfoPlist.strings` in `en.lproj` and `ko.lproj`, Android's label from `@string/app_name` in `values/` and `values-ko/`, and `Info.plist`'s own `CFBundleDisplayName` is the English one.
  - The web, written in Korean, names itself 알아몰라: the root title, each page's "· 알아몰라", the marks' alt text, the manifest and the legal pages' operator.
  - The MCP server, read by a model and in Claude's and ChatGPT's settings, is `knowno`: its `resource_name`, `serverInfo` and instructions.
- **The marks are unchanged.** The lockups' wordmark still spells smartman; a new mark is #524's.
- **The web's address is `https://knowno.app`**, `www.knowno.app` redirecting to it. The app's legal links are `https://knowno.app/terms` and `https://knowno.app/privacy`.
- **The bundle ID, the Android application ID and its namespace are `app.knowno`**, with `MainActivity` in the `app.knowno` package.
- **The clients reach the backend at `https://api.knowno.app`**: `SUPABASE_URL` in `app/config/dev.json`, from which `web.sh` and the README take the web's `NEXT_PUBLIC_SUPABASE_URL`, and the production web's value on Vercel.
- **The iOS client is the existing one, re-pointed to `app.knowno`**, so `GOOGLE_IOS_CLIENT_ID` in `app/config/dev.json` and its reverse in `Info.plist` are unchanged, and no new client is created.

## Consequences

- The renamed app installs beside the old one: a phone keeps `sh.garam.smartman` and its local database until it is deleted, and the new app starts empty and pulls the account's synced data at sign-in. A change the old app has not pushed stays there.
- Every web browser signs in again once, since its session cookie is stored under the old key; the app's new install has no session to keep.
- An installed `sh.garam.smartman` app can no longer sign in with Google on iOS, since its client now names `app.knowno`; a session it already holds keeps syncing until it ends. Android sign-in fails until the Android client for `app.knowno` with the build's signing certificate exists.
- The web's Google sign-in returns to `https://knowno.app/auth/callback`, which Supabase Auth's redirect allow list must hold, and Auth's Site URL becomes `https://knowno.app`. The app signs in natively and opens no deep link, so it adds nothing to that list.
- The internal identifiers still say smartman until #523, the marks until #524.

## Signs the decision was wrong

- A user cannot tell the app from its listing or its icon, because the Korean and English names read as two apps.
- Sign-in through `api.knowno.app` fails where the project's own URL works, which would mean Auth's custom domain does not serve the clients as it serves the MCP server.
- The legal pages need to stay reachable at `smartman.garam.sh` for an installed copy of the old app, which links there.
