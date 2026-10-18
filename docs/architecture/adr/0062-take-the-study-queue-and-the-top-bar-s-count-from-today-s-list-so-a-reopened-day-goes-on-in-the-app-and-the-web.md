# ADR 0062: Take the study queue and the top bar's count from today's list, so a reopened day goes on, in the app and the web

> Status: accepted
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

- **Today's list** places each card of the session's decks through the engine's `today` (ADR 0061): `left`, `done` or `absent`. It reads the card's stored state and the answers of the study day, 04:00 to 04:00 in the zone (ADR 0033). The app calls it through the bridge's synchronous `todays_list` (`app/lib/study/src/today.dart`). The web calls it through the WebAssembly's `todaysList` (`web/src/features/study/today-list.ts`): on the server for the queue, and in the browser for the count.
- **The queue** is the cards the queue rules select (ADR 0025, ADR 0033), plus the cards today's list keeps `left` that those rules did not select. Those are the cards answered "Don't know" last today, which their state no longer makes due. The session orders them all together, as it orders the queue. Within a session, a "Don't know" is shown again after 3 to 5 other cards, as before.
- **The top bar** counts done out of done plus left over the day's cards: those answered today before the session opened, the queue it opened with, and the new cards it takes past today's (ADR 0049), each once.
  - Done is the day's cards today's list places `done`, from the answers stored before the session and the session's own, as they stand.
  - So a "Don't know", or a change to one, leaves a card left, and its later "Know" makes it done.
- **A new study day** starts from 0, since no answer of it is stored yet.
- **The web** builds its plan on the server with the same list. It sends the day's bounds, today's answers with their cards and times, and the stored state of every card answered today, so the browser's session counts the same way. The study screen starts its session once the engine's module has loaded in the browser. Until then it shows the page's skeleton; if the module fails to load, it says so.
- **Unchanged:** the engine's FSRS, the guide ("오늘 n장" counts the cards the session opened with), the completion card and the 오늘 tab's counts. There is no stored plan, no schema change and no Supabase change.

## Consequences

- Leaving and coming back the same day shows the same count going on, such as "3/6" in place of "0/3". A card answered "Don't know" is back in the queue until it is answered "Know".
- The count can go down: a card changed to "Don't know" is no longer done.
- Every app test that builds a session loads the engine's native library first (`app/test/flutter_test_config.dart`), since the session calls it.
- The web study screen waits on the engine's module before its first card, as its first write already did.
- The 오늘 tab's daily goal still counts "done" its own way (`DailyGoal`). It is not yet taken from today's list.

## Signs the decision was wrong

- Users find a card failed early in the day coming back across many sessions, and stop opening the day's study.
- The top bar and the 오늘 tab disagree on what is done in ways users notice, which would mean the goal should take today's list too.
- The web's skeleton shows long enough that users notice the engine's module loading.
