# Home

The app's `home/` shell: the signed-in screens that show more than one domain or lead from one domain into another, and how they compose the domains.

## Current decisions

### Surface and location

- The shell lives in `app/lib/home/`; its surface is `app/lib/home/home.dart`, which exports `HomeScreen`, with internals under `app/lib/home/src/` ([ADR 0039](adr/0039-name-every-top-level-folder-by-its-responsibility-compose-across-domains-in-a-home-shell-and-keep-seams-off-screens.md), [`structure.md`](structure.md)):
  - `home_screen.dart` — `HomeScreen`: the three tabs and their bar, or the first-run home before the first deck;
  - `first_run.dart` — `FirstRun`, the layout of how to start that the first-run home and the cardless 오늘 tab share;
  - `today_tab.dart` — the 오늘 tab: the today, done and backlog cards, the last seven study days and today's decks;
  - `decks_tab.dart` — the 덱 tab: the deck rows, their progress and today chips, the search, and the buttons under the rows;
  - `record_tab.dart` — the 기록 tab: its title over `study`'s record;
  - `deck_screen.dart` — `DeckScreen`, a deck's page;
  - `new_deck_sheet.dart` and `option_sheet.dart` — the new-deck sheet and the sheet of options it and "카드 추가" open;
  - `progress_bar.dart` and `hero.dart` — the progress bar, and the navy card's shades and large count.
- The composition site passes `HomeScreen` to `account`'s `AccountGate` as the screen it opens while an account is signed in ([`account.md`](account.md)). Nothing else imports `home/`.

### Composition

- `home/` sits above every domain: it imports the domains' surfaces and the foundations, and builds each screen from the domains' exported widgets, handing values and callbacks between them, as a web route does.
- It holds no reads and no rules of its own: it declares no provider and imports no database. What a screen shows, it reads through a domain's providers and widgets.
- The tabs compose:
  - `deck`'s `decksProvider`, `cardCountsProvider`, `DeckRow`, `DeckTile`, `showNameSheet` and `DeckRepository`, for the decks, their rows and a new deck ([`deck.md`](deck.md));
  - `study`'s `TodayOverviewReader`, for the 오늘 tab's count, goal, streak, next review and last seven study days; `TodayCounter`, for each deck's count; `ProgressCounter`, for each deck's progress; `StatsView`, the 기록 tab's content, given the tab's title; `openStudy`, through which every study button opens a `StudyScreen`; and `DailyMinutesButton`, `FirstDailyMinutes` and `DailyMinutesRow`, the daily study minutes' control, first-run step and account row ([`study.md`](study.md), [ADR 0086](adr/0086-show-and-change-the-daily-study-minutes-on-the-today-card-the-completion-card-a-one-time-first-run-step-the-account-screen-and-the-web-s-today-page.md));
  - `account`'s `AccountAvatar` on the account button, and `AccountScreen`, given `sync`'s `SyncStatusView` as the status it shows and `study`'s `DailyMinutesRow` as its study setting ([`account.md`](account.md), [`sync.md`](sync.md));
  - `sharing`'s `sharingServiceProvider`, for the browse screen ([`sharing.md`](sharing.md));
  - `photo_import`'s `photoImportProvider`, for the photo options ([`ai-extraction.md`](ai-extraction.md)).
- The deck screen composes `deck`'s `deckProvider`, `cardsProvider`, `DeckTile`, `CardBackRow`, `CardEditorScreen`, `showNameSheet` and `DeckRepository`; `study`'s `TodayCounter`, `ProgressCounter` and `openStudy`; `sharing`'s `sharingServiceProvider` and `onlineProvider`, for publishing; and `photo_import`'s `photoImportProvider`.
- A `DeckRow` takes what it shows of today and of its progress as widgets, which the 덱 tab builds from `TodayCounter` and `ProgressCounter`: the deck's places for what `study` draws ([`structure.md`](structure.md)).

### Tabs

- The signed-in app is three tabs, 오늘, 덱 and 기록, in a bar at the foot on the surface over a hairline: Lucide's sun, layers and column chart over each name, the selected tab in ink and bold, the others muted, each read as a selectable button ([ADR 0036](adr/0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md)). The tabs keep their state while another is shown. Back on 덱 or 기록 returns to 오늘; on 오늘 it is left to the platform.
- Before the first deck, the first-run home shows in place of the tabs, under the lockup and the account button: the mascot in a white circle, "첫 덱을 만들어 볼까요?", one line on how to start, then "덱 만들기", the one primary, which opens the new-deck sheet, and the text "공개 덱 둘러보기" with sharing ([ADR 0067](adr/0067-start-a-deck-or-a-card-from-one-sheet-that-holds-the-photo-source-and-name-public-decks-once.md)).

### The today tab

- While no deck holds a card, the tab shows how to start in place of everything below, in the first-run home's layout: the mascot, "첫 카드를 만들어 볼까요?" and "덱에 카드를 추가해 시작해요". With one deck, a primary "카드 추가" opens the deck's screen with its add sheet up (its card editor without photo import), beside a quiet "덱 열기"; with several, a primary "덱에서 카드 추가하기" shows the 덱 tab ([ADR 0066](adr/0066-open-a-deck-made-by-hand-and-lead-an-empty-deck-and-a-cardless-today-tab-to-adding-cards.md)).

- The top bar holds the horizontal lockup, 30 high and read as the app's name, and at its right the account button, the account's initial in a 32 px circle ([ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)).
- With cards left today, the today card on the navy (raised in the dark theme): "오늘 할 카드", the count large with "장 · 약 m분", read as "오늘 할 카드 n장"; beside it the goal ring, done over goal, read as "하루 목표 n장 중 m장"; the streak chip, a flame and "n일 연속" in an outlined pill, while the streak is above zero; "오늘 n장 더 했어요" after a plus in the same outlined pill while cards were studied past the day's plan ([ADR 0087](adr/0087-count-the-cards-studied-past-the-day-s-plan-apart-so-they-never-reopen-the-day-or-grow-its-goal.md)); a line on where the user stands today, the first that holds of "n일째 이어 가는 중이에요" (nothing answered yet, a streak of two days or more), "오늘의 첫 카드를 기다리고 있어요" (nothing answered yet), "거의 다 왔어요" (three cards or fewer left), "절반을 넘었어요" (half of the goal or more done) and "좋은 출발이에요" (some done), from `study`'s `TodayStatus`, breaking only between words; it states where the user stands and never what to tap ([ADR 0046](adr/0046-state-where-the-user-stands-today-on-the-today-card-in-place-of-the-goal-s-numbers.md)); and a white "모두 학습", which opens one session over every deck ([`study.md`](study.md), [ADR 0036](adr/0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md)). Under the count and the ring, a line of its own holds the daily study minutes' control, "하루 n분" and a pencil, outlined in white, read as "하루 공부 시간 n분, 바꾸기", which opens the sheet that changes them ([ADR 0086](adr/0086-show-and-change-the-daily-study-minutes-on-the-today-card-the-completion-card-a-one-time-first-run-step-the-account-screen-and-the-web-s-today-page.md)).
- In a backlog, the backlog card in its place: the mascot in a white circle with an amber check, "다시 시작하면 돼요", "밀린 복습 n장을 급한 것부터 해요. 새 카드는 잠시 쉬어요.", the daily study minutes' control beside the streak chip, and "n장 학습 · 약 m분", which opens the same session over every deck; under it the catch-up, "하루 n장씩 하면 m일이면 따라잡아요" over a bar for each of the seven days, in the streak's amber, of the overdue reviews left at that pace, and "하루 n장씩 했을 때 남는 밀린 복습이에요". The pace is the average daily load ([`study.md`](study.md)). There is no daily portion: the owner kept a backlog as ADR 0025 has it ([ADR 0036](adr/0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md)).
- With nothing left in the day plan ([`study.md`](study.md)), the done card on the brand tint: the mascot resting with three z's, "오늘 할 카드를 다 했어요", "다음 복습은 내일 · n장, 약 m분", or the weekday, or "앞으로 7일 동안 복습할 카드가 없어요", the daily study minutes' control on the surface, the streak chip, "목표 n장 달성" once the goal is reached, and "오늘 n장 더 했어요" after a plus while cards were studied past the day's plan, which the goal never counts; under it the last seven study days and "학습하기", which opens the session over every deck; with none left in today's list, nothing still on "Don't know" included, it opens on the new cards past today's ([ADR 0040](adr/0040-keep-every-study-button-enabled-at-zero-cards-left.md), [ADR 0049](adr/0049-study-in-one-flow-that-goes-on-past-today-s-cards-as-recorded-study-with-the-current-card-showing-its-front-alone.md)).
- The first-run step: once the tab shows a day with cards, while it is the selected tab and no screen is open over it, the daily study minutes' sheet opens once per device as "하루 몇 분 공부할까요?", with "건너뛰기", unless minutes are already stored from any device ([ADR 0086](adr/0086-show-and-change-the-daily-study-minutes-on-the-today-card-the-completion-card-a-one-time-first-run-step-the-account-screen-and-the-web-s-today-page.md)). The step reads whether the tab is visible, since the 오늘 tab stays built behind the selected one.
- Every study button opens its session through `study`'s `openStudy`, which first shows that step where it has not shown, so a first session started elsewhere takes the minutes chosen.
- "지난 7일" on the surface, under the today and done cards: a bar for each of the last seven study days, labelled with the weekday and, last, 오늘, its cards above it, each card once, today's in ink and the others a quieter ink, a day without study the bar's least height; above the bars "이번 주 n장 · m분", the minutes each answer's time up to 30 s rounded up, and the streak after a flame. A tap anywhere on it shows the 기록 tab. It is read as "지난 7일 동안 n장을 m분 공부했어요" and each day as "월요일 32장", with "기록 열기" as its hint ([ADR 0088](adr/0088-show-the-last-seven-study-days-on-the-today-tab-and-page-in-place-of-the-next-seven-days-forecast.md)). There is no forward forecast: the done card's next review line is the one look ahead.
- "오늘 할 덱" lists each deck with cards left today: its tile, name, count and a play icon, read as "{name}, 오늘 n장 학습", which opens a session over that deck.
- A count that cannot be read shows why on the navy card, with "모두 학습".

### The decks tab

- The top bar holds "내 덱 n" at 26/800 alone ([ADR 0050](adr/0050-make-a-deck-from-a-button-under-the-deck-list-and-remove-the-deck-selection-mode.md)).
- A 48 px "덱 검색" keeps the decks whose name holds it, ignoring case.
- Each deck is a `DeckRow` ([`deck.md`](deck.md)), with a brand-tint "오늘 n" chip when a session over it would study n > 0 cards now, a progress bar, the mastered cards in ink and the learning ones quieter, and "n장 중 m장 익힘". A count that cannot be read shows an icon whose tooltip says why.
- Under the rows, two rows on an outline, each with an icon, its title, a line and a chevron, read as one: "새 덱 만들기" with "새 덱을 시작할 방법을 골라요", then, with sharing, "공개 덱 둘러보기" with its line, which opens the browse screen ([ADR 0050](adr/0050-make-a-deck-from-a-button-under-the-deck-list-and-remove-the-deck-selection-mode.md)).
- "새 덱 만들기" opens the new-deck sheet: "새 덱 만들기" and a row each for "직접 만들기", which asks for the name in the sheet "새 덱" and opens the deck it made ([ADR 0066](adr/0066-open-a-deck-made-by-hand-and-lead-an-empty-deck-and-a-cardless-today-tab-to-adding-cards.md)), and, when photo import exists, "사진 찍기" and "앨범에서 고르기", which start photo import from that source at once, each with a line under it. It offers no public decks: the row under the deck rows is their one way in ([ADR 0067](adr/0067-start-a-deck-or-a-card-from-one-sheet-that-holds-the-photo-source-and-name-public-decks-once.md)). A photo import that saved opens the deck it saved into.
- A tap opens a deck's screen, and a long-press does the same. There is no selection mode: 오늘's "모두 학습" studies every deck with cards today.

### The record tab

- The tab is `study`'s `StatsView` over every deck, given "기록" at 26/800, read as a heading, as the title it shows beside its period selector ([`study.md`](study.md)). There is no Plus badge: gating waits for the subscription issue (issue #90).
- The tab is built the first time it is shown, not when the tabs open, since its read folds every review through the engine; after that it keeps its state as the other tabs do.

### The deck screen

- The top bar has a back button, "카드 검색", which opens a search field in the bar with "검색 닫기", and the deck menu, which renames or deletes the deck; deleting returns to the tabs. With sharing, the menu also offers "공개하기" or "비공개로 전환", disabled with a one-line reason while offline.
- Under it, the deck's tile, its name at 22/800, and "카드 n장", with "· 공개" when the deck is published.
- The navy card, read as "오늘 이 덱": "오늘 할 카드", the count with "장 · 약 m분", in a backlog "밀린 복습을 마칠 때까지 새 카드는 쉬어요.", "n / m 익힘", the progress bar in white on its faint white, and a white "학습하기", which opens a session over the deck whatever the count, 0 included, and while the count is pending or cannot be read ([ADR 0040](adr/0040-keep-every-study-button-enabled-at-zero-cards-left.md)). While the deck holds no card, the card shows no "학습하기" ([ADR 0066](adr/0066-open-a-deck-made-by-hand-and-lead-an-empty-deck-and-a-cardless-today-tab-to-adding-cards.md)).
- Above the cards, while the deck has any, a row pinned under the top bar as the list scrolls (issue #142): "카드 n", the number of cards the list shows, read as a heading; and at its right "뜻 보기" and a switch, read together as "뜻 보기" with the switch's state. The label never changes; the switch shows the state.
- Each card is a `CardBackRow`: its front, and its back hidden behind a bar or shown ([`deck.md`](deck.md)). The deck screen holds what each row shows:
  - the switch is off each time the screen opens, so every answer is hidden; it is not remembered;
  - changing the switch sets every card to its state, a card the tap had set apart included;
  - a tap shows or hides that card alone, until the switch next changes;
  - the search's results follow the same state.
- A long-press on a card, or a screen reader's "카드 편집", opens it in the editor. The search keeps the cards whose front or back holds it, ignoring case.
- The bottom bar holds "카드 추가", outlined, or in the primary fill while the deck holds no card, when it is the screen's one primary. With photo import, it opens the sheet "카드 추가" with the new-deck sheet's names: "직접 만들기", which opens the editor, "사진 찍기" and "앨범에서 고르기" ([ADR 0067](adr/0067-start-a-deck-or-a-card-from-one-sheet-that-holds-the-photo-source-and-name-public-decks-once.md)); without, the editor. A photo import that saved into another deck replaces this screen with that deck's; one into this deck returns here.

### Interface

- Every string the screens show comes from the shared ARB set, and every tap target carries a semantic label: its text, or a tooltip for an icon button.
- The screens follow the principles and the theme of [`design.md`](design.md), with `design`'s `BottomActions` as the deck screen's bottom bar.

### Tests

- `app/test/home/home_screen_test.dart` drives the tabs, the cards studied past the day's plan leaving the done card and its goal as planned and shown apart, against a day within its plan, the back from another tab, the 기록 tab built only once shown and showing the record over every deck, the 오늘 tab's today, done and backlog cards with their counts, goal, status line, streak and forecast, today's decks, and the 덱 tab's title-only top bar, rows, search, a long-press opening a deck, and "새 덱 만들기" under the rows opening the new-deck sheet, its name sheet "새 덱", whose "직접 만들기" opens the deck it made, and with photo import its "사진 찍기" and "앨범에서 고르기" each starting photo import from that source, and the cardless 오늘 tab: with one deck, "카드 추가" as its primary opening the deck's editor and a quiet "덱 열기", with several, its primary showing the 덱 tab, and with a card, the day, and the daily study minutes: the control's label and semantics in English and Korean, the sheet it opens, the preview following a choice and the custom steps, saving updating today's count, and the first-run step shown once with a card and skipped; `app/test/home/deck_screen_test.dart` the deck screen, a first session asking for the minutes before it opens, an empty deck's primary "카드 추가" and no "학습하기", its hidden answers, a cloze card's row with its blanks empty and a tap filling them, the "뜻 보기" switch with its default, its reset of a tapped card, its semantics and its pinned row, its search, which follows the switch, and its add-card sheet, which names its rows as the new-deck sheet does and starts photo import from the source chosen, at a phone's size. Both run over an in-memory database, with `deck`'s and `study`'s real repositories and study's clock, zone and scheduler substituted, the scheduler folding every card into no state and recalling every stored state at 0.9 (`app/test/home/home_data.dart`, `app/test/home/deck_screens.dart`). The counts come from seeded cards and states; a deck repository that fails to list a deck's cards gives the unreadable count, and a study repository whose pace never arrives the pending one. A study button's session is the `StudyScreen` it pushes, read for its decks.
- The sharing tests drive the 덱 tab and the deck screen through `app/test/sharing/sharing_app.dart` the same way ([`sharing.md`](sharing.md)).
- `app/test/home/hero_test.dart` checks the shades the navy cards and the charts derive from the tokens: the quiet text at 4.5:1, and the flame, the goal ring and a quiet bar at 3:1, in both themes.
- `app/test/widget_test.dart` checks every tab, the new-deck sheet and the deck screen with every answer shown by the switch, with one shown by a tap and with the search open against the tap target and contrast guidelines in both themes.
- `app/test/architecture_test.dart` fails on an import of `home/` from anywhere but `main.dart`, on a file in `home/` that declares a provider or imports the database, and on a domain file that names a screen another domain exports ([`structure.md`](structure.md)).

## Rationale

- [ADR 0039](adr/0039-name-every-top-level-folder-by-its-responsibility-compose-across-domains-in-a-home-shell-and-keep-seams-off-screens.md) records why screens that span domains live in a shell above them, why a domain hosts no other domain's screen through a provider, and why the shell holds no reads of its own.
- [ADR 0009](adr/0009-multi-deck-session-and-random-queue-order.md) records the session over several decks and the today card; [ADR 0050](adr/0050-make-a-deck-from-a-button-under-the-deck-list-and-remove-the-deck-selection-mode.md) why the 덱 tab makes a deck from a button under its rows and has no selection mode.
- [ADR 0046](adr/0046-state-where-the-user-stands-today-on-the-today-card-in-place-of-the-goal-s-numbers.md) records the today card's status line in place of the goal's numbers, its wording and rule; issue #139 records the owner's direction.
- [ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md) records the v2 home and deck screens and the today card's minutes.
- [ADR 0040](adr/0040-keep-every-study-button-enabled-at-zero-cards-left.md) records why every study button stays enabled at zero cards left, and the done today card offers a study button, "학습하기" since [ADR 0049](adr/0049-study-in-one-flow-that-goes-on-past-today-s-cards-as-recorded-study-with-the-current-card-showing-its-front-alone.md).
- [ADR 0066](adr/0066-open-a-deck-made-by-hand-and-lead-an-empty-deck-and-a-cardless-today-tab-to-adding-cards.md) records why a deck made by hand opens, why an empty deck offers adding a card in place of "학습하기", and why a cardless 오늘 tab shows how to start; issue #205 and the PM's answer record the direction.
- [ADR 0067](adr/0067-start-a-deck-or-a-card-from-one-sheet-that-holds-the-photo-source-and-name-public-decks-once.md) records why one sheet holds the photo source, why the new-deck sheet offers no public decks, and the names of the browse screen and the name sheet; issues #206, #207 and #208 and the PM's answer record the direction.
- [ADR 0088](adr/0088-show-the-last-seven-study-days-on-the-today-tab-and-page-in-place-of-the-next-seven-days-forecast.md) records why the 오늘 tab shows the last seven study days in place of the next seven, what each bar counts, and what of the look ahead stays; issue #279 records the owner's decision.
- [ADR 0036](adr/0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md) records the tabs, the daily goal, the forecast and a card's progress, why the goal needs no stored load, and why the backlog card has no daily portion.
- [ADR 0087](adr/0087-count-the-cards-studied-past-the-day-s-plan-apart-so-they-never-reopen-the-day-or-grow-its-goal.md) records why the cards studied past the day's plan are counted apart and never reopen the day, how they are told from the day's own, and why nothing is stored for them; issue #278 records the owner's report.
- [ADR 0086](adr/0086-show-and-change-the-daily-study-minutes-on-the-today-card-the-completion-card-a-one-time-first-run-step-the-account-screen-and-the-web-s-today-page.md) records where the daily study minutes are shown and changed, why the control takes a line of its own, and why the first-run step asks before a session opens and waits for the 오늘 tab; issue #271 records the owner's direction.
- Issue #110 records the move of the two screens out of `deck` into the shell; issue #19 records the selection mode and the today card, issue #22 the v2 screens, issue #89 the tabs and the v3 screens, issue #90 the 기록 tab, and issue #142 the owner's "뜻 보기" switch with the details the PM settled.

## Open questions

- None.
