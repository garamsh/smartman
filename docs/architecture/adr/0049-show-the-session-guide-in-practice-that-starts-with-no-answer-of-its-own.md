# ADR 0049: Show the session guide in practice that starts with no answer of its own

> Status: accepted
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- [ADR 0044](0044-show-a-guide-with-the-session-s-size-in-the-previous-card-s-place-at-every-session-s-start.md) shows the session's guide in the previous card's place from every session's start until its first answer. It leaves out practice, even when the session opened on the completion card with no answer of its own. That exclusion was the PM's design, not the owner's.
- Every study button opens the screen at zero cards left ([ADR 0040](0040-keep-every-study-button-enabled-at-zero-cards-left.md)). Where cards were answered earlier today, the screen opens on the completion card, and "계속 학습" starts practice with nothing above the current card.
- The owner, on the device, 2026-10-18 (issue #162), sent a screenshot of that state: 0/0 with a full bar, the current card, and the upper half blank. They asked why the blank space was still there.
- Practice has nothing that marks it apart ([ADR 0033](0033-count-cards-left-per-study-day-from-04-00-and-continue-as-unrecorded-practice.md)). The guide's heading states where the user stands and does not name the mode.
- The PM's decision in the issue: the guide shows from the start of any session, practice included, until its first answer. In practice its heading is "오늘 할 카드를 다 했어요" in place of the size, which practice does not have. The web does the same.

## Decision

- **When.** The guide shows while the session has no answer of its own, practising or not. The first answer takes it away for the rest of the session. A session whose own answers already fill the previous card's place shows none in practice, as before.
- **Heading.** Where the session's size holds no card, the heading is "오늘 할 카드를 다 했어요" ("You've done today's cards"), in place of "오늘 n장 · 약 m분". Practice that starts with no answer of its own is reached only from a session that opened with no card left, since reaching the completion card otherwise takes an answer. So that size is always zero cards, and the heading follows from the size alone. The three lines that follow are unchanged.
- **Web.** The same, in `web/src/features/study/`.
- **Supersessions.** This replaces ADR 0044's exclusion of practice.

## Consequences

- No study screen opens on a current card with the previous card's place blank.
- The heading in that state repeats the today card's done line, so the two say the same thing about the day.

## Signs the decision was wrong

- Users read "오늘 할 카드를 다 했어요" above a card as a sign that answering it records something.
- Users who practise often find the guide in their way at each practice session's start.
