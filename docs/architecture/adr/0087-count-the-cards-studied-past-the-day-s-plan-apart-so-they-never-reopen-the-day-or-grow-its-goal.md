# ADR 0087: Count the cards studied past the day's plan apart, so they never reopen the day or grow its goal

> Status: accepted
> Date: 2026-10-20

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #278**, reported by the owner on 2026-10-19. After the day's cards are done, studying on with "학습하기" ([ADR 0049](0049-study-in-one-flow-that-goes-on-past-today-s-cards-as-recorded-study-with-the-current-card-showing-its-front-alone.md)) grows the 오늘 tab's amount and shows the day as not done.
- **Why:**
  - ADR 0049 counts an answer past today's cards in the daily goal like any other.
  - The goal is the cards done plus the cards left ([ADR 0036](0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md)).
  - A card past the plan answered "모른다" stays left in today's list ([ADR 0061](0061-keep-a-card-failed-today-in-today-s-list-until-it-is-passed-through-a-pure-engine-function-over-the-day-s-reviews.md)), and its state makes it due again within the day.
  - So every extra card joins the goal, a "모른다" among them reopens the day, and the done card goes away.
- **The rule the PM set:**
  - the day's goal is its planned cards alone: the reviews due and the day's new cards;
  - cards past the plan are written, synced, scheduled and counted in 기록, the streak and the study time as any answer, but shown on the 오늘 tab only as "오늘 n장 더 했어요";
  - a "모른다" on one comes back within the session, as now, without reopening the day;
  - the top bar counts them apart, "추가 k장", so the day's bar does not shrink;
  - the app and the web agree.
- **What tells a planned new card from an extra one.** Nothing is stored apart for them: both are cards first answered in the day. The day's new-card figure ([ADR 0085](0085-fill-each-day-s-new-cards-from-the-daily-study-minutes-the-user-sets-stored-per-user-on-the-server-and-synced.md)) is known when the day is read, and so is the order of the first answers.
- **Alternatives considered:**
  - **Storing a flag on each answer past the plan.** It needs a column on `reviews`, a migration, a sync change and the web's writes, for a fact the day's figure and the answers' order already give.
  - **Changing today's list in the engine.** The engine places cards by their due time and the day's reviews and knows nothing of the day's figure. Keeping the cards past the plan out of the list given to it keeps the engine as it is.

## Decision

- **The cards past the day's plan** are the cards first answered in the study day, in the order answered, after the first n, n being the day's new-card figure. On the phone it is `StudyDay.extra`; on the web, the `extra` of `studyDay`.
  - Answers at the same instant keep the order the day is given them in, which is the stored order.
  - A change of the daily minutes during the day moves the line, as it moves the day's new cards.
- **The day plan leaves them out** (`dayPlanOf` on both clients):
  - none is selected, left or done, whatever its latest answer and its due time;
  - the plan holds them apart as `extra`;
  - so the daily goal, the status line, each deck's count and the session's day count are the planned cards alone.
- **They are recorded as any answer:** written, synced and scheduled, and counted in 기록, the streak, the completion card's line and the pace.
- **The 오늘 tab** shows "오늘 n장 더 했어요", n being the cards past the plan across every deck, as a pill after a plus on the done card and on the today card. The goal ring never counts them. The web's 오늘 card shows the same.
- **The study session** counts the day's cards as before, but without the cards past the plan: those answered past it before the session opened, and those 학습하기 takes. Beside the day's count, "추가 k장" (the web's 오늘 card and top bar the same) counts those answered, read as "오늘 계획 밖으로 k장 더 공부함". A "모른다" on one re-shows it within the session.
- **Supersessions:** this supersedes ADR 0049's counting of answers past today's cards in the daily goal. Their counting in the streak and 기록 stands.

## Consequences

- A finished day stays finished, whatever is studied after it, until the day ends.
- A card past the plan answered "모른다" and left there is a review on a later day by its state, not a card left today.
- Raising the daily minutes after studying on turns the first of the extra cards into the day's own, and lowering them does the reverse.

## Signs the decision was wrong

- Users read "오늘 n장 더 했어요" as the day's amount, or miss the extra cards in the goal ring.
- A card past the plan answered "모른다" is wanted back the same day, outside the session.
