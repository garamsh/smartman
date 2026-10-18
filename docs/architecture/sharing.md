# Sharing

The `sharing` domain: publishing a deck, and browsing, previewing, copying, reporting and blocking other users' public decks.

## Current decisions

### Surface and location

- The domain lives in `app/lib/sharing/`; its public surface is `app/lib/sharing/sharing.dart`, with internals under `app/lib/sharing/src/` ([ADR 0002](adr/0002-domain-public-surface-and-shared-database.md)).
- The surface exports what the composition site constructs, what `home/` composes and what tests substitute:
  - `SharingService`, which browses, publishes and unpublishes, and its copy targets `CopyTarget`, `CopyIntoNewDeck` and `CopyIntoDeck`;
  - `sharingServiceProvider`, the service or null while the app has none, which hides every entry to sharing, and `onlineProvider`, whether the device is online as the service reports it, offline without one;
  - `SharingServer`, the seam to the server, and `SupabaseSharingServer`, its PostgREST implementation;
  - `Reachability`, the network state, and `DeviceReachability`, over `connectivity_plus`;
  - the model: `PublicDeckSummary`, `PublicCard`, `DisplayName`, `BrowseSort`, `ReportReason`, `ReportOutcome`;
  - the failures: `SharingFailure`, `SharingOffline`, `SharingRejected`, `SharingFailed`, `DeckNoLongerPublic`.
- It depends on `deck` (the repository, the model, `importCards`, `CardSplitRow`) and `account` (`UserId`) through their surfaces. `deck` does not reach it: `home/`'s screens read `sharingServiceProvider`, which the composition site overrides with the service it constructs ([`home.md`](home.md), [ADR 0039](adr/0039-name-every-top-level-folder-by-its-responsibility-compose-across-domains-in-a-home-shell-and-keep-seams-off-screens.md)). It imports `supabase_flutter` for PostgREST, beside `account` and `sync` ([ADR 0020](adr/0020-public-decks-in-a-sharing-domain.md)).
- `main.dart` builds `SupabaseSharingServer` over `connectAccount`'s client; a build that cannot sign in has no client, so no sharing and no entries for it.

### Publishing

- The deck screen's deck menu offers "공개하기" on a private deck and "비공개로 전환" on a public one. While `Reachability` reports no connection, the item is disabled with "인터넷에 연결되면 바꿀 수 있어요".
- "공개하기" opens a sheet: the display name the first time (2 to 20 characters, trimmed), an optional description of at most 300 characters, and the required checkbox "부적절하거나 저작권을 침해하는 내용은 공개하지 않을게요", then "공개", disabled until it is checked.
- A publish writes the server first, then the device: the profile when it is new, then the deck's row with `visibility = public`, `published_at` and the description, then the local row through `DeckRepository.setVisibility`, unsynced, for sync to push as usual. A refused publish leaves the deck private on the device and says why in the sheet.
- "비공개로 전환" writes `visibility = private` the same way and keeps the description for the next publish.
- A public deck shows a "공개" chip on its row on the home screen and beside its name on the deck screen.

### Browsing

- "공개 덱 둘러보기" opens the browse screen: the row under the 덱 tab's deck rows, and the first-run home's text action ([`home.md`](home.md), [ADR 0067](adr/0067-start-a-deck-or-a-card-from-one-sheet-that-holds-the-photo-source-and-name-public-decks-once.md)).
- The screen has a large title, "공개 덱", a search over name and description (ignoring case, run 300 ms after typing pauses), and a segmented "최신순" / "가져오기 많은 순".
- Each row shows the deck's name and "{display name} · 카드 n장 · 가져오기 m회". The listing comes from `list_public_decks` ([`server.md`](server.md)), at most 100 decks; decks of users the user blocked are absent.
- Offline, the screen shows "인터넷에 연결되지 않았어요. 연결되면 공개 덱을 볼 수 있어요." and lists once the connection returns; a failed request shows its message with "다시 시도".

### Preview and copy

- A tap opens the preview: the name, the owner's display name with the counts, the description, and the first 20 cards as split rows, with "카드 n장 중 처음 20장" when there are more.
- "내 덱으로 가져오기" opens a sheet: "새 덱으로", the default, creates a deck named after the public one; "기존 덱에 추가" takes one of the user's decks and a duplicate option, "건너뛰기" by default, or "뒷면 합치기" or "새 카드로 추가".
- A copy reads every live card of the deck, calls `record_deck_import`, which counts the user's first copy of the deck and no later one, and refuses with `DeckNoLongerPublic` when the deck is no longer public. It then saves through `DeckRepository.importCards` with `FromPublicDeck`, so each added card is an ordinary card with `source = shared` and `origin_deck_id`, and the duplicate rule of [`deck.md`](deck.md) applies. A copy into a new deck adds every card, duplicates included. Nothing links the copy to the source afterwards.
- Copies hold the text of each side, as imports do.

### Reporting and blocking

- The preview's menu offers "신고하기" and "이 사용자 차단".
- "신고하기" asks in a sheet for a reason, inappropriate, spam, copyright or other, with "신고하기" as its one action and no cancel, and files it once; a second report of the same deck says "이미 신고한 덱이에요".
- "이 사용자 차단" asks for confirmation, then blocks the owner and returns to the browse screen, which lists again without the owner's decks.

### Failures

- Each expected failure is a `SharingFailure`, mapped from PostgREST's codes as `sync` maps them ([`sync.md`](sync.md)): `SharingRejected`, `SharingOffline` (also no answer within 20 seconds), `SharingFailed`, and `DeckNoLongerPublic`.
- Screens show a `SharingFailure`, or a `DeckFailure` from the local write, as a localized message: in a snack bar for an action, in the sheet for a publish or a copy, and in place of a list. Any other error propagates.

### Interface

- Every string comes from the shared ARB set, in Korean and English. Icon buttons carry tooltips, headings are marked as headers, progress indicators carry a label, and a sheet's error is a live region.
- The screens follow [`design.md`](design.md) and are built from the shared components ([ADR 0021](adr/0021-type-and-spacing-scales-and-a-shared-component-layer.md)): browse rows are `AppListRow`s, the preview's cards `CardSplitRow`s, the publish, import and report sheets `AppSheet`s, the block confirmation `showAppConfirm`, the chip `AppChip`, and each screen's or sheet's one primary action an `AppButton` at the bottom.

### Tests

- `app/test/sharing/sharing_service_test.dart` — display name validation, publish and unpublish order and failure, the first publish's name, and copies as a new deck and into a deck with each duplicate option, over an in-memory database and a substituted server (`app/test/sharing/fakes.dart`).
- `app/test/sharing/browse_screen_test.dart` — the 덱 tab's "공개 덱 둘러보기" as the one way in beside a new-deck sheet that offers none, the title "공개 덱", the listing, search, sort, the offline state, a failed request, and the guidelines in both themes.
- `app/test/sharing/public_deck_screen_test.dart` — the preview, each import option, a deck no longer public, report and block, and the guidelines in both themes.
- `app/test/sharing/publish_test.dart` — publish, display name and description validation, the required agreement, a refused publish, unpublish, the chips, the offline menu item, and the guidelines in both themes.
- `app/test/screenshots/screenshots_test.dart` draws the deck menu, the publish sheet, the public chips, browse, the preview, and the import, report and block sheets in both themes when asked to.
- `app/test/sharing/supabase_sharing_server_test.dart` — `SupabaseSharingServer` over a substituted HTTP client: a publish sends its created, updated and published times in UTC, truncated to the millisecond through `storedTime` as sync's pushes are ([ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md) §2).
- `app/test/sharing/sharing_server_test.dart` — `SupabaseSharingServer` against the local stack `supabase/test-sync.sh` starts: publish, list, preview, copy count, report, block, and that sync never pulls another user's public deck. Each step the file takes on the stack is bounded by `SupabaseSharingServer`'s 20-second request timeout, the bound past which the app counts the server as offline: every sharing and sync request, and each user's sign-up, which retries within that bound while Auth answers that the request may be retried. The file sets no bound over a whole test, whose duration is the sum of its steps and grows with the host's load (issue #78).

## Rationale

- [ADR 0020](adr/0020-public-decks-in-a-sharing-domain.md) records why sharing is its own domain, why a publish writes the server first, how a copy reuses the deck import, and why pulls filter by owner.
- [ADR 0039](adr/0039-name-every-top-level-folder-by-its-responsibility-compose-across-domains-in-a-home-shell-and-keep-seams-off-screens.md) records why `home/` reaches sharing through its surface rather than `deck` through a provider.
- Issue #29 records the decisions made by the PM, and its amendments.

## Open questions

- Whether the browse screen should page beyond its first 100 decks. No listing holds that many yet.
- Whether a user should be able to see and undo their blocks. No screen lists them today.
