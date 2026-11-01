# ADR 0038: Lay the web out as a responsive shell with a side menu from 1024 px and a tab bar below it

> Status: accepted; creation restriction partially superseded by ADR 0122; the row click superseded by ADR 0143
> Date: 2026-10-17

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #91 records the owner's approval of the v3 canvas on 2026-10-16 and the request to restructure the whole web as a responsive web app. The artboards `WebToday`, `WebDeck`, `WebStudy` and their `Mobile` versions draw a left menu on wide screens, with the logo, 오늘, 덱, 기록 and 계정과 설정 at its foot; at phone width, a top bar with the logo and the account, and a bottom tab bar of 오늘, 덱 and 기록. The phone's 오늘 and 덱 tabs and its deck screen ([ADR 0036](0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md)) give the content.
- On `main` at `080478475571535b860451b776fb684b2594c0f2` the web has one home page: the lockup, the avatar, the today card and every deck in a centred 560 px column ([ADR 0027](0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)). The deck page has a back link, count pills and the cards as one list with their answers shown.
- The PM split #91 on 2026-10-17. Part A, this decision, covers the shell, 오늘, 덱, the deck page and study at phone width. Part B, another PR, fills 기록. The decisions carried into the web are already made: buttons enabled at zero cards (#120, [ADR 0040](0040-keep-every-study-button-enabled-at-zero-cards-left.md)), the today card's status line (#139, [ADR 0046](0046-state-where-the-user-stands-today-on-the-today-card-in-place-of-the-goal-s-numbers.md)), the deck page's 뜻 보기 switch (#142), and the study screen's two cards and session guide (#143, #145, [ADR 0042](0042-show-only-the-previous-and-the-current-study-card-at-one-size-re-decide-the-previous-card-by-a-swipe-and-open-it-on-a-tap.md), [ADR 0044](0044-show-a-guide-with-the-session-s-size-in-the-previous-card-s-place-at-every-session-s-start.md)).
- The PM answered the worker's questions in the dispatch of #91 Part A:
  - Until Part B lands, /record is a page in the shell with its heading alone, so the menus' link is not a 404.
  - The deck page drops the artboard's 카드 추가, since #91 rules creation out on the web. It also drops the 덱 메뉴, since the web's deck page offers no deck action to keep.
  - 기록's "Plus" badge waits.
  - 덱 is the phone's list of rows with a search, without creation or a selection mode. 오늘 shows only today's decks.
- Where the menu changes: the artboards place the menu (220 to 260 px) and the content (from 560 px) side by side in a wrapping row, so the content would drop under the menu below about 780 px. One breakpoint of the theme decides instead. At `lg` (1024 px) the side menu leaves at least 784 px of content, and 768 px gets the phone's layout with the full width for content. `md` (768 px) would leave a 528 px content column at that width, narrower than the artboards' 560.

## Decision

- **Shell.** The signed-in pages, 오늘 (`/`), 덱 (`/decks`), a deck (`/decks/[id]`), 기록 (`/record`) and 계정과 설정 (`/account`), share one layout in the `(shell)` route group. Sign-in, study and the legal pages stand outside it, as the artboards draw study without the menu.
- **Wide.** From 1024 px, a 240 px side menu on the surface, pinned as the page scrolls. It holds the lockup, 오늘, 덱 and 기록 (the current one on the brand tint), and at its foot the account's initial and "계정과 설정". The content sits in a column up to 1040 px wide.
- **Narrow.** Below 1024 px, a top bar with the lockup and the account's initial, and a 64 px tab bar at the foot with 오늘, 덱 and 기록, the current one in ink. The content stacks.
- **Landmarks.** Both menus are the navigation "주 메뉴", one shown at a time, each marking the current page. The page's content is its one `main`, which a skip link, "본문으로 건너뛰기", reaches as the first keyboard stop.
- **Pages.**
  - 오늘 shows the today card (count and minutes, the goal ring, the streak, ADR 0046's line, 모두 학습 with Enter), the next seven days, and today's decks. The 기억률 preview links to /record once Part B gives it a figure, and is not drawn until then.
  - 덱 shows "내 덱 n", a search, and a row per deck with its progress and today's chip.
  - The deck page shows a breadcrumb, the header, and the navy card with its progress and 학습하기 (Enter). Under it come the search, the 뜻 보기 row and a grid of cards whose answers are hidden until clicked.
  - 기록 is its heading alone until Part B.
- **Definitions.** The daily goal, the forecast, a card's progress and today's status are the web's copies of `app/lib/study/src/overview.dart` in `web/src/features/study/overview.ts`. They are tested on the phone's cases, with their constants checked against that file.
- **Keyboard.** A page's one study button opens on Enter from anywhere but a control. The study screen keeps its keys.
- **Supersessions.** This replaces ADR 0027's v2 home page and deck page on the web.

## Consequences

- Every signed-in page is reached from the menus. The study page's 끝내기 and its completion card's 그만하기 still open `/`.
- 오늘 and 덱 each read the deck list and today's study day, so moving between them reads both again, as each page reads only what it shows (ADR 0030).
- Below 1024 px a tablet gets the phone's layout, with the tab bar at its foot.
- /record exists before its content, and Part B replaces only its page.

## Signs the decision was wrong

- At 768 to 1023 px the stacked layout leaves wide pages emptier than a side menu would; users of tablets ask for the menu.
- Users miss the deck list on 오늘, or press Enter expecting it to do something else.
- The menus' current page shows late, once the URL is read, often enough to be noticed.
