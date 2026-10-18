# ADR 0060: Count a reopened study day from today's answers, so the top bar goes on instead of starting again

> Status: accepted
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #194 records the owner's report of 2026-10-18. A user leaves today's study part-way and comes back. The top bar's count then drops to the cards left and starts again at 0, so the session reads as a new, smaller one.
- The cause:
  - a session builds its queue when it opens, from the cards left today (`study.md` §Session);
  - an answered card is due a day or more later, as the engine's intervals are whole days (`engine.md`), so it leaves the queue;
  - the top bar counted the cards answered in this session out of the queue it opened with.
- **The owner's design, as settled on #194.**
  - The owner first proposed storing the day's plan on the device, then withdrew it the same day in favour of deriving the view from `reviews` and `card_states`.
  - The owner then added a rule that a card answered "Don't know" stays in today's list until "Know".
  - The PM's comment on #194 of 2026-10-18 withdraws that rule from #194. The owner is reopening whether same-day relearning belongs in the engine (#195), so #194 builds only the count.
- **What the device already holds.** The session already reads the decks' answers stored since the study day began (`answersSince`), for the completion card's counts and the streak. It also already knows the cards answered today before it opened.
- Alternatives considered:
  - **A stored plan of the day's cards**, a local table or a list per study day. It is a second copy of what the behaviour log already holds, so the two could disagree. It also needs a schema step.
  - **Counting the queue alone with a smaller "resume" guide.** The count would still restart at 0, which is what the owner reported.
  - **Keeping a "Don't know" card in today's list.** This is withdrawn until #195 decides whether same-day relearning is the engine's.

## Decision

- **The day's count.** The top bar counts the day's cards: done out of done plus left.
  - **Done** is the cards of the session's decks answered today, from 04:00 in the device's zone as ADR 0033 sets the study day. It counts the answers stored before the session opened and the session's own, each card once, whatever its answer.
  - **The total** is those answered before the session opened, the queue it opened with, and the new cards it takes past today's (ADR 0049). Each card counts once.
- **Nothing else changes.**
  - The queue is still built when the session opens, from the cards left now.
  - The guide still shows "오늘 n장 · 약 m분" for the cards the session opened with.
  - The completion card, the 오늘 tab's counts and the engine are unchanged.
  - There is no schema change and no new table.
- **Counted once.**
  - A "Don't know" re-show, or a changed answer, does not add a card again: done counts distinct cards.
  - A card answered in an earlier session that day is never in the new queue, since it is due a day or more later.
- **A new study day** starts from 0, since no answer of it is stored yet.

## Consequences

- Leaving and coming back the same day shows the same count going on, such as "4/6" in place of "0/2".
- The guide's size and the top bar's total differ once the day has answers. The guide counts the cards left, and the total counts the day's.
- The web's study top bar still counts the session alone (`web/src/features/study/session.ts`). It reads the same rows, so the same count can be built there.
- A card answered "Don't know" in an earlier session is done and not in today's list. #195 decides whether it comes back the same day.

## Signs the decision was wrong

- Users read the higher count as cards they still have to study, and expect the total to shrink as before.
- The count and the 오늘 tab's daily goal disagree in a way users notice. The goal counts a "Don't know" card due again today as not done; the top bar counts it done.
- A day's count includes cards from another deck selection the user did not open. That would mean the answers read are not limited to the session's decks.
