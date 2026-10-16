# Home

The app's `home/` shell: the signed-in screens that show more than one domain or lead from one domain into another, and how they compose the domains.

## Current decisions

### Surface and location

- The shell lives in `app/lib/home/`; its surface is `app/lib/home/home.dart`, which exports `HomeScreen`, with internals under `app/lib/home/src/` ([ADR 0039](adr/0039-name-every-top-level-folder-by-its-responsibility-compose-across-domains-in-a-home-shell-and-keep-seams-off-screens.md), [`structure.md`](structure.md)):
  - `home_screen.dart` — `HomeScreen`, with the first-run home, the today card, the decks' label and each row's today chip;
  - `deck_screen.dart` — `DeckScreen`, a deck's page, with its count pills.
- The composition site passes `HomeScreen` to `account`'s `AccountGate` as the screen it opens while an account is signed in ([`account.md`](account.md)). Nothing else imports `home/`.

### Composition

- `home/` sits above every domain: it imports the domains' surfaces and the foundations, and builds each screen from the domains' exported widgets, handing values and callbacks between them, as a web route does.
- It holds no reads and no rules of its own: it declares no provider and imports no database. What a screen shows, it reads through a domain's providers and widgets.
- The home screen composes:
  - `deck`'s `decksProvider`, `cardCountsProvider`, `DeckRow`, `showNameSheet` and `DeckRepository`, for the decks, their rows and a new deck ([`deck.md`](deck.md));
  - `study`'s `TodayCounter`, which counts the cards left today for a selection, for the today card and each row's chip, and `StudyScreen`, which "모두 학습", "계속 학습" and "학습 (n)" open ([`study.md`](study.md));
  - `account`'s `AccountAvatar` on the account button, and `AccountScreen`, given `sync`'s `SyncStatusView` as the status it shows ([`account.md`](account.md), [`sync.md`](sync.md));
  - `sharing`'s `sharingServiceProvider`, for the browse screen ([`sharing.md`](sharing.md));
  - `photo_import`'s `photoImportProvider`, for the photo button ([`ai-extraction.md`](ai-extraction.md)).
- The deck screen composes `deck`'s `deckProvider`, `cardsProvider`, `CardSplitRow`, `CardEditorScreen`, `showNameSheet` and `DeckRepository`; `study`'s `TodayCounter` and `StudyScreen`; `sharing`'s `sharingServiceProvider` and `onlineProvider`, for publishing; and `photo_import`'s `photoImportProvider`.
- A `DeckRow` takes what it shows of today as a widget, which the home screen builds from `TodayCounter`: the deck's place for something `study` draws ([`structure.md`](structure.md)).

### The home screen and the selection

- The home screen's top bar holds the horizontal lockup, 30 high and read as the app's name, as its heading; at its right, with sharing, a "둘러보기" icon button that opens the browse screen, then the account button, the account's initial in a 32 px circle ([ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)).
- Below it, the today card for a selection of every deck, on the brand's navy (the raised surface in the dark theme) with the symbol faint in its corner: "오늘 할 카드", the count large with "장", "복습 x · 새 카드 y · 약 m분", in a backlog "밀린 복습을 마칠 때까지 새 카드는 쉬어요." ([`study.md`](study.md)), and a white "모두 학습" with a play icon, which opens one study session over every deck ([ADR 0009](adr/0009-multi-deck-session-and-random-queue-order.md)). The minutes are the count times the time one card takes, which `study` reads from the user's latest reviews ([`study.md`](study.md)), rounded up.
- With no card left today, the today card reads "오늘 할 카드를 다 했어요" in place of the count and shows a white "계속 학습" in place of "모두 학습", which opens the same session; the study screen then opens on the completion card or on nothing to study ([`study.md`](study.md), [ADR 0040](adr/0040-keep-every-study-button-enabled-at-zero-cards-left.md)).
- "내 덱 n" labels the decks, with the hint "길게 눌러 여러 덱 선택".
- Each deck is a `DeckRow` ([`deck.md`](deck.md)), with a brand-tint "오늘 n" chip when a session over it would study n > 0 cards now. A count that cannot be read shows an icon whose tooltip says why.
- The bottom bar holds "새 덱", and "사진으로 만들기" when photo import exists. A photo import that saved opens the deck it saved into.
- Before the first deck, the home screen is the first-run home in place of the today card, the rows and the bottom bar: the mascot in a white circle, "첫 덱을 만들어 볼까요?", one line on how to start, then "사진으로 만들기" when photo import exists, "직접 만들기", which opens the new-deck sheet, and "공개 덱 둘러보기" with sharing.
- The new-deck sheet is titled "새 덱 만들기" with "이름은 나중에도 바꿀 수 있어요." under it, a "덱 이름" field, and "만들기".
- A tap opens a deck's screen; a long-press enters selection mode with that deck selected.
- In selection mode:
  - a tap, or a long-press, adds or removes a deck;
  - the app bar shows how many decks are selected, a clear action that leaves the mode, and "학습 (n)", which opens one study session over the selected decks;
  - a deck deleted while selected leaves the selection, and "학습 (n)" is disabled while the selection is empty;
  - each deck's row exposes whether it is selected to screen readers.

### The deck screen

- The deck screen has a back button and a deck menu that renames or deletes the deck; deleting returns to the home screen. With sharing, the menu also offers "공개하기" or "비공개로 전환", disabled with a one-line reason while offline, and a public deck shows a "공개" chip beside its name.
- Below the deck name, at 26/800, three white pills, "카드 n", "복습 x" and "새 카드 y", in a backlog the same sentence as the today card, and the primary "학습하기 · n장" with a play icon, where n is the size of the session it opens. It opens the session whatever the count, 0 included, and while the count is pending or cannot be read ([ADR 0040](adr/0040-keep-every-study-button-enabled-at-zero-cards-left.md)).
- A 48 px search field keeps the cards whose front or back text holds the search, ignoring case.
- The cards are one white rounded group of `CardSplitRow`s with one-pixel separators: front and back in two columns split by a thin divider, the back in the quieter ink; a tap opens it in the editor.
- The bottom bar holds "카드 추가", and "사진으로 추가" when photo import exists, both secondary. A photo import that saved into another deck replaces this screen with that deck's; one into this deck returns here.

### Interface

- Every string the screens show comes from the shared ARB set, and every tap target carries a semantic label: its text, or a tooltip for an icon button.
- The screens follow the principles and the theme of [`design.md`](design.md), with `design`'s `BottomActions` as their bottom bars.

### Tests

- `app/test/home/home_screen_test.dart` and `app/test/home/deck_screen_test.dart` drive the two screens over an in-memory database, with `deck`'s and `study`'s real repositories and study's clock, zone and scheduler substituted (`app/test/home/home_data.dart`, `app/test/home/deck_screens.dart`). The counts come from seeded cards and states; a deck repository that fails to list a deck's cards gives the unreadable count, and a study repository whose pace never arrives the pending one. A study button's session is the `StudyScreen` it pushes, read for its decks.
- The sharing tests drive the home and deck screens through `app/test/sharing/sharing_app.dart` the same way ([`sharing.md`](sharing.md)).
- `app/test/architecture_test.dart` fails on an import of `home/` from anywhere but `main.dart`, on a file in `home/` that declares a provider or imports the database, and on a domain file that names a screen another domain exports ([`structure.md`](structure.md)).

## Rationale

- [ADR 0039](adr/0039-name-every-top-level-folder-by-its-responsibility-compose-across-domains-in-a-home-shell-and-keep-seams-off-screens.md) records why screens that span domains live in a shell above them, why a domain hosts no other domain's screen through a provider, and why the shell holds no reads of its own.
- [ADR 0009](adr/0009-multi-deck-session-and-random-queue-order.md) records the session over several decks, the selection mode and the today card.
- [ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md) records the v2 home and deck screens and the today card's minutes.
- [ADR 0040](adr/0040-keep-every-study-button-enabled-at-zero-cards-left.md) records why every study button stays enabled at zero cards left, and the done today card offers "계속 학습".
- Issue #110 records the move of the two screens out of `deck` into the shell; issue #19 records the selection mode and the today card, and issue #22 the screens.

## Open questions

- None.
