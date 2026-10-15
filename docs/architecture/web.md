# Web

The web app in `web/`: its stack, the rules that keep it portable between Vercel and a container, its image, Google sign-in, studying decks, its theme, and its checks.

## Current decisions

### Project

- `web/` is a Next.js 16.4.1 App Router project of its own, with strict TypeScript and the `src/` layout of stack-nextjs.md §1 ([ADR 0019](adr/0019-web-app-stack-portability-and-sign-in.md)). It runs on Node.js 24.22.0, named once in `web/.nvmrc`.
- Its packages are pinned exactly in `web/package.json` and locked in `web/package-lock.json`. Dependabot's `npm` entry for `/web` proposes their moves, except TypeScript 6.1 and later, ESLint 10 and later, and `@types/node` 25 and later:
  - typescript-eslint 8.71.2 accepts TypeScript below 6.1;
  - eslint-config-next 16.4.1 brings React, import and jsx-a11y lint plugins that accept ESLint 9 at most;
  - `@types/node` follows `web/.nvmrc`, which the PM moves with the Dockerfile's base image.
- Its features live under `web/src/features/` ([`structure.md`](structure.md)): `auth`, `decks` and `study`.
- Every user-facing string is Korean, in 해요체, written where it is rendered; the root layout declares `lang="ko"`.
- Icons are `lucide-react`'s, pinned exactly like every package ([ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)).

### Portability

- No Vercel-only feature: no `@vercel/` package and no `runtime = 'edge'` anywhere under `web/`. `make lint` fails on either through `web.sh`, after checking that its pattern still finds both in two control lines.
- The build is `output: "standalone"`, and runs on the Node.js runtime.
- The configuration is environment variables, parsed once by `web/src/env.ts`: `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, and the optional `NEXT_PUBLIC_TERMS_URL` and `NEXT_PUBLIC_PRIVACY_URL`. A missing or malformed Supabase value, a key that is not a publishable key, or a legal link that is set and not https, fails the build. All are public, and no secret is read: the app uses the publishable key and the user's session.
- They are frozen into the build, so a build, and an image, belongs to one Supabase project. `web.sh` builds with the values of `app/config/dev.json` unless the environment already sets them.
- `GET /api/health` answers `{"status":"ok"}` with 200 and reads nothing.

### Image

- `web/Dockerfile` is built from the repository root: `docker build -f web/Dockerfile .`, with both variables as `--build-arg`. `web/Dockerfile.dockerignore` admits only `web/`, `app/assets/fonts/` and `engine-wasm/pkg/` ([ADR 0022](adr/0022-study-on-the-web-with-the-engine-in-the-browser.md)).
- Three stages install the locked packages, build, and copy the standalone server, the static files and `public/` into the runtime stage. Each starts from the same index digest of `node:24.22.0-trixie-slim`, and the frontend is pinned by digest in the `# syntax=` line.
- The runtime stage runs `node server.js` on port 3000 as the base image's `node` user, uid 1000.
- Dependabot's `docker` entry for `/web` proposes only a new digest of the same `node:24.22.0-trixie-slim` tag; it ignores every Node.js release change. `make lint` fails while a `FROM` names another release than `web/.nvmrc`, and `web.sh` fails while the running Node.js differs from that file, so a release change moves `web/.nvmrc`, the `node-version` of `.github/workflows/ci.yml`'s `setup-node` step and the three `FROM` digests together, which Dependabot cannot do. The PM moves them, in one PR, to a new LTS release verified per ci.md.
- What the image runs is the web app alone; nothing in it may reach a Supabase secret.

### Sign-in

- The session is Supabase Auth's, in the cookies `@supabase/ssr` writes. `web/src/lib/supabase/` holds the server client, over the request's cookies, the browser client, and `readSession`, which verifies a session with `getClaims` and returns `signed-in` with the email, `signed-out`, or `unreachable`.
- The server client waits for the request (`connection()`) before it starts: Supabase Auth's client reads the clock as it starts, which a prerender, a link's prefetch included, refuses.
- `web/src/proxy.ts` runs on every path but `/api`, `_next/static`, `_next/image`, `favicon.ico`, `brand/` and the `.svg`, `.png` and `.webmanifest` files of `public/`. It refreshes the session cookies and sends a `signed-out` visitor to `/login` from every path but `/login`, `/auth/callback`, `/terms` and `/privacy`. An `unreachable` Supabase lets the request through, so an outage signs no one out.
- `/login` offers "Google로 로그인". The button calls the browser client's `signInWithOAuth` for Google, with `redirectTo` the page's origin plus `/auth/callback`; a failure to start is shown beneath it.
- `/auth/callback` is a Route Handler. It exchanges the code for the session cookie and opens `/`, or opens `/login?error=cancelled` when no code arrives and `/login?error=failed` when the exchange fails; `/login` shows the matching sentence.
- `/account` reads the session on the server and shows the account's initial and email and "로그아웃", or that the server cannot be reached; the home page's avatar opens it.
- `/login` names the terms the user agrees to, "계속하면 이용약관과 개인정보 처리방침에 동의하는 것으로 봐요.", over the two legal links.
- Sign-out is the Server Action `signOut`, through the `auth` feature's `actions.ts`. It revokes this browser's session alone (`scope: "local"`), so the phone stays signed in, and opens `/login`. When Supabase cannot be reached it returns the sentence the form shows.
- Each origin the app is served from must be in Supabase Auth's allowed redirect URLs as `<origin>/auth/callback`. Only the owner changes that list.

### Decks and study

- The web app is online-first: it reads and writes the server tables of [`server.md`](server.md) with the user's session, under row-level security, and keeps no local database. Nothing creates or edits decks or cards on the web.
- Reads run on the server, in each page's Server Component, through `decks`' `readLibrary` (decks and cards) and `study`'s `readCardStates`. Each reads its tables in pages of 1000 rows, PostgREST's `max_rows` in `supabase/config.toml`, keeps the signed-in user's own rows, since row-level security also lets every user read other users' public decks and their cards ([`server.md`](server.md)), leaves out every row with `deleted_at` set and every card of such a deck, and parses each row at the boundary. A failure reaches the page as a value, `unreachable`, `rejected`, `failed` or `unreadable`, which it shows as one sentence in place of the list; the codes map as the phone's do ([`sync.md`](sync.md)).
- The screens follow the principles, tokens and v2 look of [`design.md`](design.md) at desktop width, lists in a centred 560 px column and the study card up to 720 px wide ([ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)):
  - `/`: the horizontal lockup as the heading and the account's avatar at the right, then the navy today card, "오늘 할 카드", the count large with "장", "복습 x · 새 카드 y", in a backlog "밀린 복습을 마칠 때까지 새 카드는 쉬어요.", and a white "모두 학습", or with nothing to study "오늘 할 카드를 다 했어요" and no button, then "내 덱 n" and a row per deck, by name: its initial on a tile in the tint the app gives it, "카드 n장", a brand-tint "오늘 n" chip when n > 0, a chevron, and a link to the deck named by all three;
  - `/decks/[id]`: a back link, the name, the pills "카드 n", "복습 x" and "새 카드 y", in a backlog the same sentence, "학습하기 · n장", disabled at 0, and the cards, oldest first, as one rounded group of front and back rows, with a search that keeps the cards whose front or back holds it, ignoring case. A deck that does not exist, or is deleted, is not found;
  - `/study?decks=…`: a session over the comma-separated decks, leaving out those that do not exist;
  - `/account`: the profile card, "계정" with "로그아웃", and the mascot and the legal links at its foot;
  - `/terms` and `/privacy`: the configured document, or until there is one, a page saying it is coming.
- Three things the phone shows wait for the web's data loading, which issue #69 owns: the today card's "약 n분", which needs the user's recent review durations; the summary's next review, which needs the state each write computes; and the "공개" chip, which needs a deck's visibility.
- `web/src/features/study/queue.ts` holds the queue rules of [`study.md`](study.md), in one module: a backlog above three days of reviews due, its due cards earliest due first in shuffled runs of ten and no new card; otherwise the due cards and up to 20 new ones, oldest first, shuffled; a "모른다" shown again after 3 to 5 other cards; and the counts the deck screens show, from the same selection ([ADR 0025](adr/0025-order-a-review-backlog-by-due-date-and-pause-new-cards.md)). The study page selects the queue on the server, at the time it read the states, and the browser orders it from a random source seeded with that time, so the server's render and the browser's agree. Every random choice of a session, its order, each re-show gap and each answer's fuzz factor, comes from that one source.
- The study screen ports the phone's session ([`study.md`](study.md)) in its v2 look: the split card, question left at 30/800 and answer right at 20/600, centred in each half, hidden until shown, divided by an inset line; the 8 px ink progress bar of cards answered out of the queue, with "n/m"; every answer of the session above the card, newest nearest, each a button that toggles it between "안다" and "모른다" with the phone's queue effects; and the summary when the queue empties or the user ends the session. Swipe is not offered.
- Keyboard: Space shows the answer, → or K is "안다", ← or J is "모른다", Z toggles the last answer, Esc ends the session, and ? lists these in a dialog. Letters are read by their physical key, so they work in any input language. Each has a visible button carrying it in `aria-keyshortcuts`.
- The engine runs in the browser ([ADR 0022](adr/0022-study-on-the-web-with-the-engine-in-the-browser.md)). `web/src/features/study/engine-wasm` links to `engine-wasm/pkg/`, which `next.config.ts` admits in `turbopackAdditionalRoots`; the generated glue fetches its `.wasm`, which the build serves as a static file. The screen starts fetching it when it opens.
- Writes never hold the screen: an answer or a toggle changes it at once, and its write joins a queue that sends one write at a time, in order. A write replays the card's answers of this session, with their fuzz factors, from its state when the session opened, as the phone does, and the Server Action `recordAnswer` stores the result with the session it verifies ([`sync.md`](sync.md)).
- A write that fails stops the queue: it and every write behind it wait, so a toggle never reaches the server before its answer. The screen says what failed in one sentence with "다시 시도", which sends them again; the answers stay in the stack. While a write waits, leaving the page asks first.

### Theme

- `web/src/styles/globals.css` declares the colour tokens of `app/lib/shared/theme.dart` ([`design.md`](design.md)) in `@theme`, under the same names in kebab case, the radii of `AppRadius`, the type scale of `AppType`, the 560 px list and 720 px study columns, and the card and raised shadows. Under `prefers-color-scheme: dark` it overrides each colour with the dark set.
- `web/src/styles/__tests__/theme-tokens.test.ts` fails when a colour token differs from theme.dart's, in either set, or a radius from `AppRadius`.
- `web/src/styles/fonts` links to `app/assets/fonts/`. `next.config.ts` names that directory in `turbopackAdditionalRoots`, and the root layout bundles Pretendard's Regular, Medium, SemiBold, Bold and ExtraBold with `next/font/local`; nothing is downloaded at run time.
- `web/public/` holds `favicon.svg`, which follows the colour scheme, `favicon-32.png`, `apple-touch-icon.png`, `icon-192.png`, `icon-512.png` and `manifest.webmanifest` with theme colour `#1F2A44`; the root layout names them, and `brand/` holds the marks.
- Buttons are at least 52 px high (`min-h-13`), the primary 56, and the focus ring is a visible outline.

### Checks

- `web.sh`, at the repository root, implements the `web/` part of `make lint`, `format`, `test` and `build`. Where `node` is missing it prints that it skipped; where the host's Node.js differs from `web/.nvmrc` it fails. It installs the locked packages when they are missing or older than the lock file.
- `make lint`: ESLint with typescript-eslint's type-checked strict rules, `tsc --noEmit`, the portability check and the Node.js release check.
- `make format`: Prettier, over the files git tracks or would track.
- `make test`: the Vitest suite (`web/src/**/__tests__/`), then, where Docker and buildx answer, the image built and run, its health and non-root uid asserted, and the Playwright specs in `web/e2e/` run against it; `web/e2e/study.spec.ts` skips there. Then `supabase/test-web.sh` runs that spec against a throwaway local stack (below).
- `make build`: `next build`, then the image where Docker and buildx answer.
- CI runs `web.sh` on the Node.js that `.github/workflows/ci.yml` installs for the WebAssembly tests, on both jobs; `web.sh` fails there when it differs from `web/.nvmrc`. Only the ubuntu job has Docker, so it alone runs the image and the e2e specs, `supabase/test-web.sh`'s included.

### Tests

- `web/src/app/__tests__/sign-in-gate.test.ts` lists every route from the `page.tsx` and `route.ts` files under `web/src/app/`, and runs each through the proxy's matcher and the proxy, against Supabase Auth substituted with MSW: signed out, every route but the three public ones goes to `/login`; signed in, none does.
- `web/src/app/account/__tests__/account.test.tsx` renders the account page's profile and the home page's avatar link over a session cookie and shows the server-side read: the initial and the email, the link to `/account`, the unreachable state, and the redirect without a session.
- `web/src/components/__tests__/legal.test.tsx` checks the legal links' targets without a configured URL, the coming-soon page, and its redirect once a URL is configured; `web/src/__tests__/env.test.ts` the legal links' parsing.
- `web/src/features/decks/__tests__/deck-tint.test.ts` checks that a deck's tile takes the tint the app gives the same id.
- `web/src/app/auth/callback/__tests__/route.test.ts`, `web/src/features/auth/__tests__/` and `web/src/app/login/__tests__/` cover the code exchange, sign-out and the sentences shown.
- `web/e2e/sign-in.spec.ts` runs against the image: `/` lands on `/login`, the sign-in request leaves for Supabase with this origin's callback, the theme follows dark mode, the icons, the manifest and the manifest's icons answer 200 without a session, and `/api/health` answers.
- PostgREST is substituted in the Vitest suite by `web/src/testing/mocks/postgrest.ts`, which holds the four tables in memory and applies the filters, paging, upsert resolutions and review column grant the app relies on:
  - `web/src/app/__tests__/decks.test.tsx` — the deck list and its chips from server rows, the backlog sentence, tombstones and another user's public deck left out, and a library larger than one page;
  - `web/src/app/decks/[id]/__tests__/deck.test.tsx` — the deck page, the backlog sentence, its search, and a deleted deck not found;
  - `web/src/app/study/__tests__/study.test.tsx` — the queue's order and re-show gap under the seeded source, its membership, each keyboard shortcut and its visible control, the next card shown before its write is answered, and a failed write retried;
  - `web/src/features/study/__tests__/queue.test.ts` — the backlog: new cards taken at three days of reviews due and left out above, the earliest-due order with its tie, the shuffled runs of ten, and an up-to-date queue shuffled whole;
  - `web/src/features/study/__tests__/writes.test.tsx` — an answer writes one review and the state the engine module gives, and a toggle replays with the stored factor;
  - `web/src/features/study/__tests__/engine.test.ts` — the engine as the browser loads it: one step of `engine/tests/fixtures/reference.json`, fuzz included, and a refused review arriving as its typed `EngineError`.
- `web/e2e/study.spec.ts` signs up a user with a password on a local stack, where password sign-in is enabled in `supabase/config.toml`, seeds a deck and a card as the phone's sync would, studies the card in the browser, and reads the review and the state back from the server. With `E2E_SCREENSHOTS` naming a directory, it also saves the home, deck, study, summary and account pages in both colour schemes there, for review. `supabase/test-web.sh` starts that stack as `supabase/test-sync.sh` does ([ADR 0014](adr/0014-database-tests-on-a-stack-of-their-own.md)), builds the app with the stack's URL and key, serves it with its standalone server as the image does, runs the spec, fails when it ran no test, and stops the server and the stack on every exit. Without Docker or `node` it prints the skip and why.

## Rationale

- [ADR 0019](adr/0019-web-app-stack-portability-and-sign-in.md) records the stack, the portability rules, why the image is built from the repository root, why the font is linked rather than copied, why sign-in starts in the browser, and why sign-out is local.
- [ADR 0022](adr/0022-study-on-the-web-with-the-engine-in-the-browser.md) records why the engine runs in the browser, why answers are written through one Server Action one at a time, and why the image admits `engine-wasm/pkg/`.
- [ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md) records the web's v2 look, its icons and manifest, the legal links, and why the minutes, the next review and the public chip wait for #69.
- Issue #44 records the decisions made by the PM; issue #45 those for studying on the web; issue #72 the brand and the v2 pages.

## Open questions

- None.
