# ADR 0019: Build the web app on Next.js in `web/`, portable between Vercel and a container, with Google sign-in through Supabase Auth's cookie session

> Status: accepted
> Date: 2026-10-15

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #44 (M8, part b) adds a web app a user signs into with the same Google account as on the phone. The PM decided there:
  - the stack: Next.js App Router with strict TypeScript and the `src/` layout, Tailwind CSS v4 with CSS-first `@theme`, Vitest with Testing Library and MSW, Playwright for e2e, pinned with a lock file;
  - portability, after the owner's decision of 2026-10-14 to deploy on Vercel first and on a personal cluster later: no Vercel-only feature or `@vercel/*` runtime package, the Node.js runtime only, `output: "standalone"`, configuration only through `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` read by `src/env.ts`, and `GET /api/health` answering 200 without Supabase;
  - a multi-stage `web/Dockerfile` with a non-root user and `FROM …@sha256:` digests, built, run and checked in CI;
  - sign-in through Supabase Auth with Google and `@supabase/ssr`, mandatory as on the phone ([ADR 0017](0017-require-sign-in-through-an-account-gate.md)), redirecting through `<origin>/auth/callback`;
  - the design tokens of `app/lib/shared/theme.dart` in `@theme`, light and dark following `prefers-color-scheme`, with IBM Plex Sans KR self-hosted from `app/assets/fonts/`.
- `NEXT_PUBLIC_` values are inlined at `next build` and frozen there (stack-nextjs §8). A value the container reads only at start would need the client to receive it some other way.
- Alternatives considered for the font, which is about 11 MB in four files:
  - a copy under `web/`: the repository grows by 11 MB, and two copies can drift;
  - `turbopack.root` at the repository root, so a relative path can reach `app/assets/fonts/`: Turbopack resolves and may watch every file under its root, `app/build/` and the Rust `target/` directories included;
  - a symbolic link inside `web/` with `experimental.turbopackAdditionalRoots` naming its target, which Next.js 16.4.1 documents for files outside the project reached across a symlink.
- Alternatives considered for starting sign-in:
  - a Server Action that calls `signInWithOAuth` and redirects: it needs this deployment's origin on the server, from request headers that a proxy in front of the container may rewrite;
  - the browser client's `signInWithOAuth`, which reads the origin from the page and stores the PKCE verifier in a cookie the callback reads.
- Alternatives considered for sign-out: Supabase's default `global` scope revokes every session of the user, the phone's included; `local` revokes this browser's alone.
- TypeScript 7.0.2 and ESLint 10.12.0 are the newest releases. typescript-eslint 8.71.2 accepts TypeScript `>=4.8.4 <6.1.0`, and eslint-plugin-react, eslint-plugin-import and eslint-plugin-jsx-a11y, which eslint-config-next 16.4.1 depends on, accept ESLint 9 at most.

## Decision

- **Project.** `web/` is a Next.js 16.4.1 project of its own, laid out as stack-nextjs.md §1 describes, on Node.js 24.22.0 named in `web/.nvmrc`, with TypeScript 6.0.3 and ESLint 9.39.5. Its packages are pinned exactly in `web/package.json` and locked in `web/package-lock.json`.
- **Structure.** The web app's unit is the feature under `web/src/features/`, reached only through the `index.ts` and `actions.ts` stack-nextjs §13 names, with `web/src/lib/` below every feature. It has no single composition site: Next.js calls each route, Server Action and the proxy as an entry point of its own, and each constructs its Supabase client through `web/src/lib/supabase/`. Nothing under `web/` imports code from `app/`.
- **Portability.** No `@vercel/` package and no `runtime = 'edge'` appear under `web/`; `make lint` fails on either, and checks its pattern against control lines first. The build is `output: "standalone"`. The two `NEXT_PUBLIC_` variables are parsed once in `src/env.ts`, which fails the build on a missing or malformed value or a key that is not a publishable key. Because they are frozen at build, an image is built for one Supabase project, with both values as build arguments.
- **Image.** `web/Dockerfile` is built from the repository root, so that the fonts are in its context; `web/Dockerfile.dockerignore` admits only `web/` and `app/assets/fonts/`. It has three stages from the same digest of `node:24.22.0-trixie-slim`, and runs `node server.js` as the base image's `node` user. Dependabot's `docker` entry for `/web` proposes the digest's move.
- **Sign-in.** The session lives in `@supabase/ssr`'s cookies. `src/proxy.ts` refreshes it on every request its matcher selects (all but `/api`, `_next/static`, `_next/image` and `favicon.ico`), verifies it with `getClaims`, and redirects a signed-out visitor to `/login` from every path but `/login` and `/auth/callback`. A Supabase that cannot be reached is not a sign-out: the request goes through, and a page that reads the session says the server cannot be reached. The sign-in button calls the browser client's `signInWithOAuth` for Google with `redirectTo` set to the page's origin plus `/auth/callback`, a Route Handler that exchanges the code for the session cookie. Sign-out is a Server Action that revokes this browser's session alone (`scope: "local"`).
- **Design.** `src/styles/globals.css` declares theme.dart's colour tokens and radii in `@theme`, overrides the colours under `prefers-color-scheme: dark`, and a test fails when they differ from theme.dart. `src/styles/fonts` is a symbolic link to `app/assets/fonts/`, which `turbopackAdditionalRoots` admits, and `next/font/local` bundles the four weights into the build.
- **Checks.** `web.sh` runs `make lint`, `format`, `test` and `build` over `web/`, and skips with the reason where `node` is missing. `make test` runs the Vitest suite, then, where Docker and buildx answer, builds the image, runs it, asserts it answers `/api/health` and runs as a non-root uid, and runs the Playwright specs against it.

## Consequences

- One image runs the same under `docker run` locally, in CI and on a cluster; Vercel builds the same source with its own Node.js runtime.
- A second Supabase project means a second image build, not a new environment variable at start.
- Vercel's project must include files outside its root directory, `web/`, for the font link to resolve.
- The e2e specs run only where Docker answers: on the ubuntu CI job, not the macOS one.
- TypeScript and ESLint stay a major release behind until typescript-eslint and the React lint plugins accept the newer ones; Dependabot's `npm` entry ignores those majors.
- The web app and the phone share an account and its sessions, and signing out of one leaves the other signed in.

## Signs the decision was wrong

- Vercel or the image build fails to resolve `src/styles/fonts`, or a Next.js release drops `turbopackAdditionalRoots`.
- The cluster deployment needs one image across Supabase projects, and per-project builds become the bottleneck.
- Users sign in successfully at Google and land on `/login?error=failed`, because the PKCE verifier cookie did not survive the round trip.
- A request with a valid session is sent to `/login`, or one without a session reaches a page, through a path the matcher excludes.
- A feature needs a Vercel-only service, and the portability check is worked around rather than the decision revisited.
