# Sync

The `sync` domain: keeping the local database and the signed-in account's rows on the server in step, in the background.

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
- With `account`, it is one of the two domains that import `supabase_flutter`, for PostgREST only ([ADR 0015](adr/0015-sync-protocol-and-conflict-policy.md)).

### Local schema

- Schema v4 gives `decks`, `cards`, `reviews` and `card_states` the columns `updated_at`, `deleted_at` (a tombstone) and `dirty` (not yet pushed). `dirty` defaults to set, so every local insert is unsynced; the v3 to v4 migration leaves every existing row unsynced, and dates a review's `updated_at` by its `reviewed_at` and a card state's by its `last_review`.
- `sync_state` holds at most one row: the owning account's id, and per table the pull cursor, the highest server `revision` applied. No row means no account owns the database.
- Screens never show a tombstoned row ([`deck.md`](deck.md), [`study.md`](study.md)).

### A run

- A run, for the signed-in account:
  1. claims the database: with no owner, its rows become the account's; with another owner, every synced row, the owner and the cursors are deleted first, so another account's rows are never pushed;
  2. pulls `decks`, `cards`, `reviews`, then `card_states`, each in pages of 500 rows above its cursor, lowest revision first, applying each page and moving the cursor in one drift transaction;
  3. recomputes the state of every card a pulled review was added to or changed the rating of;
  4. pushes the unsynced rows of each table in the same order, 500 per request, then clears `dirty` on each row still as it was pushed; a row edited during the push stays unsynced.
- Pull comes before push, so a local row that loses its merge is never sent.
- A pulled row whose parent is not yet on the device ends its page there, below the cursor; the pull starts over, up to three passes, and a parent still missing then fails the run as `SyncFailed`.
- Each pushed row carries `user_id`, the run's account; a session belonging to another account is refused by row-level security.

### Conflicts

- Decks and cards: a tombstone wins over a live row, whichever was written later; otherwise the later `updated_at` wins. On a tie an unsynced local edit wins, since the server has not seen it; otherwise the server's.
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

### Tests

- `app/test/sync/merge_test.dart` — each conflict rule, with a control.
- `app/test/sync/synchronizer_test.dart` — push, pull, the conflict rules end to end, the state fold and ownership, over two in-memory databases and a substituted server (`app/test/sync/fake_sync_server.dart`) with the server's revision, ownership and review rules.
- `app/test/sync/sync_controller_test.dart` — when runs start, retry, `push` and `clear`.
- `app/test/sync/answer_path_test.dart` — the composed app answers and advances while a run never finishes.
- `app/test/sync/sync_status_test.dart` — each status on the account screen, the retry, and the tap target and contrast guidelines in both themes.
- `app/test/sync/two_devices_test.dart` — two in-memory databases syncing through `SupabaseSyncServer` as one new account against a local stack. `make test` runs it through `supabase/test-sync.sh`, which starts a throwaway stack with Postgres, Auth, PostgREST and the gateway, under its own project id and reserved database and API ports, as [ADR 0014](adr/0014-database-tests-on-a-stack-of-their-own.md) does for the database tests, and stops it on every exit. Without Docker the script prints the skip and why; the plain `flutter test` run skips the file with its reason.

## Rationale

- [ADR 0015](adr/0015-sync-protocol-and-conflict-policy.md) records the protocol, the conflict policy, ownership, when sync runs, and why `sync` imports `supabase_flutter`.
- [ADR 0010](adr/0010-server-schema-and-row-level-security.md) records the server schema sync runs against.
- Issue #24 records the decisions made by the PM.

## Open questions

- A study session writes a card's state from the state it opened with. A review of that card pulled during the session is left out of that write; the card's state is right again once another review of it, or another device's state recomputed with both, is pulled. Whether the session should reread the state before writing is open.
