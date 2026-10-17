# Home

The app's `home/` shell: the signed-in screens that show more than one domain or lead from one domain into another, and how they compose the domains.

## Current decisions

### Surface and location

- The shell lives in `app/lib/home/`; its surface is `app/lib/home/home.dart`, which exports `HomeScreen`, with internals under `app/lib/home/src/` ([ADR 0039](adr/0039-name-every-top-level-folder-by-its-responsibility-compose-across-domains-in-a-home-shell-and-keep-seams-off-screens.md), [`structure.md`](structure.md)):
  - `home_screen.dart` — `HomeScreen`: the three tabs and their bar, or the first-run home before the first deck;
  - `today_tab.dart` — the 오늘 tab: the today, done and backlog cards, the next seven days and today's decks;
  - `decks_tab.dart` — the 덱 tab: the deck rows, their progress and today chips, the search and the selection mode;
  - `record_tab.dart` — the 기록 tab, a placeholder until issue #90;
  - `deck_screen.dart` — `DeckScreen`, a deck's page;
  - `new_deck_sheet.dart` and `option_sheet.dart` — the new-deck sheet and the sheet of options it and "카드 추가" open;
  - `progress_bar.dart` and `hero.dart` — the progress bar, and the navy card's shades and large count.
- The composition site passes `HomeScreen` to `account`'s `AccountGate` as the screen it opens while an account is signed in ([`account.md`](account.md)). Nothing else imports `home/`.

### Composition

- `home/` sits above every domain: it imports the domains' surfaces and the foundations, and builds each screen from the domains' exported widgets, handing values and callbacks between them, as a web route does.
- It holds no reads and no rules of its own: it declares no provider and imports no database. What a screen shows, it reads through a domain's providers and widgets.
- The tabs compose:
  - `deck`'s `decksProvider`, `cardCountsProvider`, `DeckRow`, `DeckTile`, `showNameSheet` and `DeckRepository`, for the decks, their rows and a new deck ([`deck.md`](deck.md));
  - `study`'s `TodayOverviewReader`, for the 오늘 tab's count, goal, streak and forecast; `TodayCounter`, for each deck's count; `ProgressCounter`, for each deck's progress; and `StudyScreen`, which every study button opens ([`study.md`](study.md));
  - `account`'s `AccountAvatar` on the account button, and `AccountScreen`, given `sync`'s `SyncStatusView` as the status it shows ([`account.md`](account.md), [`sync.md`](sync.md));
  - `sharing`'s `sharingServiceProvider`, for the browse screen ([`sharing.md`](sharing.md));
  - `photo_import`'s `photoImportProvider`, for the photo options ([`ai-extraction.md`](ai-extraction.md)).
- The deck screen composes `deck`'s `deckProvider`, `cardsProvider`, `DeckTile`, `CardAnswerRow`, `CardEditorScreen`, `showNameSheet` and `DeckRepository`; `study`'s `TodayCounter`, `ProgressCounter` and `StudyScreen`; `sharing`'s `sharingServiceProvider` and `onlineProvider`, for publishing; and `photo_import`'s `photoImportProvider`.
- A `DeckRow` takes what it shows of today and of its progress as widgets, which the 덱 tab builds from `TodayCounter` and `ProgressCounter`: the deck's places for what `study` draws ([`structure.md`](structure.md)).

### Tabs

- The signed-in app is three tabs, 오늘, 덱 and 기록, in a bar at the foot on the surface over a hairline: Lucide's sun, layers and column chart over each name, the selected tab in ink and bold, the others muted, each read as a selectable button ([ADR 0036](adr/0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md)). The tabs keep their state while another is shown. Back on 덱 or 기록 returns to 오늘; on 오늘 it is left to the platform.
- Before the first deck, the first-run home shows in place of the tabs, under the lockup and the account button: the mascot in a white circle, "첫 덱을 만들어 볼까요?", one line on how to start, then "사진으로 만들기" when photo import exists, "직접 만들기", which opens the name sheet, and "공개 덱 둘러보기" with sharing.

### The today tab

- The top bar holds the horizontal lockup, 30 high and read as the app's name, and at its right the account button, the account's initial in a 32 px circle ([ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)).
- With cards left today, the today card on the navy (raised in the dark theme): "오늘 할 카드", the count large with "장 · 약 m분", read as "오늘 할 카드 n장"; beside it the goal ring, done over goal, read as "하루 목표 n장 중 m장"; the streak chip, a flame and "n일 연속" in an outlined pill, while the streak is above zero; "하루 목표 n장 중 m장 했어요"; and a white "모두 학습", which opens one session over every deck ([`study.md`](study.md), [ADR 0036](adr/0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md)).
- In a backlog, the backlog card in its place: the mascot in a white circle with an amber check, "다시 시작하면 돼요", "밀린 복습 n장을 급한 것부터 해요. 새 카드는 잠시 쉬어요.", the streak chip, and "n장 학습 · 약 m분", which opens the same session over every deck; under it the catch-up, "하루 n장씩 하면 m일이면 따라잡아요" over a bar for each of the seven days, in the streak's amber, of the overdue reviews left at that pace, and "하루 n장씩 했을 때 남는 밀린 복습이에요". The pace is the average daily load ([`study.md`](study.md)). There is no daily portion: the owner kept a backlog as ADR 0025 has it ([ADR 0036](adr/0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md)).
- With nothing left, the done card on the brand tint: the mascot resting with three z's, "오늘 할 카드를 다 했어요", "다음 복습은 내일 · n장, 약 m분", or the weekday, or "앞으로 7일 동안 복습할 카드가 없어요", the streak chip and "목표 n장 달성" once the goal is reached; under it the next seven days and "계속 학습", which opens the session over every deck ([ADR 0040](adr/0040-keep-every-study-button-enabled-at-zero-cards-left.md)).
- "앞으로 7일" on the surface: a bar for each day, labelled 오늘, 내일 and the weekday, its count above it, today's in ink, or on the done card the next day with cards, and the others a quieter ink; beside the heading "내일 n장 · 이번 주 m장", or "이번 주 m장" once done. The bars are read as one line of each day and its count.
- "오늘 할 덱" lists each deck with cards left today: its tile, name, count and a play icon, read as "{name}, 오늘 n장 학습", which opens a session over that deck.
- A count that cannot be read shows why on the navy card, with "모두 학습".

### The decks tab

- The top bar holds "내 덱 n" at 26/800, "선택", which enters selection mode, and "새 덱", which opens the new-deck sheet: "새 덱 만들기" and a row each for "직접 만들기", which asks for the name, "사진으로 만들기" when photo import exists, and "공개 덱에서 가져오기" with sharing, each with a line under it. A photo import that saved opens the deck it saved into.
- A 48 px "덱 검색" keeps the decks whose name holds it, ignoring case.
- Each deck is a `DeckRow` ([`deck.md`](deck.md)), with a brand-tint "오늘 n" chip when a session over it would study n > 0 cards now, a progress bar, the mastered cards in ink and the learning ones quieter, and "n장 중 m장 익힘". A count that cannot be read shows an icon whose tooltip says why.
- Under the rows, with sharing, "공개 덱 둘러보기" with its line, on an outline, which opens the browse screen.
- A tap opens a deck's screen; a long-press enters selection mode with that deck selected. No line explains the long-press.
- In selection mode:
  - a tap, or a long-press, adds or removes a deck;
  - the app bar shows how many decks are selected, a clear action that leaves the mode, and "학습 (n)", which opens one study session over the selected decks;
  - a deck deleted while selected leaves the selection, and "학습 (n)" is disabled while the selection is empty;
  - each deck's row exposes whether it is selected to screen readers.

### The record tab

- "기록" and "학습 기록은 곧 여기에서 볼 수 있어요." until issue #90 fills it.

### The deck screen

- The top bar has a back button, "카드 검색", which opens a search field in the bar with "검색 닫기", and the deck menu, which renames or deletes the deck; deleting returns to the tabs. With sharing, the menu also offers "공개하기" or "비공개로 전환", disabled with a one-line reason while offline.
- Under it, the deck's tile, its name at 22/800, and "카드 n장", with "· 공개" when the deck is published.
- The navy card, read as "오늘 이 덱": "오늘 할 카드", the count with "장 · 약 m분", in a backlog "밀린 복습을 마칠 때까지 새 카드는 쉬어요.", "n / m 익힘", the progress bar in white on its faint white, and a white "학습하기", which opens a session over the deck whatever the count, 0 included, and while the count is pending or cannot be read ([ADR 0040](adr/0040-keep-every-study-button-enabled-at-zero-cards-left.md)).
- Each card is a `CardAnswerRow`: its question, and its answer hidden behind a bar until a tap shows it and a second hides it; a long-press, or a screen reader's "카드 편집", opens it in the editor ([`deck.md`](deck.md)). The search keeps the cards whose front or back holds it, ignoring case.
- The bottom bar holds "카드 추가". With photo import, it opens a sheet with "직접 입력" and "사진"; without, the editor. A photo import that saved into another deck replaces this screen with that deck's; one into this deck returns here.

### Interface

- Every string the screens show comes from the shared ARB set, and every tap target carries a semantic label: its text, or a tooltip for an icon button.
- The screens follow the principles and the theme of [`design.md`](design.md), with `design`'s `BottomActions` as the deck screen's bottom bar.

### Tests

- `app/test/home/home_screen_test.dart` drives the tabs, the back from another tab, the 오늘 tab's today, done and backlog cards with their counts, goal, streak and forecast, today's decks, and the 덱 tab's rows, search, new-deck sheet and selection; `app/test/home/deck_screen_test.dart` the deck screen, its hidden answers, its search and its add-card sheet. Both run over an in-memory database, with `deck`'s and `study`'s real repositories and study's clock, zone and scheduler substituted (`app/test/home/home_data.dart`, `app/test/home/deck_screens.dart`). The counts come from seeded cards and states; a deck repository that fails to list a deck's cards gives the unreadable count, and a study repository whose pace never arrives the pending one. A study button's session is the `StudyScreen` it pushes, read for its decks.
- The sharing tests drive the 덱 tab and the deck screen through `app/test/sharing/sharing_app.dart` the same way ([`sharing.md`](sharing.md)).
- `app/test/home/hero_test.dart` checks the shades the navy cards and the charts derive from the tokens: the quiet text at 4.5:1, and the flame, the goal ring and a quiet bar at 3:1, in both themes.
- `app/test/widget_test.dart` checks every tab, the new-deck sheet and the deck screen with an answer shown and the search open against the tap target and contrast guidelines in both themes.
- `app/test/architecture_test.dart` fails on an import of `home/` from anywhere but `main.dart`, on a file in `home/` that declares a provider or imports the database, and on a domain file that names a screen another domain exports ([`structure.md`](structure.md)).

## Rationale

- [ADR 0039](adr/0039-name-every-top-level-folder-by-its-responsibility-compose-across-domains-in-a-home-shell-and-keep-seams-off-screens.md) records why screens that span domains live in a shell above them, why a domain hosts no other domain's screen through a provider, and why the shell holds no reads of its own.
- [ADR 0009](adr/0009-multi-deck-session-and-random-queue-order.md) records the session over several decks, the selection mode and the today card.
- [ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md) records the v2 home and deck screens and the today card's minutes.
- [ADR 0040](adr/0040-keep-every-study-button-enabled-at-zero-cards-left.md) records why every study button stays enabled at zero cards left, and the done today card offers "계속 학습".
- [ADR 0036](adr/0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md) records the tabs, the daily goal, the forecast and a card's progress, why the goal needs no stored load, and why the backlog card has no daily portion.
- Issue #110 records the move of the two screens out of `deck` into the shell; issue #19 records the selection mode and the today card, issue #22 the v2 screens, and issue #89 the tabs and the v3 screens.

## Open questions

- None.
