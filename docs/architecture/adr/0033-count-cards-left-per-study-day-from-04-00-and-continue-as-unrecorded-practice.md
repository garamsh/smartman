# ADR 0033: Count the cards left per study day from 04:00, end the day's cards on a completion card, and continue as practice that writes nothing

> Status: accepted; its 20 new cards a day superseded by ADR-0043
> Date: 2026-10-16

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #87 records the owner's study-load model, decided on 2026-10-16 with the v3 canvas (the artboards `Summary` and `HomeDone`): a user faces one number, the cards left today; studying lowers it, it never goes below zero, and what is left carries over only as reviews. Once it reaches zero, the same study screen continues as practice over the cards studied today, and practice is never recorded.
- On `main` at `2cb056bd095ca4c47d6a557feda56d5f2b912f7b`, both queues take up to `newCardLimit` (20) new cards every time a session opens ([ADR 0009](0009-multi-deck-session-and-random-queue-order.md)), so a deck with unstudied cards never reaches zero, and a card is due when its due time is at or before the moment the queue is read ([ADR 0025](0025-order-a-review-backlog-by-due-date-and-pause-new-cards.md)), so the count grows during the day as cards fall due.
- The issue decides the rules: a study day starts at 04:00 in the device's time zone (the browser's on the web); a day takes 20 new cards less those already first answered in it, across every deck, with no unused quota carried over; the cards left today are the due cards plus that remaining quota; at zero with nothing answered today the screen says "오늘은 학습할 카드가 없어요"; at zero during a session a completion card takes the current card's place under the stack, with "오늘 학습 완료", the line 안다 n · 모른다 n · minutes · streak, and [계속 학습] and [그만하기]; practice starts with every card answered today, shuffled, repeats the missed ones each after a gap until all are right, then the whole set again, and writes nothing. The backlog rule still pauses new cards. No usage hint is added to a study screen.
- The issue leaves the mechanics open. The PM decided them on 2026-10-16, on the worker's question in the dispatch of #87:
  - the constants stay in `queue.dart` and `queue.ts`, with a test that fails when they drift, as the theme tokens are kept ([ADR 0030](0030-read-only-what-each-web-page-shows-and-size-the-web-from-the-app-tokens.md)), rather than one JSON file both clients load, which would need an asynchronous asset load at the phone's composition site and a further link into `app/`;
  - the streak is the study days in a row with a stored answer, across every deck, counted back from today when today has one and from yesterday otherwise, so an unstudied today breaks nothing until it ends;
  - the completion line counts today's answers over the session's decks: those stored before the session and the session's own, with the minutes the sum of their times on screen, rounded up;
  - practice takes every card of the session's decks answered at least once today, reviews and new cards alike;
  - the web reads the study day on the server, in the zone a cookie the browser writes names, with Asia/Seoul when there is none;
  - closing the screen before the count reaches zero leaves it, since the summary it showed is removed;
  - practice answers join the stack and toggle with the same queue effects, writing nothing, and the top bar stays as the day's session left it.
- A card is counted on its day: "a card is never shown before its day" and a count studying only lowers need a card due later today to count from the start of the day, and a card due tomorrow not at all. the engine rounds every interval to whole days, at least one (`engine/src/fsrs.rs` at `2cb056bd095ca4c47d6a557feda56d5f2b912f7b`), and a study day lasts 24 hours outside a change of offset, so a card answered today is next due on a later day and the count does not rise again after an answer.
- Alternatives considered:
  - The due time against the moment the queue is read, as before. The count would grow during the day, and reaching zero would not mean the day is done.
  - Midnight as the day's start. A session past midnight would start a new day and a fresh quota for a user still studying the evening's cards.
  - Computing the web's day in the browser. The pages read and select on the server ([ADR 0030](0030-read-only-what-each-web-page-shows-and-size-the-web-from-the-app-tokens.md)), so the server needs the zone; a cookie set on every page, the sign-in page included, reaches it before any counted page.

## Decision

- **Day.** A study day runs from 04:00 to the next 04:00 in the device's time zone, read at the instant each boundary names, so a day across a change of offset starts and ends at 04:00 local time.
- **Quota.** A day takes `newCardLimit` (20) new cards less the cards first answered in it, across every deck, from the stored reviews, never below zero. A day's unused quota is not carried to the next.
- **Cards left today.** A session over some decks takes every card due before the day ends and as many new cards as the day has left, oldest first; in a backlog, which counts the same due cards, it takes no new card. The deck screens count the same selection.
- **Nothing to study.** With no card left and no card of the decks answered today, the study screen says "오늘은 학습할 카드가 없어요".
- **Completion.** Once no card is left, the completion card takes the current card's place under the stack: the mascot, "오늘 학습 완료", today's 안다 and 모른다 answers over the decks, their minutes, the streak, [계속 학습] and [그만하기]. A toggle that puts a card back takes it away again. Closing the screen leaves it; there is no summary.
- **Practice.** [계속 학습] continues in the same screen and route: every card of the decks answered today, shuffled; then the cards missed in that pass, each put back after the re-show gap until it is answered right; then all again, until the user stops. A practice answer joins the stack and can be toggled with the same effects on the practice queue. It writes no review, no card state and nothing for sync, and changes no count, streak or statistic. The session's own answers, toggled during practice, are still written.
- **One definition.** `newCardLimit`, `studyDayStartHour` (4), `reshowGapMin`, `reshowGapMax`, `backlogDays` and `backlogBucketSize` are constants in `app/lib/study/src/queue.dart` and `web/src/features/study/queue.ts`; `web/src/features/study/__tests__/rules.test.ts` fails when one differs from the other's, or when `queue.dart` declares one it does not compare.
- **Web time zone.** The root layout's head script writes the browser's IANA zone into the cookie `smartman-tz`; the server reads the day in it, or in Asia/Seoul without a valid one.
- **Supersessions.** This replaces ADR 0009's up to 20 new cards per session and its due cards at or before now; ADR 0025's due cards at or before now in the backlog count; ADR 0007's close button and back ending the session on the summary; and ADR 0027's summary with the next review.

## Consequences

- The count on every deck screen falls as the user studies and reaches zero once the day's cards are done; tomorrow's cards and tomorrow's quota wait for 04:00.
- A user who studies 20 new cards in one deck sees no new card in another deck until the next day.
- The phone's session reads today's answers and every answer's time when it opens; the web's study page reads today's answers, the earlier answers of the cards answered today, and the latest answers a page at a time until the streak is decided. On `/` and `/decks/[id]`, the reads of today's answers wait on up to four requests in two steps, where ADR 0030's reads wait on two.
- Practice lives in the session alone: closing the screen discards it, and nothing on another device sees it.
- The completion card's streak is read when the session opens, so an answer synced from another device after that is not in it until the next session.
- On a day 25 hours long, where clocks go back, a card answered in its first hour with a one-day interval falls due before the day ends and is counted again that day.
- A web visitor whose browser names no zone, or a server request before the cookie is set, counts the day in Asia/Seoul.

## Signs the decision was wrong

- Users who study past 04:00 report the night's cards counting against the next day's quota, or users in another schedule ask for another start hour.
- Users with several decks report new cards they wanted in one deck used up by another.
- Users report the count rising during the day, or a card shown before its day.
- Users expect practice to count, ask for its answers to be kept, or report losing practice they closed.
- The web's counts disagree with the phone's for the same user at the same moment, from a zone the cookie did not carry.
- The deck pages' added reads show up in their load time.
