# Architecture

Current architecture of the system and the decisions behind it. This file is the index; workers read it before touching code, the PM keeps it honest.

## Structure

- **Responsibility documents** (one `.md` per domain or concern, e.g. `memory.md`, `gateway.md`) — the single source of truth for how the system is shaped *now*. To know the current state, read only these.
- **`adr/`** — the record of individual decisions: direction taken, context, rejected alternatives.

## Rules

1. **Responsibility document skeleton**: current decisions (consolidated) / rationale summary with links to the relevant ADRs / open questions. Do not copy ADR content — synthesize the present state.
2. **ADRs are append-only.** Once merged, the body is frozen. Exceptions: updating the status field (`accepted` → `superseded by ADR-XXXX`), fixing typos or broken links, and appending a dated entry under `## Errata` when the decision stands but a fact supporting it was wrong — the erratum names what falsified it, and the original text stays intact. A changed decision means a new ADR that supersedes the old one — never an edit.
3. **Decisions land in pairs.** A PR that adds or supersedes an ADR must update the affected responsibility documents in the same PR. A PR with only one of the two is rejected — the final state must always live in the responsibility documents.
4. Keep this index current: every responsibility document and every ADR is listed here. An ADR covers a decision that changes a project rule — a settled choice that does not affect the rules does not earn one.
5. **Every domain or concern has a responsibility document.** The PR that introduces one adds its document; the PR that removes one deletes it. A system with no code yet has no more than `structure.md` (rule 6), and that is the correct state.
6. **Structural rules live in `structure.md`.** The shape chosen at bootstrap imposes rules — what the unit is, what may reference what, when a new one is earned — and they belong in the responsibility document for that concern, where a reviewer cites one by line and a correction is an ordinary edit. Not the ADR: rule 2 freezes that body, so superseding the choice of shape would be the price of fixing a rule's wording.
7. **A point the structural rules leave to the project is settled in an ADR** — the one recording the shape where the question is met at bootstrap, a later one where it is met later. Which side is taken decides what counts as a defect, so it is a decision under rule 4, and the ADR still holds the record after bootstrap. Nothing obliges a project to settle a question it has not met: until then the point waits under `structure.md`'s open questions, where it binds nothing, and moves into that document's current decisions when the project takes a side.
8. **Structural rules yield only to what a framework imposes.** Where `structure.md` and a convention file decide the same case differently, `structure.md` governs, unless the stack-specific file that applies decides it as its framework imposes it — the alternative fails to build or run, so the project cannot restate it. A stack file's spelling of a structural rule is not that: the rule it spells is `structure.md`'s. The shape chosen at bootstrap is this project's own refinement of what a stack-neutral file states for every project. A project with no `structure.md` meets no such conflict, and this rule asks nothing of it.

## Index

- `structure.md` — the structural rules of the app: the domain as unit, what may reference what, and the composition site.
- `deck.md` — the `deck` domain: decks, cards, content blocks, the card key, and the duplicate rule.
- `engine.md` — the scheduling engine: FSRS-6 in the pure Rust crate `engine/`, its public surface, and its reference values.
- `account.md` — the `account` domain: the gate that requires sign-in, Google sign-in through Supabase Auth, the session, and the configuration it reads from `app/config/`.
- `design.md` — the app's design language: the principles every screen follows, where each is applied today, and the shared light and dark theme.
- `study.md` — the `study` domain: the study session over one or more decks, its queue and stored card state, and the flutter_rust_bridge crate and bindings through which it calls the engine.
- `sync.md` — the `sync` domain: the local sync columns and cursor, a run's pull and push, the conflict rules, when sync runs, sign-out, and the status the account screen shows.
- `server.md` — the Supabase schema the app syncs to: the four tables, row-level security, server-set revisions, tombstones, the extraction count, and the pgTAP tests `make test` runs.
- `ai-extraction.md` — the `extract-cards` Edge Function: its contract, limits and privacy, how its model is switched, the eval that chooses the model, and the app's `photo_import` domain that calls it.
- `adr/0001-domain-structure.md` — partition the app by domain, with siblings reached only through their public surface.
- `adr/0002-domain-public-surface-and-shared-database.md` — declare a domain's surface in one library file, and keep the drift database below the domains.
- `adr/0003-fsrs-engine.md` — schedule with FSRS-6 as py-fsrs 6.3.2 implements it, without learning steps or fuzz; its no-fuzz decision superseded by ADR 0012.
- `adr/0004-flutter-rust-bridge.md` — bridge the engine through a flutter_rust_bridge crate in `app/rust/` built with native assets, with its bindings in the `study` domain.
- `adr/0005-study-queue-and-card-state.md` — queue a session from due then new cards, re-show a "Don't know" after three cards, and store each card's state parts in `card_states`.
- `adr/0006-account-native-google-sign-in.md` — sign in with native Google Sign-In through Supabase Auth in an `account` domain, configured per environment from `app/config/`, with flavors deferred to M7; its sole import of `supabase_flutter` superseded by ADR 0015, and its optional sign-in by ADR 0017.
- `adr/0007-study-swipe-screen-and-session-toggle.md` — answer by swiping a split card, keep every session answer in a toggleable stack, and reschedule a toggle by replaying the card's session answers; supersedes ADR 0005's screen and correction rules.
- `adr/0008-google-sign-in-nonce.md` — send Google sign-in a nonce drawn once per run, its SHA-256 hex to Google and the raw value to Supabase, superseding ADR 0006's "No nonce is sent".
- `adr/0009-multi-deck-session-and-random-queue-order.md` — study a non-empty selection of decks in one session, with a header count and a "study all" action, and draw the queue's order and the re-show gap from one seeded random source; supersedes ADR 0005's queue order, re-show gap and single-deck entry point.
- `adr/0010-server-schema-and-row-level-security.md` — sync to a per-user Supabase schema guarded by row-level security, with server-set revisions from one sequence drawn under a per-user lock, composite foreign keys between a user's rows, and pgTAP tests in `make test`; its "Tests" decision superseded by ADR 0014.
- `adr/0011-shared-app-theme-bundled-font-and-today-builder.md` — draw every screen from one shared light and dark theme with a bundled IBM Plex Sans KR, chosen per device, and show study's counts in deck screens through one builder provider; supersedes ADR 0009's header provider and ADR 0007's study colour constants.
- `adr/0012-fuzz-review-intervals.md` — fuzz review intervals as py-fsrs 6.3.2 does, with a factor in `[0, 1)` the app draws from the session's random source and stores on each review; supersedes ADR 0003's "The engine does not fuzz".
- `adr/0013-extract-cards-function-and-eval.md` — extract cards in a dependency-free Deno Edge Function with an optional retry model, limit it per user through one locked SQL function, and choose its model with a budget-capped eval in `tools/eval/`.
- `adr/0014-database-tests-on-a-stack-of-their-own.md` — run the database tests on a throwaway local stack per run, under its own project id and a reserved port, stopped on every exit; supersedes ADR 0010's "Tests" decision.
- `adr/0015-sync-protocol-and-conflict-policy.md` — sync in the background by pull then push per table, with last-writer-wins edits, winning tombstones, unioned reviews and recomputed card states, a database owned by one account, and `sync` importing `supabase_flutter`; supersedes ADR 0006's "the only domain importing `supabase_flutter`".
- `adr/0017-require-sign-in-through-an-account-gate.md` — require sign-in through an `AccountGate` at the app's root that opens the app from the session the device holds, without waiting on the network, and closes every screen over it when the session ends; supersedes ADR 0006's optional sign-in.
- `adr/0000-template.md` — the template every ADR is written from.
