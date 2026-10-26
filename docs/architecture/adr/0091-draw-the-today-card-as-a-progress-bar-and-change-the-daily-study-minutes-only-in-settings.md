# ADR 0091: Draw the today card as a progress bar, and change the daily study minutes only in settings

> Status: accepted; its bar white on the navy's faint track superseded by ADR-0098
> Date: 2026-10-20

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #305**, the owner's decisions of 2026-10-20 from the design canvas's row "최종": 오늘 학습 전, 오늘 진행 중, 설정, and 설정 › 하루 공부 시간.
- **The today card** ([ADR 0036](0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md), [ADR 0046](0046-state-where-the-user-stands-today-on-the-today-card-in-place-of-the-goal-s-numbers.md)) showed the cards left with their minutes, and beside them a goal ring holding the same day as done over goal. ADR 0046 kept the goal's numbers in the ring alone.
- **The daily study minutes** were shown and changed in five places ([ADR 0086](0086-show-and-change-the-daily-study-minutes-on-the-today-card-the-completion-card-a-one-time-first-run-step-the-account-screen-and-the-web-s-today-page.md)):
  - a control on the today, backlog and done cards;
  - a line on the completion card;
  - the account screen's row;
  - the first-run step;
  - the web's 오늘 page.
  - The app's control and row opened the picker as a sheet, and the web's control opened it as a dialog ([ADR 0090](0090-pick-the-daily-study-minutes-as-one-large-number-between-minus-and-plus-typed-in-place-with-two-tiles-of-what-they-mean.md)).
- **The owner's choice:**
  - the today card states the day once, as done over the day's cards, with a bar;
  - the minutes leave the 오늘 cards and the completion card, and change in settings alone.
- **The PM's answers on the issue:**
  - the streak chip keeps "n일 연속";
  - the study button keeps "모두 학습" throughout;
  - the "오늘 n장 더 했어요" pill stays, so [ADR 0087](0087-count-the-cards-studied-past-the-day-s-plan-apart-so-they-never-reopen-the-day-or-grow-its-goal.md) stands.
- **Alternatives considered:**
  - **Keep the ring beside the bar.** That would show the same two numbers twice, the clutter the owner removed.
  - **Count the cards left, as before, with the bar of those done.** A bar of done over the day reads with a count of the same figures, and the minutes then say what is left.
  - **The app's picker as a sheet over the account screen.** The owner's "설정 › 하루 공부 시간" is a screen of its own with a back button. The first-run step stays a sheet, since it asks over the 오늘 tab and can be skipped.

## Decision

- **The today card**, on both clients:
  - **The top row:** "오늘 할 카드", with the streak chip at its right while the streak is above zero.
  - **The count:**
    - the cards done large, then "/ n장", the day's cards;
    - at its right, "약 m분" for the cards left, or "약 m분 남음" once a card is done today;
    - the large count is hidden from screen readers, since the bar reads the same figures.
  - **The bar:**
    - a bar of done over the day's cards, white on the navy's faint track;
    - a `progressbar` read as "n장 중 d장".
  - **Under the bar:**
    - ADR 0046's line on where the user stands;
    - ADR 0087's "오늘 n장 더 했어요" while cards were studied past the day's plan.
  - **The button:** "모두 학습".
  - **Removed:** the goal ring, and the daily study minutes' control. The card shows no split into reviews and new cards.
- **The backlog and done cards:** no daily study minutes' control; otherwise as they were.
- **The completion card:** no "내일도 하루 n분 · 바꾸기".
- **Settings is the one place the minutes change, after the first-run step:**
  - **App:** the account screen's "공부" section holds the row "하루 공부 시간" with the minutes and a chevron, and no icon. It opens ADR 0090's picker as a screen:
    - "하루 공부 시간" in its top bar, with a back button;
    - the sentence, the number and the tiles, scrolling above the keypad;
    - "저장" pinned at its foot, which returns to the account screen with the minutes saved;
    - back saves nothing.
  - **Web:** the account page gets a "공부" section above "화면", with the same row, read as "하루 공부 시간 n분". It opens ADR 0090's dialog. The page reads the plan the dialog's tiles need on the server, as the 오늘 page read it.
  - **First run:** the first-run step is unchanged. It is a sheet over the 오늘 tab, with "건너뛰기".

## Consequences

- The today card states the day once, and it is shorter by the ring's height and the control's line.
- A user changes the minutes in one place. The 오늘 cards no longer show them.
- This supersedes:
  - ADR 0036's goal ring on the today card;
  - ADR 0046's goal numbers in the ring;
  - ADR 0086's control on the today, backlog and done cards, its completion card's line, and its control and dialog on the web's 오늘 page;
  - the sheet that ADR 0086 and ADR 0090 opened from the account screen's row, which is now a screen.

## Signs the decision was wrong

- Users ask where to change their daily minutes, having looked on 오늘.
- Users read the large count as the cards left, rather than those done.
