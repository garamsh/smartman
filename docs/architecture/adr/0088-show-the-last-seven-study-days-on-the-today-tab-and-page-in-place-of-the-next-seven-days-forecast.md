# ADR 0088: Show the last seven study days on the 오늘 tab and page in place of the next seven days' forecast

> Status: accepted
> Date: 2026-10-20

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #279**, the owner's decision of 2026-10-19: the 오늘 screen shows past study instead of the coming days, so users see how hard they have worked. The forward forecast goes.
- **What showed:** under the today and done cards, on the phone and the web, "앞으로 7일": the cards due on each of the next seven study days ([ADR 0036](0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md)).
- **What stays, by the PM's design:**
  - the done card's one line "다음 복습은 내일 · n장", which says when to come back;
  - in a backlog, the catch-up's bars, which are about catching up, not about future work.
- **What the 오늘 screen already reads.**
  - On the phone, every stored answer is on the device.
  - On the web, 오늘 already calls `study_record_days`, for its retention card, and `study_days_before`, for the pace. The first gives each study day's cards, each once; the second, each earlier study day's answer time, each answer capped. Today's answers, with their durations, are read for today's list.
  - So no new read and no new table is needed.
- **Alternatives considered:**
  - **A calendar week, Monday to Sunday.** On a Monday it would show one day. The last seven study days always show a week's worth.
  - **Counting answers rather than cards.** A card re-shown after "모른다" would count twice. 기록's study days count each card once a day, so the two screens agree.
  - **Keeping the forecast beside the past.** The owner asked for it to go; two seven-day charts would make the card long and make one of them easy to misread.

## Decision

- **"지난 7일"** takes the forecast's place under the today and done cards: the last seven study days ending today, each from 04:00 to 04:00 in the device's or the browser's zone.
  - Each day is a bar of the cards answered in it, each once. Today is last and in ink, the others in a quieter ink.
  - A day without study is an empty slot, the bar's least height over "0".
  - Above the bars: "이번 주 n장 · m분", the seven days' cards and their minutes, then the streak after a flame. The minutes are the answers' time, each answer up to 30 s (`answerCapMs`), rounded up.
  - A tap anywhere on the card opens 기록: on the phone its tab, on the web `/record`.
  - The card is read as one sentence, "지난 7일 동안 n장을 m분 공부했어요", then each day as "월요일 32장", with "기록 열기" as its hint.
- **The figures.**
  - On the phone, `overview.dart`'s `lastWeek` counts them from the answers stored since the first of the seven days.
  - On the web, `overview.ts`'s `lastWeek` joins:
    - `study_record_days`' cards for each day;
    - `study_days_before`' time for each earlier day;
    - today's answers, each capped.
  - `chartDays` is 7 on both, and the web's test compares it with the phone's.
- **The forecast goes:**
  - `forecast` and its strings, and the web's `forecast` and its chart.
  - The next review is now `nextReviewOf`: the first study day after today, within seven, with a card due.
  - The labels the catch-up and the next review share are renamed `dayToday`, `dayTomorrow` and `dayCount`.
- **Supersessions:** this supersedes ADR 0036's forecast on the 오늘 tab and the web's 오늘 page. Its next review line and the backlog's catch-up stand.

## Consequences

- The streak shows twice on the 오늘 tab: on the today or done card's chip, and beside the week's line.
- A user who has not studied for a week sees seven empty slots and "이번 주 0장 · 0분".
- The 오늘 tab and page read no new data: the phone reads a week's answers where it read today's, and the web keeps every study day `study_record_days` gives.

## Signs the decision was wrong

- Users miss knowing tomorrow's load, beyond the done card's next review line.
- The last seven days and 기록's study days disagree for the same days.
