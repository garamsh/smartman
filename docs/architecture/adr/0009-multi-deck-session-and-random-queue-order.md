# ADR 0009: Study a non-empty selection of decks in one session, and draw the queue's order and re-show gap from one seeded random source

> Status: accepted; its header provider, `todayCardProvider`, superseded by ADR-0011
> Date: 2026-10-15

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #19 lets the user study several decks in one session. The PM decided there:
  - the deck list gets a selection mode, entered by a long-press, with "학습 (n)" starting one session over the selected decks and a clear action leaving the mode;
  - the deck list's header card shows "오늘 할 카드 n장", counted by the queue rules, and a "모두 학습" action that studies every deck;
  - `studyScreenProvider` takes a non-empty set of `DeckId`s instead of one `Deck`, and `deck` still does not import `study`;
  - the queue is every card due at or before now across the selected decks, plus up to `newCardLimit` (20) new cards in total, oldest first by creation time;
  - the order is randomized so that users cannot learn the sequence: due cards shuffled, new cards at random places among them, and the re-show gap after "Don't know" drawn uniformly from 3 to 5 cards, or as many as remain;
  - all randomness comes from one `Random` the session receives, seeded from the session start in the app and injected in tests.
- [ADR 0005](0005-study-queue-and-card-state.md) ordered the queue earliest due first, then new, with a fixed `reshowGap` of 3, and its entry point built the screen for one deck. Its state storage and [ADR 0007](0007-study-swipe-screen-and-session-toggle.md)'s screen, toggle and rescheduling rules are not in question.
- The header count needs each card's stored state, which only `study` reads, and a failure of that read is a `StudyFailure`, which only `study` describes.
- Alternatives considered for the header:
  - A count function declared in `deck` and overridden at the composition site. `deck` would then receive a `StudyFailure` it cannot describe to the user.
  - The count computed in `deck` from its own tables. The due cards are decided by `card_states`, which `deck` does not read.
- Alternatives considered for the order:
  - Shuffling the due cards and appending the new ones as a block. The issue rules this out: new cards always trail.
  - `List.shuffle`. Its draws are not documented, so a test cannot construct a random source that keeps a known order.

## Decision

- **Selection.** `deck` declares `DeckSelection`, a set of deck ids that cannot be empty: one deck, or the result of `DeckSelection.of`, which is null for no deck. `studyScreenProvider` builds the screen for a `DeckSelection`; the card list passes its own deck's.
- **Header.** `deck` declares `todayCardProvider`, which builds the deck list's header card for a selection of every deck. The composition site overrides it with `study`'s `TodayCard`, as it does `studyScreenProvider`. `TodayCard` counts with the same functions that build a session's queue and starts that session itself.
- **Membership.** A session reads the cards of every selected deck and their stored states, then takes every card due at or before now and up to 20 cards with no state, oldest first by creation time across the decks.
- **Order.** The selected cards are put in a uniformly random order by a forward Fisher–Yates shuffle over the due and new cards together, which places each new card at a uniformly random position among the shuffled due cards. A draw of 0 keeps the card in its place.
- **Re-show gap.** A "Don't know", or a toggle that puts a card back, inserts it after a gap drawn uniformly from `reshowGapMin` (3) to `reshowGapMax` (5) other cards, or after as many as remain.
- **Random source.** The session receives one `Random` and draws every choice above from it. `study` declares `studyRandomProvider`, a function from the session's start time to that `Random`; the composition site overrides it with one seeded from that time, and tests override it.

## Consequences

- Two sessions over the same cards show them in different orders, and a card answered "Don't know" returns after a gap the user cannot count on.
- Tests fix the order: a seeded `Random` repeats one order, and a source that always draws 0 keeps the order selected and the shortest gap.
- The queue no longer puts the most overdue cards first. A session the user leaves early studies a random part of the backlog rather than its oldest part.
- `deck` gains a second provider that the composition site overrides with a `study` widget, the pattern ADR 0005 named as a sign to watch.
- The header count is read again when the deck list comes back on top, not continuously. A write still running when the user returns can be missed by that read.

## Signs the decision was wrong

- Users with a large backlog leave sessions early and find their most overdue cards keep going unstudied.
- Users report a "Don't know" card coming back at a gap they find too short or too long, now that it varies.
- The header count and the session it opens disagree in practice, from a write the read missed or a card that became due in between.
- More `deck` screens need `study` widgets, and the providers overridden at the composition site keep multiplying.
- A user selects every deck by hand often enough that "모두 학습" and the selection mode read as two ways to do one thing.
