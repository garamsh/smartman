# ADR 0143: Edit a stored card on the web from its row, the later `updated_at` winning

> Status: accepted
> Date: 2026-11-02

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #548 has the web's direct entry write a card as a list of 칸 and open any existing card. [ADR 0137](0137-frame-a-card-by-its-blocks-each-block-type-deciding-whether-it-has-a-front-and-a-back.md) decides the 칸, their fields and the editor's groups. It does not decide how the web reaches a stored card, how the web writes one, or what the web does with 칸 it holds no media for.
- [ADR 0122](0122-create-decks-and-reviewed-cards-on-the-web.md) inserts new cards only and leaves "existing-card editing, public-deck browsing and full media/audio authoring" as separate work. Until this ADR the web's one write to a stored card was photo import's merged back.
- [ADR 0038](0038-lay-the-web-out-as-a-responsive-shell-with-a-side-menu-from-1024-px-and-a-tab-bar-below-it.md) hides a deck's answers until clicked, under a switch. `web-decks.md` kept that click "since the web edits no card", where a tap on the phone's row opens its editor ([ADR 0118](0118-name-each-concept-once-write-each-role-in-one-form-hold-every-screen-to-one-set-of-visual-details-and-redraw-settings-and-the-deck-screen-by-them.md)).
- `sync.md` settles a conflict on a card by the later `updated_at`, a tombstone winning over a live row. The web has no local copy, so it writes the server's row directly, as it writes a review's toggle "only where the server's edit is older".
- The web holds no media upload and draws no photo from the bucket.
- Alternatives considered:
  - **Keep the row's click and add a "편집" action on each row.** It keeps a reveal per card, at the price of a second control on every row and a screen the phone does not have. The phone's behaviour was taken.
  - **Compare the `updated_at` the page read and refuse any change since.** It protects an edit made elsewhere, and would be a rule the phone does not follow: a later edit wins on every other path.
  - **Build web media upload here.** ADR 0122 leaves it apart, and it needs preparing, a `media` row, Storage and box drawing. It is its own issue.

## Decision

- **A row opens the card.** A click on a row of a deck's page opens that card in the editor, as a tap on the phone's does. "뒷면 보기" is the one reveal; the reveal of one row by a click goes.
- **The write.** A save of a stored card writes its 칸 to `front`, `[]` to `back`, `free` at version 2, the key of its new 칸 and the save's time as `updated_at`. Its id, `source`, `origin_deck_id`, `created_at`, reviews and card state are left as they are.
- **The later `updated_at` wins.** The update applies only where the row's `updated_at` is older than the save's and the row is live. A row a later edit holds is left as it is, and the save says so and keeps the draft. A tombstone wins: a card deleted elsewhere is not written.
- **A key that collides** is refused unless the user allows it, as the phone's `editCard`: "이 덱에 이미 있는 카드예요", then "그래도 저장".
- **Read-only.** A card of a later template, or holding a block this build does not know, whether in a 칸 list or on a side, opens with its content and the phone's words, "새 버전의 앱에서 만든 카드라 이 버전에서는 편집할 수 없어요. 앱을 업데이트해 주세요.", and no field. The server action refuses it the same way, so a stale page cannot write over it.
- **사진 and 소리.** A stored 사진 or 소리 opens as a group of its own: it keeps its media and boxes, moves and is deleted by its ⋯, and changes side by its chips while it has a side. The web's "칸 추가" offers 글, 단어, 빈칸 문장 and 표, not ADR 0137's six, until web media upload lands. A write naming a photo or sound the stored card does not hold is refused, and a new card holds none. A file whose 칸 is deleted on the web is not released, since the web has no deletion queue.
- **No delete.** The web still deletes no card.

## Consequences

- ADR 0122's restriction to new cards is superseded, and its "existing-card editing" is this work. Its media and public-deck work stay apart.
- ADR 0038's answers hidden until clicked is superseded for the click; its switch stands.
- A web save can overwrite an edit made on a phone earlier than the save and not yet seen on the page, as any later edit does under `sync.md`.
- A web save refused as later keeps its draft; the user reopens the deck to see the later edit.
- The photo or sound of a 칸 deleted on the web stays in the bucket until the follow-up that releases it.

## Signs the decision was wrong

- Users ask to reveal one card on the deck page, often enough that the row needs a second control.
- Users lose phone edits to web saves of a page left open, which would ask for a check of the version read.
- Web users delete photo 칸 in numbers that leave real storage behind before the release lands.
