# ADR 0046: State where the user stands today on the today card, in place of the goal's numbers

> Status: accepted; its goal's numbers in the ring superseded by ADR-0091; its status line on the phone superseded by ADR-0120
> Date: 2026-10-17

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- [ADR 0036](0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md) gave the today card the goal ring, done over goal, and below it "the goal's line", "하루 목표 n장 중 m장 했어요", which repeats the ring's numbers.
- Issue #139 records the owner's direction of 2026-10-17, on the device: replace that line with a short line that changes with progress. The PM wrote the wording in the issue, chosen by the first state that holds:

  | State | ko |
  |---|---|
  | nothing answered yet, streak 2 days or more | "{n}일째 이어 가는 중이에요" |
  | nothing answered yet | "오늘의 첫 카드를 기다리고 있어요" |
  | 3 cards or fewer left | "거의 다 왔어요" |
  | half of the goal or more done | "절반을 넘었어요" |
  | some done | "좋은 출발이에요" |

- The owner's no-hint rule stands: [ADR 0044](0044-show-a-guide-with-the-session-s-size-in-the-previous-card-s-place-at-every-session-s-start.md) widened it for the session's guide alone. The line states where the user stands and never says what to tap. The done card and the backlog card keep their own text. Issue #91 will put the same lines on the web.

## Decision

- **Status.** In place of the goal's line, the today card states where the user stands, the first row of the table that holds over the daily goal and the streak: nothing done with a streak of two days or more; nothing done; three cards or fewer left; half of the goal or more done, exactly half included; some done. In English: "On a {n}-day streak", "Waiting for today's first card", "Almost there", "Past the halfway mark", "Off to a good start".
- **One rule.** The rule is `TodayStatus.of` in `app/lib/study/src/overview.dart`, beside `DailyGoal`; `home/` lays out the line it names.
- **Numbers.** The ring alone shows done over goal, and its semantics keep "하루 목표 n장 중 m장", so a screen reader loses nothing the removed line gave.
- **Wrapping.** The line breaks only between words (`keepWords` in `app/lib/design/word_break.dart`, moved there from the session guide so both use one helper).
- **Supersessions.** This replaces ADR 0036's "the goal's line" on the today card.

## Consequences

- The today card reads the goal's numbers once, in the ring, and its line changes as the day goes.
- The streak shows twice before the day's first answer from two days on: in the chip and in the line.

## Signs the decision was wrong

- Users miss the goal's numbers in words, or read the line as an instruction.
- Users find the streak said twice before the first answer redundant.
