# ADR 0022: Study on the web with the engine in the browser, writing each answer in order through a Server Action

> Status: accepted; its engine in the browser alone superseded by ADR-0047
> Date: 2026-10-15

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #45 (M8c) lets a signed-in user study on the web the decks made on the phone. The PM decided there:
  - the web app writes the rows the phone's sync writes ([ADR 0015](0015-sync-protocol-and-conflict-policy.md)): an answer inserts one review and upserts its card's state, each with the edit's `updated_at`, and deletes nothing;
  - the card's state comes from the WebAssembly engine ([ADR 0018](0018-engine-as-webassembly.md)), and a toggle replays the card's answers of the session with their fuzz factors ([ADR 0007](0007-study-swipe-screen-and-session-toggle.md), [ADR 0012](0012-fuzz-review-intervals.md));
  - the next card shows at once and the write runs after it; a failed write is shown with a retry, and the answer stays in the stack.
- Where the engine runs, with Next.js 16.4.1 and Turbopack:
  - in the Server Action, reading the `.wasm` with `readFile(new URL(…, import.meta.url))`: in a Route Handler the build copied the file to `.next/server/assets/`, but in the module graph of a page's Server Action it emitted it as a client asset, `/_next/static/media/…`, so the server would read a path its disk does not hold;
  - in the browser: the glue `wasm-bindgen --target web` writes fetches the `.wasm` named beside it, and the build serves that file from `/_next/static/media/`, which the image already copies.
- stack-nextjs.md §3 makes a Server Action, called from `onClick`, the mutation path of the app's own UI, and §5 has it verify the session itself.
- A toggle's update finds no row while its answer's insert has not been stored, so a write that failed cannot be passed by the writes behind it.
- `web/Dockerfile.dockerignore` admits only `web/` and `app/assets/fonts/` ([ADR 0019](0019-web-app-stack-portability-and-sign-in.md)); the build follows a link to `engine-wasm/pkg/`, outside both.
- `structure.md` gives the web app its features but, with `auth` alone, left open whether one feature may depend on another. `study` needs `decks`' cards; the deck screens show `study`'s counts.

## Decision

- **Engine.** The engine runs in the browser. `web/src/features/study/engine-wasm` links to `engine-wasm/pkg/`, admitted by `turbopackAdditionalRoots`; the generated glue fetches its `.wasm` as a static file. The study screen fetches it when it opens.
- **Writes.** A write replays the card's answers of the session from its state when the session opened, in the browser, and the Server Action `recordAnswer` verifies the session and stores the review and the state. An answer's insert ignores a review already stored; a toggle moves the rating only where the server's edit is older.
- **Order.** The screen changes first; its writes go out one at a time, in the order given. A failed write stops the queue: it and every write behind it wait until the user's "다시 시도" sends them again.
- **Image.** `web/Dockerfile.dockerignore` admits `engine-wasm/pkg/` beside `web/` and `app/assets/fonts/`, and the build stage copies it. This supersedes ADR 0019's image context of `web/` and the fonts alone.
- **Features.** A web feature may depend on a sibling only through its entry points, and the graph stays acyclic: `study` depends on `decks`, and a route hands `study`'s counts to `decks`' components.
- **e2e.** The study spec runs against the app built with a throwaway local stack's URL and key, which a build freezes, served by its standalone server, as [ADR 0014](0014-database-tests-on-a-stack-of-their-own.md) runs the database tests.

## Consequences

- The server runs no WebAssembly, and the browser fetches about 83 KB once per page that studies.
- The server stores the state the browser computed, as it stores the state a phone pushes; row-level security limits either to the user's own rows.
- A write is idempotent until it succeeds, so a retry after a lost answer writes no second review.
- One unreachable write holds every later answer of the session until the retry, and leaving the page while writes wait drops them, which the page asks before allowing.
- A change of `pkg/` reaches the web app at its next build, and the image takes it from the repository root.
- `make test` builds the web app once more, for the stack, and starts a third throwaway stack.

## Signs the decision was wrong

- Turbopack stops emitting the glue's `.wasm` as a static file, or a browser the app supports cannot instantiate it.
- Users report answers lost after a page closes, because writes waited behind one that failed.
- A second writer of the same rows needs the server to compute the state, so a client's state can no longer be stored as sent.
- The two features grow imports both ways, and the route's composition becomes the place most changes land.
