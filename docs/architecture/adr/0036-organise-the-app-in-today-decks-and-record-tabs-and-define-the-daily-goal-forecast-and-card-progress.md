# ADR 0036: Organise the app in 오늘, 덱 and 기록 tabs, and define the daily goal, the seven-day forecast and a card's progress

> Status: accepted; the today card's goal line superseded by ADR-0046
> Date: 2026-10-17

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #89 records the owner's v3 home and deck screens, approved on 2026-10-16 with the artboards `Main`, `HomeDone`, `HomeBacklog`, `Decks`, `NewDeckSheet` and `Deck`. On `main` at `4c804aeb2a4383e1dffe9146b0ba2edfd56cc8a5`, the signed-in app is one home screen, `home/`'s `HomeScreen`: the today card over the deck rows, a bottom bar with "새 덱" and "사진으로 만들기", a long-press for selection with a hint, and a deck page whose cards show question and answer side by side ([ADR 0039](0039-name-every-top-level-folder-by-its-responsibility-compose-across-domains-in-a-home-shell-and-keep-seams-off-screens.md), [ADR 0040](0040-keep-every-study-button-enabled-at-zero-cards-left.md)).
- The issue defines, for the home screen:
  - today's load as [ADR 0033](0033-count-cards-left-per-study-day-from-04-00-and-continue-as-unrecorded-practice.md)'s cards left, with minutes at the user's pace;
  - the daily goal as the cards answered today against the load as it stood when the study day started, without practice;
  - the streak as consecutive study days with a recorded answer, which `study` already counts for the completion card;
  - the seven-day forecast as the cards due on each of the next seven study days, today being today's load;
  - a card as 익힘 (mastered) when its current interval is at least 21 days, 학습 중 (learning) when reviewed below that, and 새 카드 (new) when never reviewed.
- The artboards draw shades the token set lacks: a quieter white and a faint white on the navy card, a lighter navy for learning bars, and an amber flame. A colour token added to `AppColors` must also be added to `web/src/styles/globals.css`, which a web test compares with it, and this issue touches the app alone.
- Alternatives considered:
  - Keep one home screen and add the forecast and progress to it. The owner's canvas splits today's study from the deck list, which grows with the library.
  - Store the load at the start of each study day, to measure the goal against. That would need a new table synced across devices; the due-by-day-end rule of ADR 0033 already fixes the day's load, so it can be recovered from what was answered and what is left.
  - A daily backlog portion, as `HomeBacklog` draws it ("84장 중 급한 것부터 30장만"), with a catch-up chart at 30 a day. It is a new queue rule that ADR 0025 does not have, and the queue's constants are kept the same in `web/src/features/study/queue.ts`, which a test enforces. The owner decided on 2026-10-17, on the worker's question in the dispatch of issue #89, against it: a backlog stays as ADR 0025 has it, every due card earliest due first and no new card, and the home screen shows the whole backlog, with the catch-up projected at the average daily load. That decision is why the artboard's portion is not built.
- The PM settled the other open points in the same dispatch: the mascot's poses are the existing `Mascot` with drawn decorations and no new assets; the 덱 tab shows "내 덱 n" without the subscription's limit, the drawn deck search, and a "선택" button; and the goal and today's decks are as decided below.

## Decision

- **Tabs.** The signed-in app is three tabs in `home/`, 오늘, 덱 and 기록, in a bottom bar on the surface over a hairline, the selected tab in ink and the others muted. Back on 덱 or 기록 returns to 오늘; on 오늘 it leaves the app. Before the first deck the first-run home shows in place of the tabs. 기록 holds a heading and one line until its content (issue #90) arrives.
- **Today's load** is `TodayCounter`'s count, which `study` reads once for the counter and the overview through one function.
- **Daily goal.** For the study day, the goal is every card of the selection answered within the day, from the stored reviews, together with every card left in today's queue, each once; done is the goal less the cards left. A card answered "Don't know" and due again today is left, so not done. Practice records nothing and counts toward neither.
- **Streak** is `study`'s `streak`, over the stored answers since the day began and the study days in a row before it, as the completion card counts it.
- **Forecast.** Today's load, then, for each of the next six study days, the stored states that fall due within it; the days run from 04:00 to 04:00 in the device's zone, each boundary read at its own instant.
- **Progress.** `masteredInterval` is 21 days, the one statement of the constant. A card's interval is its due time less its last review; at least `masteredInterval` is mastered, below it learning, and no stored state new.
- **오늘.** The today card on the navy: "오늘 할 카드", the count with its minutes, the goal ring with done over goal, the streak and the goal's line, and "모두 학습"; then the next seven days as bars, today's in ink; then "오늘 할 덱", a row per deck with cards left today, which studies that deck. Once nothing is left: the done card with the mascot resting, "오늘 할 카드를 다 했어요", the next review with its day, cards and minutes, the streak and "목표 n장 달성" when the goal is reached; the seven days; and "계속 학습". In a backlog: the backlog card with the mascot cheering, "다시 시작하면 돼요", the whole overdue count, that new cards wait, and "n장 학습" with their minutes, which studies every deck; then the catch-up: the overdue reviews left at the start of each of the seven days when the user clears the average daily load a day, ADR 0025's `dailyLoad` rounded up and at least one, with how many days that takes. No daily portion; the queue rules are unchanged.
- **덱.** "내 덱 n" with "선택", which enters selection mode, and "새 덱", which opens the new-deck sheet: "직접 만들기", "사진으로 만들기" with photo import, and "공개 덱에서 가져오기" with sharing; a search by name; a row per deck with its name, "공개" and "오늘 n" chips, a progress bar and "m장 중 n장 익힘"; and "공개 덱 둘러보기" with sharing. A long-press still selects; no hint text. The Plus limit and badges, and the CSV option, wait for the subscription issue.
- **Deck page.** The tile, the name and "카드 n장", with "· 공개" when published; a navy card with today's count and minutes, "n / m 익힘", the progress bar and "학습하기"; each card's question on its row with the answer hidden until a tap, a second tap hiding it, and a long-press or a screen reader's action opening it to edit; the search in the top bar; one "카드 추가", which with photo import offers "직접 입력" and "사진".
- **Shades.** The navy card's quiet text and its track are the token `onHero` at 80% and 16%; the learning share of a progress bar is its ink at 45%; the forecast's other bars are ink at 55%; the flame is the `streak` token, on the navy, inside an outlined pill there. No colour token is added. `app/test/home/hero_test.dart` checks the derived pairs in both themes: the quiet text at 4.5:1, and the flame, the goal ring and a quiet bar at 3:1. A progress bar's three shares do not all reach 3:1 against each other; its counts are always in text beside it and in its label, so the bar is supplementary (the PM's condition in the dispatch of issue #89 was that the contrast tests cover the derived pairs).
- **Supersessions.** This replaces, in the app, ADR 0009's today card over the deck list and ADR 0027's v2 home and deck screens with these tabs and screens; the web's keep them until issue #91.

## Consequences

- The deck list no longer carries today's study, and today's study no longer scrolls past the library.
- A card's answer on the deck page needs a tap to read, and editing a card needs a long-press or the screen reader's action, where a tap opened it.
- The goal holds across devices without new storage, but a card added during the day joins the goal once it is answered or left.
- The navy card's shades are derived from tokens, so the web's later screens (issue #91) draw them by the same rule or add the tokens on both clients together.
- A user in a backlog sees the whole overdue count, and a catch-up at a normal day's pace, but no smaller daily target; a portion would need a queue rule on both clients first.

## Signs the decision was wrong

- Users miss the deck list on opening the app, or cannot find how to edit a card once its row hides the answer.
- The goal ring's total moves during the day in ways users report as wrong, for cards added or deleted that day.
- Users in a backlog give up on a count they cannot finish, and ask for a smaller daily portion, or find the catch-up's days too many to read as a path.
- The 21-day line marks cards mastered that users still miss, or the reverse.
