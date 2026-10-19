# ADR 0080: Document each web feature in its own responsibility document beside web.md, and name each test file's behaviour in one line

> Status: accepted
> Date: 2026-10-19

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #242**, from the QA audit of 2026-10-19: `docs/architecture/web.md` held the web's stack, image, sign-in, shell, deck and study pages, admin area, legal documents, theme, checks and tests in one document, 85,970 bytes on `main` at `676b1ba9e8c37822ad51a77e0fd81941f6eb903e`. About a quarter of it was a §Tests section listing, test by test, what each file asserts.
- **The rules met:**
  - `docs/convention/documentation.md` §Keep it maintainable, "One file, one responsibility": "A file that outgrows a single topic does not get a Contents list as a remedy — it gets split by responsibility, with each piece serving one topic."
  - The same section, "No implementation detail": a list of a test file's assertions is line-level behaviour, edited with every change to the test.
  - `docs/architecture/README.md` §Rules, rule 5: "Every domain or concern has a responsibility document."
- **What `structure.md` left open:** it makes the web feature the unit "as a domain is under `app/lib/`, and is earned the same way", and each app domain has its own document. It did not say where a web feature is documented. Under rule 7, that point is settled in an ADR.
- **The PM's decision**, relayed in the dispatch of #242: one document per web feature beside `web.md`, which keeps the stack, the shell and the foundations; and test sections of one line per file. A fact that an inventory line held and no decision stated moves into the feature document's decisions, not out of the documents.
- **Alternatives considered:**
  - **Each web feature in the matching app domain's document**, the web's study beside the app's in `study.md`. The web's features are separate code with their own routes, reads and tests, and `admin` and `legal` match no app domain. Two clients' surfaces in one document would make each section say which client it speaks of.
  - **Keeping the inventories, moved verbatim.** They would still transcribe each test's assertions, which the test files hold.

## Decision

- **Each web feature has its own responsibility document**, named `web-<feature>.md` beside `web.md`: `web-account.md`, `web-admin.md`, `web-decks.md`, `web-study.md` and `web-legal.md`. A new feature adds its document in the pull request that adds the feature, as rule 5 asks.
  - Each opens by naming the app domain or server document its territory abuts.
  - Each holds its pages, reads, components' behaviour and tests, and links the ADRs behind them.
- **`web.md` keeps what is the web app's own concern:**
  - the project and its packages;
  - portability and the image;
  - the session and the proxy;
  - the shell, the failure pages and the skeletons;
  - the server reads every feature makes;
  - the theme;
  - the checks.
  - Its tests section lists the foundations', the shell's and the end-to-end tests.
- **A test section names each test file and the behaviour it covers, in one line, and the file holds the cases.**
  - A test substitute's behaviour that other tests rely on, such as the PostgREST substitute's refusals, stays a decision in the document.
  - A fact that an assertion list held and no decision stated becomes a decision line.
- `structure.md` states the first rule among its current decisions for the web app.

## Consequences

- A change to one web feature edits that feature's document, and a change to a test edits its document only when what the test covers changes.
- The app's documents still list their tests assertion by assertion (`study.md`, `server.md`, `sync.md`, `home.md`, `account.md`, `sharing.md`, `ai-extraction.md`). This ADR decides the web documents' form only; bringing the others to it is a later change.

## Signs the decision was wrong

- A web feature's document and its app domain's document repeat the same rule, and the two drift apart.
- A test's one line no longer tells a reviewer which file to open for a behaviour.
