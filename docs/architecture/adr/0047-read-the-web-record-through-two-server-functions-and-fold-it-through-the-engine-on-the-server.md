# ADR 0047: Read the web's 기록 through two server functions, and fold it through the engine on the server

> Status: accepted
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #91's Part B, as the PM split it on 2026-10-17, puts ADR 0037's metrics on the web's `/record` page: the web's copies of the phone's functions, tested on the same fixed histories, and the read they need, "a server function in the manner of `study_days_before` if the browser should not pull the whole history".
- The metrics need every stored answer: the retention, the study days and both streaks group every live answer by study day, and the mastered weeks fold every live card's answers through the engine to know each card's interval at each week's end. The recall bands need the engine's retrievability of each live card's state ([ADR 0037](0037-define-the-record-tab-s-retention-recall-bands-mastered-weeks-and-study-days-and-compute-them-on-the-device.md)).
- The web reads only what each page shows, on the server, in pages of 1000 rows ([ADR 0030](0030-read-only-what-each-web-page-shows-and-size-the-web-from-the-app-tokens.md)). A year of daily study holds tens of thousands of reviews, tens of pages.
- The engine is the WebAssembly module of `engine-wasm/pkg/`, which the web runs in the browser alone ([ADR 0022](0022-study-on-the-web-with-the-engine-in-the-browser.md), whose consequences say the server runs none). No SQL folds FSRS, and a second copy of FSRS in TypeScript would drift from the engine.
- On `main` at `98ca47972a74fbd387be00e792a1a84b81da6979`, Turbopack turns `new URL("./….wasm", import.meta.url)` in a server module into the static path `/_next/static/media/…`: a static asset, which `.next/standalone` holds no copy of (the Dockerfile copies `.next/static` beside it), so a server running its traced files alone finds no file there.
- Alternatives considered, put to the PM on the worker's question in the dispatch of Part B, who decided on 2026-10-17:
  - Pass the states and the answers to a client component that folds them in the browser after the module loads. Rejected: it ships the whole history to the browser, and two charts would appear late.
  - Leave the recall bands and the mastered weeks off the web. Rejected: the issue asks for #90's content.
  - Read every review through PostgREST and group it in TypeScript. Tens of requests per page load where two serve.

## Decision

- **Days.** `public.study_record_days(time_zone, before)` returns one row per study day with a live answer before `before`, oldest first, each from 04:00 to 04:00 in the zone named: its start, the distinct cards answered, its scheduled reviews and those answered "good", by ADR 0037's definition. The web's `recordDays` holds the same definition in TypeScript, tested on the phone's histories, and the Vitest fake answers the function with it; a pgTAP test runs the function on the same histories.
- **Cards.** `public.study_record_cards()` returns one row per live card of a live deck with a live answer: its live state or none, and its live answers' ratings, times and fuzz factors in the order given.
- **Both functions** run as the caller, `stable`, with an empty `search_path`, executable by `authenticated` alone, and change no row. Migration `20261018090001_study_record.sql` adds them; its version follows `20261018090000_study_days.sql`, the latest on `main`, on the PM's instruction.
- **Engine on the server.** The `/record` page's Server Component reads both in two requests sent together, parses every row at the boundary, and runs the engine on the server: `web/src/features/study/engine-server.ts` instantiates the same module from its file's bytes, once per server process, read from the project's root at the link `src/features/study/engine-wasm`. `next.config.ts` traces the file into the `/record` route's output with `outputFileTracingIncludes`, so the standalone server and each serverless function carry it; no Vercel-only feature is used. A state or answer the engine refuses reads as `unreadable`.
- **Supersessions.** This replaces ADR 0022's engine in the browser alone: the study screen still runs it there, and the record page also runs it on the server.

## Consequences

- The browser receives the computed metrics and the study days, never the history; the page renders whole on the server.
- Each `/record` load reads every live answer twice on the server, grouped in Postgres and folded in Node. Locally, over 996 reviews of 200 cards, the page's warm load took 189 ms (`supabase/test-web.sh`'s record test); a far longer history may need a summary kept per card.
- The module is 83 KB in the server's memory once loaded; a cold function pays its read and instantiation once.
- The standalone output carries the module through a link to `next_additional_roots/engine/`, which the image copies with the rest of `.next/standalone`.

## Signs the decision was wrong

- The record page's load grows past #69's bar of 1 s for users with long histories.
- A host stops carrying traced files into its functions, or the link the standalone output keeps is lost in a copy, and the page fails to load the module.
- The phone's and the web's figures differ for the same user, because the function and `recordDays` drifted.
