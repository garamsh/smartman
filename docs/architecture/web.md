# Web

The web app in `web/`: its stack, the rules that keep it portable between Vercel and a container, its image, Google sign-in, its theme, and its checks.

## Current decisions

### Project

- `web/` is a Next.js 16.4.1 App Router project of its own, with strict TypeScript and the `src/` layout of stack-nextjs.md §1 ([ADR 0019](adr/0019-web-app-stack-portability-and-sign-in.md)). It runs on Node.js 24.22.0, named once in `web/.nvmrc`.
- Its packages are pinned exactly in `web/package.json` and locked in `web/package-lock.json`. Dependabot's `npm` entry for `/web` proposes their moves, except TypeScript 6.1 and later, ESLint 10 and later, and `@types/node` 25 and later:
  - typescript-eslint 8.71.2 accepts TypeScript below 6.1;
  - eslint-config-next 16.4.1 brings React, import and jsx-a11y lint plugins that accept ESLint 9 at most;
  - `@types/node` follows `web/.nvmrc`, which the PM moves with the Dockerfile's base image.
- Its features live under `web/src/features/` ([`structure.md`](structure.md)). The first is `auth`.
- Every user-facing string is Korean, written where it is rendered; the root layout declares `lang="ko"`.

### Portability

- No Vercel-only feature: no `@vercel/` package and no `runtime = 'edge'` anywhere under `web/`. `make lint` fails on either through `web.sh`, after checking that its pattern still finds both in two control lines.
- The build is `output: "standalone"`, and runs on the Node.js runtime.
- The configuration is two environment variables, parsed once by `web/src/env.ts`: `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. A missing or malformed value, or a key that is not a publishable key, fails the build. Both are public, and no other secret is read: the app uses the publishable key and the user's session.
- Both are frozen into the build, so a build, and an image, belongs to one Supabase project. `web.sh` builds with the values of `app/config/dev.json` unless the environment already sets them.
- `GET /api/health` answers `{"status":"ok"}` with 200 and reads nothing.

### Image

- `web/Dockerfile` is built from the repository root: `docker build -f web/Dockerfile .`, with both variables as `--build-arg`. `web/Dockerfile.dockerignore` admits only `web/` and `app/assets/fonts/`.
- Three stages install the locked packages, build, and copy the standalone server and static files into the runtime stage. Each starts from the same index digest of `node:24.22.0-trixie-slim`, and the frontend is pinned by digest in the `# syntax=` line.
- The runtime stage runs `node server.js` on port 3000 as the base image's `node` user, uid 1000.
- Dependabot's `docker` entry for `/web` proposes the base image's move. `make lint` fails while a `FROM` names another Node.js release than `web/.nvmrc`, so the PR that moves the image also moves the file.
- What the image runs is the web app alone; nothing in it may reach a Supabase secret.

### Sign-in

- The session is Supabase Auth's, in the cookies `@supabase/ssr` writes. `web/src/lib/supabase/` holds the server client, over the request's cookies, the browser client, and `readSession`, which verifies a session with `getClaims` and returns `signed-in` with the email, `signed-out`, or `unreachable`.
- `web/src/proxy.ts` runs on every path but `/api`, `_next/static`, `_next/image` and `favicon.ico`. It refreshes the session cookies and sends a `signed-out` visitor to `/login` from every path but `/login` and `/auth/callback`. An `unreachable` Supabase lets the request through, so an outage signs no one out.
- `/login` offers "Google로 로그인". The button calls the browser client's `signInWithOAuth` for Google, with `redirectTo` the page's origin plus `/auth/callback`; a failure to start is shown beneath it.
- `/auth/callback` is a Route Handler. It exchanges the code for the session cookie and opens `/`, or opens `/login?error=cancelled` when no code arrives and `/login?error=failed` when the exchange fails; `/login` shows the matching sentence.
- `/` reads the session on the server and shows the signed-in email and "로그아웃", or that the server cannot be reached.
- Sign-out is the Server Action `signOut`, through the `auth` feature's `actions.ts`. It revokes this browser's session alone (`scope: "local"`), so the phone stays signed in, and opens `/login`. When Supabase cannot be reached it returns the sentence the form shows.
- Each origin the app is served from must be in Supabase Auth's allowed redirect URLs as `<origin>/auth/callback`. Only the owner changes that list.

### Theme

- `web/src/styles/globals.css` declares the colour tokens of `app/lib/shared/theme.dart` ([`design.md`](design.md)) in `@theme`, under the same names in kebab case, and the radii `card` (24px) and `row` (16px). Under `prefers-color-scheme: dark` it overrides each colour with the dark set.
- `web/src/styles/__tests__/theme-tokens.test.ts` fails when a token differs from theme.dart's, in either set.
- `web/src/styles/fonts` links to `app/assets/fonts/`. `next.config.ts` names that directory in `turbopackAdditionalRoots`, and the root layout bundles Regular, Medium, SemiBold and Bold with `next/font/local`; nothing is downloaded at run time.
- Buttons are at least 52 px high (`min-h-13`), and the focus ring is a visible outline.

### Checks

- `web.sh`, at the repository root, implements the `web/` part of `make lint`, `format`, `test` and `build`. Where `node` is missing it prints that it skipped; where the host's Node.js differs from `web/.nvmrc` it fails. It installs the locked packages when they are missing or older than the lock file.
- `make lint`: ESLint with typescript-eslint's type-checked strict rules, `tsc --noEmit`, the portability check and the Node.js release check.
- `make format`: Prettier, over the files git tracks or would track.
- `make test`: the Vitest suite (`web/src/**/__tests__/`), then, where Docker and buildx answer, the image built and run, its health and non-root uid asserted, and the Playwright specs in `web/e2e/` run against it.
- `make build`: `next build`, then the image where Docker and buildx answer.
- CI runs `web.sh` on the Node.js that `.github/workflows/ci.yml` installs for the WebAssembly tests, on both jobs; `web.sh` fails there when it differs from `web/.nvmrc`. Only the ubuntu job has Docker, so it alone runs the image and the e2e specs.

### Tests

- `web/src/app/__tests__/sign-in-gate.test.ts` lists every route from the `page.tsx` and `route.ts` files under `web/src/app/`, and runs each through the proxy's matcher and the proxy, against Supabase Auth substituted with MSW: signed out, every route but the three public ones goes to `/login`; signed in, none does.
- `web/src/app/__tests__/home.test.tsx` renders the home page's account section over a session cookie and shows the server-side read: the email, the unreachable state, and the redirect without a session.
- `web/src/app/auth/callback/__tests__/route.test.ts`, `web/src/features/auth/__tests__/` and `web/src/app/login/__tests__/` cover the code exchange, sign-out and the sentences shown.
- `web/e2e/sign-in.spec.ts` runs against the image: `/` lands on `/login`, the sign-in request leaves for Supabase with this origin's callback, the theme follows dark mode, and `/api/health` answers.

## Rationale

- [ADR 0019](adr/0019-web-app-stack-portability-and-sign-in.md) records the stack, the portability rules, why the image is built from the repository root, why the font is linked rather than copied, why sign-in starts in the browser, and why sign-out is local.
- Issue #44 records the decisions made by the PM.

## Open questions

- None.
