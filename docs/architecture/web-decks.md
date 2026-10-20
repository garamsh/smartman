# Web decks

The web's `decks` feature: the deck list, a deck's page, the first run with no deck, the card content blocks and how a side is drawn. The pages' shell and the server reads they share are [`web.md`](web.md)'s; the app's `deck` domain is [`deck.md`](deck.md).

## Current decisions

### Reads

- `/decks` (덱) reads what `/` (오늘) reads, `decks`' `readDeckList` and `study`'s `readToday` and `readRecentRetention` together ([`web-study.md`](web-study.md)), without the streak; `/decks/[id]` reads `readLibrary` over the deck it names (that deck and its cards with both sides) and `readToday`, together; its title reads the same `readLibrary` through React's `cache` (`read-deck.ts` beside the page), so the page and its title make one request (#281).

### Pages

- `/decks` (덱): "내 덱 n", "덱 검색", which keeps the decks whose name holds it, ignoring case, and a row per deck, two columns from 1024 px: its tile, name, mastered and learning bar, mastered in ink and learning in ink at 45% with no gap between them, as `design.md` §Theme and the phone draw it (#325), and "n장 중 m장 익힘", "공개" when published, "오늘 n" when n > 0, and a chevron, opening the deck. The web creates no deck and has no selection mode.
- `/decks/[id]`, titled "name · smartman", or "덱 · smartman" when the read fails: a breadcrumb "덱 / name", its "덱" a back chevron and the word on a target at least `tap-target` high and wide (#281); the deck's tile, its name and "카드 n장", with "· 공개" when published; the navy card "오늘 이 덱": "오늘 할 카드" with "장 · 약 m분", in a backlog the same sentence, "m / n 익힘" over a bar of mastered, learning and new, in `on-hero`, `on-hero` at 45% and `on-hero` at 20%, with no gap between the shares (#325), read as one sentence, and "학습하기" with its Enter key, a link to the study page whatever n is ([ADR 0040](adr/0040-keep-every-study-button-enabled-at-zero-cards-left.md)), and none while the deck holds no card ([ADR 0066](adr/0066-open-a-deck-made-by-hand-and-lead-an-empty-deck-and-a-cardless-today-tab-to-adding-cards.md)); "카드 검색", which keeps the cards whose front or back holds it, ignoring case; a row pinned as the list scrolls with "카드 n" and the "뜻 보기" switch (issue #142); and the cards, oldest first, in a grid of 240 px columns, each a button with its front and its back hidden behind a bar, read as "front, 뒷면 가려짐", until clicked, then "front, 뒷면 back". Each side is drawn through `SideText`, a senses block's labels as the study page draws them ([ADR 0075](adr/0075-store-a-vocabulary-card-s-senses-as-a-typed-block-and-show-each-label-in-brackets-before-its-meaning.md)). A whole card's button, one whose front holds a cloze or a table block, shows its front through `WholeCard` in place of the front and the bar, its blanks empty until clicked, then filled, its front read with each blank "빈칸" ([ADR 0068](adr/0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md)). The switch starts off each time the page opens; changing it sets every card to its state, and a click then sets that card apart until the switch next changes; the search's results follow. There is no "카드 추가" and no deck menu: the web creates nothing and has no deck action. A deck that does not exist, or is deleted, is not found, and so is an address id that is not a uuid: `decks`' `parseDeckId` reads it before any request, so a malformed id never reaches the server as a failed read (#237).
- 오늘 and 덱 for a user with no deck show, under their headings, in place of the today card and the list, the phone's first run: the mascot in its 128 px surface circle, "첫 덱을 만들어 볼까요?" and "덱은 휴대폰 앱에서 만들어요. 단어장 사진을 찍거나 직접 입력하면 여기에도 보여요.". It offers no action: the web creates nothing, and has no public-deck browsing to offer "공개 덱 둘러보기".
- A deck with no card shows, in place of the search and the cards, the same first-run layout: the mascot, "아직 카드가 없어요", the phone's words for an empty deck, and "카드는 휴대폰 앱에서 덱에 추가해요. 추가한 카드는 여기에도 보여요.", with no action, since the web adds no card (`decks`' `EmptyDeck`, #276).
- A deck or card search that matches nothing says "찾는 덱이 없어요. 다른 단어로 검색해 보세요." or "찾는 카드가 없어요. 다른 단어로 검색해 보세요.", the app's words.

### Card content

- `web/src/features/decks/card-content.ts` reads, refuses, fills and speaks a card's `cloze`, `table` and `senses` blocks as the phone's `app/lib/deck/` does, on `app/test/deck/content_test.dart`'s cases and the phone's `spokenContent`, the back the server's senses migration writes among them, as `supabase/tests/senses_migration_test.sql` asserts its stored text. `WholeCard` (`web/src/features/decks/components/whole-card.tsx`) draws a whole card, and `SideText` a side with a senses block's labels ([`web-study.md`](web-study.md) for the study page's use).
- A deck's tile takes the tint the app gives the same id.

### Tests

Each line names a file and what it covers; the file holds the cases. The deck list on 덱 is tested with 오늘 in `web/src/app/(shell)/__tests__/today.test.tsx` ([`web-study.md`](web-study.md)).

- `web/src/app/(shell)/decks/[id]/__tests__/deck.test.tsx` — the deck page: its header and counts, the hidden backs, "뜻 보기", search, whole and senses cards, the empty deck, "학습하기" at zero, the way back to 덱 and its target, a failed read under its way back and heading, a deleted deck and a malformed id not found.
- `web/src/features/decks/__tests__/card-content.test.ts` — the content blocks read, refused, filled and spoken on the app's cases.
- `web/src/features/decks/__tests__/progress-shades.test.tsx` — a deck row's progress shares in ink and ink at 45%, with no gap.
- `web/src/features/decks/__tests__/deck-tint.test.ts` — a deck's tile tint against the app's for the same id.

## Rationale

- [ADR 0030](adr/0030-read-only-what-each-web-page-shows-and-size-the-web-from-the-app-tokens.md) records why each page reads only what it shows.
- [ADR 0038](adr/0038-lay-the-web-out-as-a-responsive-shell-with-a-side-menu-from-1024-px-and-a-tab-bar-below-it.md) records what the PM settled for Part A of #91 on these pages: no 카드 추가 or deck menu, and 덱 without creation or selection.
- [ADR 0040](adr/0040-keep-every-study-button-enabled-at-zero-cards-left.md) records why the deck page's study link opens the study page at zero cards left.
- [ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md) records why the public chip waited for #69.
- [ADR 0066](adr/0066-open-a-deck-made-by-hand-and-lead-an-empty-deck-and-a-cardless-today-tab-to-adding-cards.md) records why a deck with no card offers no study button.
- [ADR 0068](adr/0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md) records the table and cloze blocks and how the deck page draws them whole, as the phone does.
- [ADR 0075](adr/0075-store-a-vocabulary-card-s-senses-as-a-typed-block-and-show-each-label-in-brackets-before-its-meaning.md) records the senses block and how the deck page draws a sense's labels, as the phone does.

## Open questions

- None.
