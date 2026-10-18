# ADR 0062: Take the study queue and the top bar's count from today's list, so a reopened day goes on, in the app and the web

> Status: accepted; its resume line's place in the session's guide superseded by ADR-0063
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #194 records the owner's report of 2026-10-18. A user leaves today's study part-way and comes back. The top bar's count then drops to the cards left and starts again at 0, so the session reads as a new, smaller one.
- The cause:
  - a session builds its queue when it opens, from the cards left today (`study.md` §Session);
  - an answered card is due a day or more later, as FSRS's intervals are whole days (`engine.md`), so it leaves the queue;
  - the top bar counted the cards answered in this session out of the queue it opened with.
  - A card answered "Don't know" was shown again only within the session that took the answer. Closing the screen lost it, so a reopened session never showed it that day.
- **The design, as settled.**
  - The owner first proposed storing the day's plan on the device, then withdrew it in favour of deriving the view from `reviews` and `card_states`.
  - The owner then decided (#195, ADR 0061) that a card failed today stays in today's list until it is passed. Done means a card's latest answer today is "Know".
  - The rule is the engine's `today`, shared by the app, the web and the server, rather than each client's.
- Alternatives considered:
  - **A stored plan of the day's cards**, a local table or a list per study day. It is a second copy of what the log holds, which could disagree with it, and it needs a schema step.
  - **Counting the cards answered at least once.** This is what #197 first built. A card answered "Don't know" would count as done while it is still to be studied.
  - **Each client's own rule for the count and the queue**: the app and the web could drift apart.

## Decision

- **Today's list** places each card of the selected decks through the engine's `today` (ADR 0061): `left`, `done` or `absent`. It reads the card's stored state and the answers of the study day, 04:00 to 04:00 in the zone (ADR 0033).
  - The app calls it through the bridge's synchronous `todays_list` (`app/lib/study/src/today.dart`).
  - The web calls it through the WebAssembly's `todaysList` (`web/src/features/study/today-list.ts`): on the server for the queue and the pages' counts, and in the browser for the session's count.
  - A list that does not place every card given is an error, not a default.
- **One day plan, one count.** `dayPlanOf` turns the list into the day's plan over a selection:
  - the cards the queue rules select (ADR 0025, ADR 0033);
  - the cards still on "Don't know" that the rules did not select: those answered "Don't know" last today, which their state no longer makes due;
  - the cards done.
  Left is the selection plus the cards still on "Don't know". The study session, the top bar, `TodayCounter` (the deck chips, the 오늘 tab's rows and the deck screen), the 오늘 tab's count and daily goal, and the web's 오늘 and deck pages all count from it, so they agree.
- **The daily goal** is done plus left: done is the cards answered "Know" last today, and a card answered "Don't know" is left until it is answered "Know".
- **The queue** a session opens with is the selection, ordered as before. The cards still on "Don't know" come back as a re-show does: each after a gap of `reshowGapMin` to `reshowGapMax` cards drawn from the session's random source, or at the end when fewer remain. This holds in a backlog as out of one, so a card is never left behind every overdue card. Within a session, a "Don't know" comes back after 3 to 5 other cards, as before.
- **The top bar** counts done out of the day's cards: those answered today before the session opened, the queue it opened with, and the new cards it takes past today's (ADR 0049), each once. Done is the day's cards today's list places `done`, from the answers stored before the session and the session's own, as they stand. So a "Don't know", or a change to one, leaves a card left, and its later "Know" makes it done.
- **A session keeps its day.** Its own answers count toward its progress in the study day it opened in, whatever their time, so a session open across 04:00 goes on counting. The next day's list starts at the first open after 04:00, from 0 done.
- **The resume line.** A session that opens with a card of the day done reads "이어서 해요 · 남은 n장 · 약 m분" in the guide, n being the cards left. The day's first session keeps "오늘 n장 · 약 m분". This replaces ADR 0044's guide text for a session that resumes a day. The guide's minutes and the today card's still agree, since both count the day plan's left cards.
- **The web** builds its plan on the server with the same list. It sends the day's bounds, the cards still on "Don't know" apart from the selection, whether the day resumes, today's answers with their cards and times, and the stored state of every card answered today.
  - The study screen starts its session once the engine's module has loaded in the browser, showing the page's skeleton until then.
  - If the module fails to load, the screen says "학습 화면을 불러오지 못했어요. 연결을 확인하고 다시 시도해 주세요." with "다시 시도", which loads it again.
  - If the server's module fails to load, each page shows its own failure message.
- **Unchanged:** the engine's FSRS and the completion card. There is no stored plan, no schema change and no Supabase change.

## Consequences

- Leaving and coming back the same day shows the same count going on, such as "3/6" in place of "0/3", under "이어서 해요". A card answered "Don't know" is back a few cards into the queue until it is answered "Know".
- The count can go down: a card changed to "Don't know" is no longer done.
- The 오늘 tab and the study screen agree. A card answered "Don't know" keeps the today card from reading done, and keeps the goal from being reached.
- Every app test that builds a session loads the engine's native library first (`app/test/flutter_test_config.dart`), since the session calls it.
- The web pages that count today, and the study screen, wait on the engine's module, as the study screen's first write already did.

## Signs the decision was wrong

- Users find a card failed early in the day coming back across many sessions, and stop opening the day's study.
- The top bar and the 오늘 tab disagree on what is done, which would mean a count was built without the day plan.
- The web's skeleton shows long enough that users notice the engine's module loading.
