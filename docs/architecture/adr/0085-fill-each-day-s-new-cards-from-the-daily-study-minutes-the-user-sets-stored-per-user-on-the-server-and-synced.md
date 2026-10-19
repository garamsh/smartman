# ADR 0085: Fill each day's new cards from the daily study minutes the user sets, stored per user on the server and synced

> Status: accepted
> Date: 2026-10-20

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #271**, the owner's decision of 2026-10-19, which replaces the 2026-10-17 decision (#141, [ADR 0043](0043-set-each-day-s-new-cards-from-the-user-s-recency-weighted-study-time-and-pace-and-count-an-answer-s-time-only-in-the-foreground.md)) that a day's study time is inferred from the user's history.
- **The inferred study time locks itself in.** A user stops at the amount the app gives, so the recorded study time never grows past the first 20 cards, and neither does the daily amount. Due reviews are already fixed by their dates. The only free choice is how many new cards to start, and that choice sets every later day's review load. So the user chooses a daily study time, and the app fills it.
- **The rule the PM set, following the owner:**
  - the user sets daily study minutes, from presets of 10, 15, 20, 30, 45 and 60, or a custom value from 5 to 180, with 20 by default;
  - due reviews come first; new cards fill the minutes left after the reviews, at the user's measured pace, the recency-weighted pace of ADR 0043, 10 s an answer until enough answers exist;
  - new cards never go below zero, and pause in a backlog, as before;
  - the cold start of 20 cards for 5 study days goes, and minutes and pace decide from the first day;
  - "학습하기" past today's cards stays ([ADR 0049](0049-study-in-one-flow-that-goes-on-past-today-s-cards-as-recorded-study-with-the-current-card-showing-its-front-alone.md)), and extra study does not change the setting;
  - the setting syncs between the phone and the web, is stored per user on the server by a migration that changes no row, and is used offline on the phone.
- **What the phone syncs today** ([`sync.md`](../sync.md)): four tables, each pulled above a revision cursor and pushed while unsynced, with the later `updated_at` winning a conflict.
- **Alternatives considered:**
  - **The minutes as a column of `public.profiles`.** Row-level security lets every user read the profile of a user with a public deck, so a study setting there would be readable by others, and `profiles` holds sharing's display name.
  - **The setting as a fifth revisioned table, pulled above a cursor.** A user has one row, so a cursor saves nothing; the row is pulled whole each run.
  - **A direct upsert of the row from both clients.** An older device's push would overwrite a later edit made elsewhere. `save_study_settings` writes only where the stored edit is older, as a review's rating moves.
  - **Keeping ADR 0043's reviews set aside**, the daily load plus the reviews due beyond it spread over a week. The owner's rule is the minutes left after the due reviews; the backlog rule already pauses new cards when reviews pile up.

## Decision

- **The rule.** A day's new cards are max(0, floor((M × 60,000 − D × review pace) / first-answer pace)), in whole milliseconds, where:
  - M is the user's daily study minutes;
  - D is the reviews due as the day stood when it started: the cards due before it ends not answered in it, and the cards answered in it that had an answer before it.
  - The pace, the study days and the answer cap are ADR 0043's, unchanged. So is an answer's time counting only in the foreground.
  - The cards first answered in the day still come off its new cards, and an unused figure is not carried over.
  - A change of M applies to today at once.
  - In a backlog no new card is taken, as [ADR 0025](0025-order-a-review-backlog-by-due-date-and-pause-new-cards.md) decides.
- **The constants**, once per client in `app/lib/study/src/queue.dart` and `web/src/features/study/queue.ts`, which `rules.test.ts` compares:
  - `defaultDailyMinutes` 20, `minDailyMinutes` 5 and `maxDailyMinutes` 180;
  - `dailyMinutePresets` 10, 15, 20, 30, 45 and 60;
  - `rules.test.ts` also checks the bounds against the migration's check.
  - `coldStartNewCards`, `coldStartStudyDays`, `studyTimeHalfLife`, `studyTimeStepPercent` and `reviewSpreadDays` are removed.
- **When the last new card starts.** For a preview of what a choice means, both clients name the study day on which the last never-reviewed card is first answered: today when today takes them all, otherwise after as many days of the day's figure as the rest needs, and none when the figure is zero.
- **On the server**, `public.study_settings` holds a user's row: `user_id`, `daily_minutes` checked to 5 to 180, and `updated_at`.
  - A user selects its own row alone and writes none directly.
  - `save_study_settings(daily_minutes, updated_at)`, `security definer`, stores the caller's row where the stored one is older or absent, and answers whether it did.
  - A user without a row studies the default.
  - The row deletes with its user.
- **On the phone**, the drift table `study_settings` (schema 9) holds at most one row: the minutes, their edit time and `dirty`.
  - No row reads as the default.
  - `StudyRepository.setDailyMinutes` writes it unsynced, so the phone uses it offline.
- **Sync.**
  - Each run pulls the account's row after the four tables and merges it: the later edit wins, and on a tie an unsynced local edit wins, as for decks.
  - A local row kept stays unsynced, so the push repairs the server's.
  - The push sends an unsynced row through `save_study_settings`, then clears `dirty` while the row is still as pushed.
  - Claiming the database for another account and sign-out delete it with the synced rows.
- **On the web**, `readToday` reads the user's row with the four reads, and the Server Action `saveDailyMinutes` saves through `save_study_settings` with the time of the save, refusing minutes outside 5 to 180 unsent.
- **Supersessions.** This supersedes ADR 0043's study time, its cold start and its reviews set aside. ADR 0043's foreground time, study days, pace and minutes stand.

## Consequences

- A new user's first day takes 120 new cards at the default 20 minutes and the unknown pace of 10 s, until a lower setting or a measured pace changes it.
- A user who studies more than the minutes, through "학습하기", sees no change to later days' new cards; only the setting moves them.
- The phone and the web count the same day from the same minutes once both have synced; a phone offline counts with the setting it last held.
- How the setting is shown and changed is decided with its screens, in a later change.

## Signs the decision was wrong

- Users keep the default, and new-card counts far above what they finish pile reviews into a backlog within a week.
- A setting made on one client is lost to an older push from the other.
- The preview's date drifts far from when the last new card is actually started, because later days' reviews take more of the minutes than today's.
