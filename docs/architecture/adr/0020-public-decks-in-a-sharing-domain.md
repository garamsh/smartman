# ADR 0020: Share decks through a sharing domain that publishes on the server first and copies through the deck import

> Status: accepted
> Date: 2026-10-15

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- The owner decided on 2026-10-15 that decks can be made public and shared between users. Issue #29 records the PM's decisions, with amendments made after #24, #28 and #30 merged:
  - a deck's `visibility` is `private` or `public`, with `published_at` and a description of at most 300 characters; others see its current cards read-only, a copy is a snapshot, and unpublishing stops new views and copies;
  - a display name of 2 to 20 characters in `profiles`, shown with public decks instead of the email;
  - `deck_reports`, unique per reporter and deck, a deck hidden by a trigger after three distinct reporters, `user_blocks`, an `import_count` raised by a security-definer function, and pgTAP tests of each policy;
  - the browse, preview, import and publish screens, with reporting and blocking for the stores' user-generated content rules;
  - `visibility`, `published_at` and `description` synced as ordinary deck columns under [ADR 0015](0015-sync-protocol-and-conflict-policy.md) in local schema v5; `hidden` server-only, unwritable by clients through the column grant; `origin_deck_id` synced on cards, and `source` gaining `shared`;
  - publishing needs the network: the profile and the visibility are written to the server at once, and offline "공개하기" is disabled with a reason;
  - copying reuses `DeckRepository.importCards` and its `DuplicateChoice`, writing `source = shared` and the origin.
- The schema's row-level security let a session read only its own rows, so sync pulled every row the session could read ([ADR 0010](0010-server-schema-and-row-level-security.md)). A policy letting any user read public decks would have made every other user's public deck arrive in each pull.
- Widening `cards.source` replaces its check, and keeping `hidden` and `import_count` from clients takes the table-level insert and update grants on `decks` away. Neither changes a row. The PM approved both on 2026-10-15, and the owner approved pushing the migration to the remote project.
- [ADR 0015](0015-sync-protocol-and-conflict-policy.md) left `account` and `sync` the only domains importing `supabase_flutter`.

## Decision

- **Domain.** A new `sharing` domain in `app/lib/sharing/` holds the server seam (`SharingServer`, with `SupabaseSharingServer` for PostgREST), the network state (`Reachability`, with `DeviceReachability` over `connectivity_plus`), the screens, and `SharingService`. It depends on `deck` and `account` through their surfaces and imports `supabase_flutter` for PostgREST, a third domain to do so.
- **Seam in deck.** `deck` declares `DeckSharing` and `deckSharingProvider`, null by default, which the composition site overrides with `SharingService`; null hides the browse button and the publish item. `deck` does not depend on `sharing`.
- **Publishing.** A publish writes the profile when it is the first, then upserts the deck's row on the server with the new visibility and an edit time, then writes the device's row, unsynced. A publish the server refused leaves nothing on the device; one the device failed to store is pulled back by sync, whose newer edit time it carries. The upsert leaves `user_id` and `deleted_at` to the server, so a deck deleted on another device stays deleted.
- **Copying.** A copy reads the deck's live cards, asks `record_deck_import` whether the deck is still public, which also counts the copy, and then saves through `importCards` with `FromPublicDeck(origin)`. Copies are text, as imports are.
- **Server.** Public reads are added as separate select policies, so writes stay under the owner-only ones. The listing is `list_public_decks`, a function running as the caller, so row-level security decides what it reads and it leaves out the caller's blocks. Clients hold column grants on `decks` that omit `hidden` and `import_count`, as [ADR 0010](0010-server-schema-and-row-level-security.md) limits reviews.
- **Pulls filter by owner.** Each `SyncServer` pull takes the run's account and filters on `user_id`, so another user's public deck is never pulled.

## Consequences

- Publishing and copying need a connection; everything else in the app still works offline.
- Owner devices pull a deck again when it is copied or hidden, since those updates draw a new revision.
- A deck the device has not pushed yet is created on the server by the publish itself; its cards follow with the next sync, so a deck published offline-first may show few cards for a moment.
- `connectivity_plus` is a new plugin; an interface that is up but cannot reach the server is reported by the request, not by the menu.
- Copying a deck of more than 1000 cards takes one request per 1000.

## Signs the decision was wrong

- Users find decks they copied missing cards that the owner had at the time, which would mean the copy and the import count disagree on what was public.
- The listing slows as public decks grow, which would mean the per-deck card count in `list_public_decks` needs a stored count.
- Reports hide decks that should not be hidden often enough that the dashboard queue grows, which would mean three reporters is too few.
- Another screen needs the server for something `sync` does not carry, and a fourth domain imports `supabase_flutter`, which would mean one client seam should sit below the domains.
