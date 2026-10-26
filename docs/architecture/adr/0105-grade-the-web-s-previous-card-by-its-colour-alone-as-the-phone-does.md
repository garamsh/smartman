# ADR 0105: Grade the web's previous card by its colour alone, as the phone does

> Status: accepted
> Date: 2026-10-26

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #380.** It carries to the web the owner's decision on #375 for the phone, which [ADR 0099](0099-answer-study-cards-by-swipe-alone-and-grade-the-previous-card-by-its-colour-alone-on-the-phone.md) records: the previous card shows no "안다" or "모른다" chip.
  - The owner's reason, as ADR 0099 records it: the design wants nothing on a card that is not its content.
  - The owner chose this knowing its cost: a colour-blind user who does not use a screen reader can no longer read the grade from the card.
- **The web's chip.** [ADR 0035](0035-show-the-previous-and-current-study-card-reach-earlier-cards-three-at-a-time-re-decide-the-centred-card-and-grade-each-card-by-its-colour-and-a-chip.md) gave both clients the chip "so the grade never rests on colour alone". On the web, `GradedCard` draws it, the same component that draws the day's last card from an earlier session. The coach's last step draws a sample previous card with the same chip.
- **Other chips.** `GradeChip` also names the grade in the whole card's dialog and in "이번 학습", the list beside the cards from 1024 px. Neither is a card's face, and #380 keeps the dialog's words.
- **Out of scope.** The owner removed the answer buttons for the phone's swipe study alone; the web keeps its buttons and keys.

## Decision

- **The cards.** On the web, the previous card shows its grade by its fill and line alone: `know-card` inside `know-line`, or `dont-know-card` inside `dont-know-line`, with no chip. The day's last card from an earlier session and the coach's sample card are drawn the same way.
- **Kept:**
  - the card's accessible name, which names its grade;
  - the "카드 전체 보기" dialog, which states the grade in words with its chip;
  - "이번 학습", which keeps its chips;
  - the swipe's reveal behind a moving card, "안다로 바꿔요" or "모른다로 바꿔요".
- **Supersession.** This replaces, on the web, ADR 0035's chip on the previous card.

## Consequences

- The phone and the web draw a previous card alike.
- On either client, a colour-blind user who does not use a screen reader reads the grade only by opening the card or, on a wide screen, in "이번 학습".
- `GradeChip` stays, for the dialog and the list.

## Signs the decision was wrong

- Users misread a previous card's grade, or open cards only to learn it.
- Accessibility feedback names the grade that rests on colour alone.
