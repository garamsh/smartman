# ADR 0077: Drop the review and card state tombstones that nothing writes

> Status: accepted
> Date: 2026-10-19

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- [ADR 0010](0010-server-schema-and-row-level-security.md) gave every synced table a `deleted_at` tombstone, and [ADR 0015](0015-sync-protocol-and-conflict-policy.md) the same on the device. Issue #219, read on `main` at `3df760f83b743317cc4ab9fa4fe8fd5dddea443f`, found that nothing writes one on `reviews` or `card_states`:
  - a client may update only a review's `rating` and `updated_at` and holds no delete privilege on `reviews`, and ADR 0015 says "clients cannot tombstone reviews";
  - the device's two card state writers, the fold and the study write, leave `deleted_at` null; deleting a deck or a card tombstones the deck and its cards alone, and a deleted card keeps its state ([`deck.md`](../deck.md));
  - the web writes `deleted_at` null and deletes nothing.
- Built around the state anyway: the `reviews_delete` policy, a partial index per client on live reviews, the index `card_states_tombstone_revision` with the purge's deletion of card state tombstones ([ADR 0034](0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md) §3), the device's deletion of them ([ADR 0041](0041-raise-each-pull-cursor-to-a-watermark-read-under-the-user-s-lock-and-strip-local-tombstones-in-place.md)), and a `deleted_at is null` filter on every read of either table.
- The owner decided on 2026-10-19 (issue #250) that until the first store release no older app build is kept working, so no build that sends or reads the columns needs serving.

## Decision

- **Reviews have no tombstone.** A review is written once, its rating may change, and it goes only with its account, as [ADR 0026](0026-delete-the-account-through-an-edge-function.md)'s cascade removes it.
- **Card states have no tombstone.** A card state is replaced by its fold or its next answer, stays with its card when the card is deleted, and goes with its card's row or its account.
- `reviews.deleted_at` and `card_states.deleted_at` are dropped on the server and on the device (schema v7), with what reads them:
  - the server's `reviews_delete` policy and `card_states_tombstone_revision` index, and the purge's deletion of card state tombstones;
  - the device's deletion of card state tombstones in its local purge;
  - every `deleted_at is null` filter on a read of either table, on the server, the device and the web.
- The partial indexes on live reviews become whole indexes on the same columns, `reviews_user_id_reviewed_at` on the server and `reviews_reviewed_at` on the device, since every row they held is every row.
- Decks and cards keep their tombstones, written by deleting a deck or a card.

## Consequences

- A review or a card state with `deleted_at` set can no longer be represented, so no reader has to leave one out.
- A migration on each side: the server's drops two columns and rewrites the functions that read them, which merging deploys; the device's rebuilds two tables. Every value dropped is null, so no row changes.
- Removing a review, should the product ever need it, takes a new decision: a tombstone written by a defined deletion, or a delete privilege and a way for devices to learn of it.

## Signs the decision was wrong

- A feature needs to remove one answer, such as undoing a mistaken one after the session, and has to add the column back.
- A device pulls a card state for a card it no longer holds and has no way to tell the server's copy is gone.
