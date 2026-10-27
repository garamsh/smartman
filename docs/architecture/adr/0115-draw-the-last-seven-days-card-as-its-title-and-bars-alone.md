# ADR 0115: Draw the last seven days card as its title and bars alone

> Status: accepted
> Date: 2026-10-27

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #443**, the owner's decision of 2026-10-27: the "지난 7일" card needs neither the week's cards nor the streak in words.
- **What showed.** [ADR 0088](0088-show-the-last-seven-study-days-on-the-today-tab-and-page-in-place-of-the-next-seven-days-forecast.md) put, above the bars, "이번 주 n장 · m분" and the streak after a flame. The bars already show each day's cards, the card's spoken sentence already states the week's cards and minutes, and the streak shows on the today card's chip (twice on one screen, as ADR 0088's consequences noted).
- **Alternatives considered:**
  - **Keeping the summary and dropping the streak.** The owner named both.
  - **Moving the week's total into the title.** It would be the same figure in another place.

## Decision

- The card draws its title, then its seven bars, on the phone and the web. The summary line and the streak line are removed. Nothing else about the card's layout changes.
- The card is read as before: "지난 7일 동안 n장을 m분 공부했어요", each day as "월요일 32장", and "기록 열기" as its hint.
- The `weekSummary` string is removed. `streakDays` stays, as the today card's chip uses it.
- This **refines** ADR 0088's "above the bars" line. The figures, the bars, the tap to 기록 and the reading are unchanged.

## Consequences

- The streak shows once on the 오늘 tab and page: on the today or done card's chip. A user with no streak sees the same card as before.
- The week's minutes are heard from the card's sentence and no longer seen.

## Signs the decision was wrong

- Users ask where the week's total went.
