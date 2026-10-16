# Sync

The `sync` domain: keeping the local database and the signed-in account's rows on the server in step, in the background, and the web app as a second writer of those rows.

## Current decisions

### Surface and location

- The domain lives in `app/lib/sync/`; its public surface is `app/lib/sync/sync.dart`, with internals under `app/lib/sync/src/` ([ADR 0002](adr/0002-domain-public-surface-and-shared-database.md)).
- The surface exports what the composition site constructs and overrides with:
  - `SyncServer`, the seam to the server, with `Pulled`; `SupabaseSyncServer`, its PostgREST implementation; and `connectSyncServer`, which picks the server for the account's connection;
  - `SyncStore`, `Synchronizer` and `SyncController`, and `syncControllerProvider`;
  - the status: `SyncStatus`, `SyncIdle`, `Syncing`, `Synced`, `SyncInterrupted`;
  - the failures: `SyncFailure`, `SyncOffline`, `SyncRejected`, `SyncFailed`;
  - `SyncStatusView`.
- The domain reads and writes the shared database directly. It uses `account`'s surface for the session (`AccountService`, `SignedIn`'s `UserId`, and the `SupabaseClient` of `AccountConnection`) and `study`'s for the fold (`Scheduler.fold`).
- `deck` and `study` do not import `sync`. `account` reaches it through `accountDataProvider` and `syncStatusProvider`, which the composition site overrides with the `SyncController` and `SyncStatusView` ([`account.md`](account.md)).
- With `account` and `sharing`, it is one of the domains that import `supabase_flutter`, for PostgREST only ([ADR 0015](adr/0015-sync-protocol-and-conflict-policy.md), [ADR 0020](adr/0020-public-decks-in-a-sharing-domain.md)).

### Local schema

- Schema v4 gives `decks`, `cards`, `reviews` and `card_states` the columns `updated_at`, `deleted_at` (a tombstone) and `dirty` (not yet pushed). `dirty` defaults to set, so every local insert is unsynced; the v3 to v4 migration leaves every existing row unsynced, and dates a review's `updated_at` by its `reviewed_at` and a card state's by its `last_review`.
- `sync_state` holds at most one row: the owning account's id, and per table the pull cursor, the highest server `revision` applied. No row means no account owns the database.
- Schema v5 adds `visibility`, `published_at` and `description` to `decks` and `origin_deck_id` to `cards`, and lets `source` be `shared`. The v4 to v5 migration leaves every deck private and rebuilds `cards` for its check, keeping every row ([`sharing.md`](sharing.md)).
- Screens never show a tombstoned row ([`deck.md`](deck.md), [`study.md`](study.md)).

### Target local schema and sync (not built yet)

[ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md) decides what follows. None of it is built: each bullet holds once its implementation issue merges. Until then the decisions above describe the app.

- **Ids.** Ids stay `TEXT` on the device, always in canonical lowercase uuid form, since the server's `uuid` returns them that way ([`server.md`](server.md)). The app creates new ids with `uuid`'s `v7()`, and the web creates them with the `uuid` npm package's `v7()` in place of `crypto.randomUUID()`.
- **Schema v6, time.** Schema v6 stores every `DateTime` column as ISO-8601 text in UTC (drift's `store_date_time_values_as_text`). Every write truncates to the millisecond, so text order is time order, and the precision matches what the web sends.
  - The v5 to v6 migration rebuilds each synced table with `TableMigration`, converting each column from Unix seconds. It keeps every row and its `dirty` flag, with foreign keys off, as the earlier rebuilds did.
  - Its migration test starts from v5 rows that are unsynced and tombstoned, and reads them back unchanged.
- **Schema v6, indexes:**
  - `cards_deck_id_created_at` on `(deck_id, created_at)`;
  - `cards_deck_id_card_key`, rebuilt as partial where `deleted_at IS NULL`;
  - `reviews_card_id_reviewed_at` on `(card_id, reviewed_at)`, which also covers the cascade from `cards`;
  - `reviews_live_reviewed_at` on `reviewed_at` where `deleted_at IS NULL`;
  - one `{table}_unsynced` index per synced table, partial on `"dirty"`.
  - Each partial index is declared with `TableIndex.sql`. A query reaches it only by repeating its term, so the check for unsynced rows reads `WHERE "dirty"`, not `dirty = 1`.
- **Study reads.** `StudyRepository.firstAnswersSince` groups only the cards answered since the day began, found through `reviews_live_reviewed_at`. The streak is read one probe of that index per study day, in place of reading every answer's time (`answerTimes`) ([`study.md`](study.md)).
- **No new local checks.** A check added on the device would have to hold for every stored row, or the table rebuild aborts and the database no longer opens. The server's checks are the authority, and a row they refuse fails the run as `SyncFailed`, as any constraint does.
- **Horizon.** A run first reads `sync_horizon()`. If a table's cursor is above zero but below the horizon, the device may have missed purged tombstones, so it rebuilds:
  - it pulls that table from revision 0, merging as usual;
  - it deletes each synced local row the pull did not return;
  - it then pushes as usual.
  - A pushed row refused for a parent the server no longer holds (`23503`) is deleted locally, since a delete elsewhere wins.
- **Local purge.** After a run that leaves no row unsynced, the device deletes its tombstoned decks, cards and card states. The device's foreign keys then delete those cards' reviews and states, as the server's purge does.
- **Order.** The server's purge job is turned on only after the app release that reads the horizon has shipped ([`server.md`](server.md)). Its first mark is taken that day, so its first purge comes 90 days later. A device still on an older release then misses a delete only if it also stayed unsynced through those 90 days.

### A run

- A run, for the signed-in account:
  1. claims the database: with no owner, its rows become the account's; with another owner, every synced row, the owner and the cursors are deleted first, so another account's rows are never pushed;
  2. pulls the account's own `decks`, `cards`, `reviews`, then `card_states`, each in pages of 500 rows above its cursor, lowest revision first, applying each page and moving the cursor in one drift transaction; a pull filters on `user_id`, since the session may also read other users' public decks and cards ([ADR 0020](adr/0020-public-decks-in-a-sharing-domain.md));
  3. recomputes the state of every card a pulled review was added to or changed the rating of;
  4. pushes the unsynced rows of each table in the same order, 500 per request, then clears `dirty` on each row still as it was pushed; a row edited during the push stays unsynced.
- Pull comes before push, so a local row that loses its merge is never sent.
- A pulled row whose parent is not yet on the device ends its page there, below the cursor; the pull starts over, up to three passes, and a parent still missing then fails the run as `SyncFailed`.
- Each pushed row carries `user_id`, the run's account; a session belonging to another account is refused by row-level security.

### Conflicts

- Decks and cards: a tombstone wins over a live row, whichever was written later; otherwise the later `updated_at` wins. A deck's visibility, publish time and description are columns of its row and follow the same rule, so a publish on one device reaches the others. On a tie an unsynced local edit wins, since the server has not seen it; otherwise the server's.
- Reviews: a union by id. A review on both sides keeps the rating of its later edit, with the same tie rule. On the server, a push inserts new reviews and changes an existing one's `rating` and `updated_at` only where the server's edit is older.
- Card states are never merged. A pulled state replaces a synced local one and gives way to an unsynced one. After a pull brings a review for a card, the card's state is recomputed by folding all its non-deleted reviews in `reviewed_at` order through the engine from a new card, each with its stored fuzz factor, and written unsynced where it differs.
- A row where the local copy is kept is marked unsynced, so the next push repairs the server's copy, which another device may have overwritten.
- Equal-key cards from two devices are distinct rows: both are kept, and the deck's duplicate rule shows them on the next edit.

### When it runs

- `SyncController` starts a run when an account signs in, at app start and on each resume while signed in, and three seconds after the last of a burst of local writes that left a row unsynced. A study session's answers are such writes, so the run after a session is the one after its last answer.
- One run at a time: a trigger during a run starts one more after it.
- Nothing on the study screen's answer path awaits a run; only sign-out's push and clear do.
- A failed run is retried after 5 seconds, doubling up to 5 minutes; a successful run or the retry button restarts the backoff.

### Sign-out

- `SyncController` is `account`'s `AccountData`. Sign-out first runs sync and reports whether nothing is left unsynced; the account screen then warns "동기화되지 않은 변경이 있어요" and lets the user cancel or sign out anyway.
- After signing out, the controller waits for the run under way, then deletes every synced row, the owner and the cursors, so the next account starts empty and pulls its own rows.

### Failures and status

- Every expected failure of a run is a `SyncFailure`:
  - `SyncOffline` — no connection, no answer within 20 seconds, or a server or gateway error;
  - `SyncRejected` — the session or a row-level security policy refused the request;
  - `SyncFailed` — the server answered with a row sync cannot read or a constraint it refused, or the local database failed.
- A failure is never shown as a blocking error. It becomes the status `SyncInterrupted`, which the account screen shows while signed in, one line read out as it changes: "동기화 중", "동기화됨", "오프라인 · 연결되면 동기화해요", or "동기화하지 못했어요" with "다시 시도".
- `SupabaseSyncServer` maps PostgREST's error codes: `42501`, `PGRST301`, `PGRST302`, 401 and 403 to `SyncRejected`; `PGRST000` to `PGRST002` and 500, 502, 503 and 504 to `SyncOffline`; any other to `SyncFailed`.

### The web app as a writer

- The web app keeps no local database: it writes the server's `reviews` and `card_states` directly, with the user's session, the same rows a phone's push sends, so the phone merges them by the rules above ([`web.md`](web.md), [ADR 0022](adr/0022-study-on-the-web-with-the-engine-in-the-browser.md)).
- An answer inserts its review, ignoring one already stored under its id, with `good` for "안다" and `again` for "모른다", its time, its duration on screen, a fuzz factor drawn for it, and `user_id`. A toggle changes that review's `rating` and `updated_at` only where the server's edit is older, as a push does.
- Either then upserts the card's `card_states` row with the state the engine computes, replaying the card's answers of the web session, each with its factor, from the state the session opened with.
- Every row takes the time of the edit as `updated_at`, and `deleted_at` stays null; the server sets `revision`. The web app deletes nothing.
- A phone pulls these rows like any other: the review is added to or changes the rating of its card's history, so the card's state is recomputed by the fold, and a pulled state replaces a synced one.

### Tests

- `app/test/sync/merge_test.dart` — each conflict rule, with a control.
- `app/test/sync/synchronizer_test.dart` — push, pull, the conflict rules end to end, the state fold and ownership, over two in-memory databases and a substituted server (`app/test/sync/fake_sync_server.dart`) with the server's revision, ownership and review rules.
- `app/test/sync/sync_controller_test.dart` — when runs start, retry, `push` and `clear`.
- `app/test/sync/answer_path_test.dart` — the composed app answers and advances while a run never finishes.
- `app/test/sync/sync_status_test.dart` — each status on the account screen, the retry, and the tap target and contrast guidelines in both themes.
- `app/test/sharing/sharing_server_test.dart`, run by the same script, checks that a run never pulls another account's public deck, and that a publish reaches the owner's other device.
- `app/test/sync/two_devices_test.dart` — two in-memory databases syncing through `SupabaseSyncServer` as one new account against a local stack, and an answer and its toggle written as the web app writes them, which both devices merge with an offline answer into the fold of the union. `make test` runs it through `supabase/test-sync.sh`, which starts a throwaway stack with Postgres, Auth, PostgREST and the gateway, under its own project id and reserved database and API ports, as [ADR 0014](adr/0014-database-tests-on-a-stack-of-their-own.md) does for the database tests, and stops it on every exit. Without Docker the script prints the skip and why; the plain `flutter test` run skips the file with its reason. Each step the file takes on the stack is bounded by `SupabaseSyncServer`'s 20-second request timeout, the bound past which the app counts the server as offline: every sync request, and the sign-up and the sign-in, which retry within that bound while Auth answers that the request may be retried. The file sets no bound over a whole test, whose duration is the sum of its steps and grows with the host's load (issue #47).

## Rationale

- [ADR 0015](adr/0015-sync-protocol-and-conflict-policy.md) records the protocol, the conflict policy, ownership, when sync runs, and why `sync` imports `supabase_flutter`.
- [ADR 0010](adr/0010-server-schema-and-row-level-security.md) records the server schema sync runs against.
- [ADR 0020](adr/0020-public-decks-in-a-sharing-domain.md) records why pulls filter by owner and how deck visibility syncs.
- [ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md) records the target local schema, the horizon and the local purge; issue #93 records the owner's direction.
- Issue #24 records the decisions made by the PM, issue #29 the synced deck and card columns of schema v5, and issue #45 those for the web app as a writer.

## Open questions

- A study session writes a card's state from the state it opened with, on the phone and on the web. A review of that card pulled or written elsewhere during the session is left out of that write; the card's state is right again once another review of it, or another device's state recomputed with both, is pulled. Whether the session should reread the state before writing is open.
