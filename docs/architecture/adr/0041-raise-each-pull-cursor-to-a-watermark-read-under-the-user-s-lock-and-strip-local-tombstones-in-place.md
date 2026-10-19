# ADR 0041: Raise each pull cursor to a watermark read under the user's lock, and strip local tombstones in place

> Status: accepted; the local purge's deletion of card state tombstones superseded by ADR-0077
> Date: 2026-10-17

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #106 builds step 4 of [ADR 0034](0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md) §9: schema v6, v7 ids, horizon-aware sync and the local purge. Two rules of ADR 0034 §3, read against the app at `d543ed1e35fe7c3af2fd306ae3d03f461c770e72`, fail as written. The PM decided both on 2026-10-17, in #106.
- **The rebuild rule.** ADR 0034 §3: "A device whose cursor for a table is above zero but below the horizon may have missed a purged tombstone. It rebuilds that table". It also says "Ninety days bounds how often that full pull happens".
  - A table's cursor is the revision of the last of the user's own rows the device applied: `SyncStore._apply` moves it to the last row of each pulled page (`app/lib/sync/src/sync_store.dart`). It moves only when one of the user's rows in that table changes.
  - The horizon is a mark of `private.revision`, the one sequence every user's writes to every table draw from (`supabase/migrations/20261014155006_sync_schema.sql`). Once the purge job runs (step 6), it rises daily.
  - So a table the user has not written for 90 days keeps its cursor while the horizon passes it, and every run after that rebuilds the table, whether or not the device ever missed a delete. Example: the cards of a user who studies every day but has finished adding cards. Every run, after each study session, would pull every card again: 10,000 cards at 500 a page is 20 requests a run, with no end. A device that syncs daily would rebuild as often as one left unsynced for a year.
  - This step is an app release. A release cannot be withdrawn from the devices that took it (ADR 0034 §9, step 4), so the rule has to be right before step 6 turns the purge on.
- **The local purge.** ADR 0034 §3: the device "deletes a tombstoned card that no review references, with its state, and a tombstoned deck that no card references". A device cannot know that no review will reference the card later:
  - device X answers card C offline, so the review R is unsynced;
  - device Y deletes C and syncs;
  - device Z syncs, pulls C's tombstone, holds no review of C, and deletes C;
  - X syncs and pushes R. The server accepts it, since C's tombstone is still there: the server's purge is 90 days away, and would then strip C, which R references, rather than delete it;
  - Z's next run pulls R, whose card it no longer holds. Z's cards cursor is past C's revision, so C never comes back. The page stops before R, the pull's three passes fail, and the run fails as `SyncFailed` on every run from then on. R never reaches Z.
  - The server's own purge is safe, because it deletes only tombstones below the horizon. By then no review can still reach them: a review pushed for a deleted card is refused with `23503`. The phone keeps no per-row revision, so it cannot apply the same test.
  - Measured in #106's pull request: `app/test/sync/synchronizer_test.dart`'s test of this scenario fails with ADR 0034's delete rule in place, and passes with the strip below.
- Alternatives passed over:
  1. For the rebuild:
     - keeping the rule as written, and settling it before step 6. The installed releases would keep the rule, and step 6 would then start full pulls on phones that cannot be updated;
     - raising the cursor to the horizon after each complete pull. The horizon rises daily, so a table nobody writes would still be rebuilt once a day;
     - reading the sequence's last value without the user's lock. One of the user's transactions may have drawn a revision below the value read and still be uncommitted. The pull would then miss that row, and the cursor would pass it.
  2. For the local purge:
     - a last pull pass that rebuilds the parent tables when a parent is still missing. It adds a recovery branch for a failure that stripping in place removes outright ([`simplicity.md`](../../convention/simplicity.md) §Core principle);
     - deleting only tombstones below the horizon, as the server does. The phone keeps no per-row revision to compare with it.

## Decision

### 1. The watermark

- `public.sync_horizon()` returns one row: `horizon` and `watermark`.
  - `horizon` is the revision the last purge purged below, kept in `private.sync_horizon`, one row that holds 0 until a purge runs.
  - `watermark` is `private.revision`'s last value. It is read after the function takes the caller's revision lock: the transaction-level advisory lock keyed by `hashtextextended(user_id::text, 0)`, which the revision trigger takes before it draws.
- Why the read is safe:
  - each of the caller's writing transactions draws its revision while holding that lock, and holds it to commit;
  - so when the function gets the lock, every revision of the caller's rows at or below the value it reads is committed;
  - any later draw is above that value: the sequence hands out values in increasing order, and its cache is 1, Postgres's default, so no session holds values drawn ahead.
  - A pull that starts after the call and completes has therefore returned every row of the caller's at or below the watermark.
- The function is `security definer`, `volatile` (it takes a lock), sets `search_path = ''`, and is executable by `authenticated` only.
- A run reads it once, before it pulls. When a table's pull completes, the table's cursor becomes the larger of the cursor and the watermark.
- A table is rebuilt when its cursor is above zero and below the horizon, as ADR 0034 §3 states. The cursor is now at least the watermark of the last completed pull, so this happens only to a device that has not completed a pull since the horizon's mark was taken, about 90 days earlier. The bound of 90 days holds again.

### 2. The local purge

- After a run that leaves nothing unsynced, the device:
  - deletes every card state tombstone;
  - strips every card tombstone in place: `front` and `back` become `[]` and `card_key` `''`;
  - strips every deck tombstone in place: `name` becomes `''` and `description` null, and the deck is made private.
- The device never deletes a card or deck tombstone. A review that arrives later still finds its card, and nothing cascades to a review.
- The strip is not marked unsynced. The server strips its own copy in its purge.
- The rows a rebuild removes are the only card and deck rows a device deletes: rows the server no longer holds, which no later review can reach.
- The server's purge is unchanged.

This supersedes two passages of ADR 0034 §3: the cursor the rebuild rule reads, and the local purge's deletion of unreferenced card and deck tombstones.

## Consequences

- A device that syncs regularly never rebuilds a table, however long the table goes unwritten. A device left unsynced for about 90 days rebuilds each table once.
- Each run takes the user's revision lock once, briefly. A run that starts while one of the user's writes is in progress waits for that write to commit.
- Card and deck tombstones stay on the device for as long as the database does, without their content. A stripped card row holds two 36-character ids, three 24-character times, its source and empty content: under 200 bytes. So 10,000 deleted cards hold under 2 MB. A rebuild still removes the rows the server has purged, and signing out or another account's claim removes them all.
- A device that took this release never fails a run over a review whose card it purged.

## Signs the decision was wrong

- A device that synced in the last 90 days rebuilds a table. That would mean the watermark does not cover what the pull returned.
- A pull misses a row a device should hold, and the row has a revision at or below a watermark that device stored. That would mean a revision was drawn outside the lock.
- Stripped tombstones grow to rival live rows in a phone's database, which would argue for a local purge that can test the horizon, with a revision kept per row.
- Calls to `sync_horizon()` show among `supabase inspect db outliers`, or the lock wait among slow runs, which would mean writes hold the user's lock longer than a run can wait.
