# ADR 0043: Set each day's new cards from the user's recency-weighted study time and pace, and count an answer's time only in the foreground

> Status: accepted
> Date: 2026-10-17

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #141 records the owner's decisions of 2026-10-17: no per-deck goal or target date; the day's new cards follow the time this user studies and the speed this user answers, both weighted toward recent samples; days without study are left out of the study time; new cards stay one pool across decks, oldest first ([ADR 0009](0009-multi-deck-session-and-random-queue-order.md), [ADR 0033](0033-count-cards-left-per-study-day-from-04-00-and-continue-as-unrecorded-practice.md)); the backlog rule still pauses them ([ADR 0025](0025-order-a-review-backlog-by-due-date-and-pause-new-cards.md)).
- On `main` at `77c32bb76afa4b1d12acebf57b3b72a142c46481` a day takes 20 new cards (`newCardLimit`, ADR 0033), and the minutes shown use the median `duration_ms` of the latest 200 reviews ([ADR 0027](0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)).
- The issue's comments add, by the owner's last direction of 2026-10-17: an answer's clock runs only in the foreground (the phone resumed; the web page visible, with no window-focus tracking, idle timer or auto-lock), and each answer's duration is capped when the estimates are computed, the bound chosen from the data and the simulation, while stored rows keep their raw value.
- The PM decided on 2026-10-17, on the worker's questions in the dispatch of #141:
  - the stability bound applies to the study time T between consecutive study days, inside the recency-weighted recursion, rather than to a stored figure (which would add synced state) or to the new cards taken the day before (which would drag the figure down after a short day); the recursion starts from a fixed window of study days, so a client holding more history computes the same figure;
  - after the simulation showed that bounding T leaves the day-to-day swing of new cards near the mean figure itself, the time set aside for reviews is the collection's daily load plus the reviews due beyond it spread over k days (candidate G), with the k that keeps the swing near the daily load's alone while new cards still fall on return from a rest.
- The production read, aggregates only, run read-only by the PM on 2026-10-17 with the two queries recorded in the pull request that adds this ADR: 127 live answers of one user over three study days, all stored before foreground timing existed.

  | Answers | n | p10 | p25 | p50 | p75 | p90 | p95 | p98 | p99 | max | over 30 s | over 60 s | over 120 s |
  |---|---|---|---|---|---|---|---|---|---|---|---|---|---|
  | a card's first answer | 54 | 1.9 s | 3.3 s | 5.1 s | 7.7 s | 12.2 s | 20.3 s | 58.3 s | 58.9 s | 58.9 s | 2 | 0 | 0 |
  | later answers | 73 | 3.2 s | 3.9 s | 5.8 s | 10.1 s | 28.5 s | 70.8 s | 168.9 s | 654.9 s | 654.9 s | 7 | 5 | 3 |
  | all | 127 | 2.6 s | 3.8 s | 5.4 s | 9.4 s | 20.3 s | 58.3 s | 159.8 s | 168.9 s | 654.9 s | 9 | 5 | 3 |

  Its three study days held 24, 44 and 59 answers and took 2.2, 8.8 and 24.4 minutes, each list sorted on its own. One user's tail with background time in it cannot set the bound alone; it is one input beside the simulation.
- **The simulation**, `engine/examples/daily_load.rs`, run from `engine/` with `cargo run --locked --release --example daily_load`, seeds 1 to 20, SplitMix64, 180 days per run:
  - each day the user studies with a probability lower at the weekend, for a time drawn log-normally around the habit's minutes; the queue is every due card and the day's new cards, shuffled, with no new card in a backlog; the user answers until the queue is empty or the next card would pass the time, so a short queue leaves time unused;
  - recall follows the engine's retrievability, 0.6 for a new card; a "Don't know" comes back four cards later; every review draws a fuzz factor;
  - a first answer takes a log-normal time around 7 s, a review one around a median falling from 6.5 s to 2.5 s as the card is reviewed (spread 0.7); 3% of answers also store an idle time around 90 s (spread 1.0), the visible-but-away time the foreground clock still counts;
  - five habits: 15 minutes with weekend rests (steady); 15 minutes daily with two days' rest every 14 (rests); 15 minutes with a wide spread and frequent rests (irregular); 25 minutes changing to 8 on day 90 (25 → 8); and 8 changing to 25 (8 → 25);
  - each candidate changes one constant of the chosen rule. Swing: the mean change in new cards between consecutive study days after the cold start. Fit: the mean of |time studied − T| / T over the study days from day 30. Follow: the study days after day 90 until T is within 20% of the time studied over study days 21–50 after it. Return, recovery: after each rest, the new cards of the day of return over the mean of the three study days before, and the study days until a day takes 90% of that mean. Cap error: the mean of |T from stored durations − T from the true ones| / the latter. Time used: time studied over time available.

### Study-time estimate

| Candidate | Swing: steady / rests / irregular / 25 → 8 / 8 → 25 | Fit: steady / irregular | Follow: 25 → 8 / 8 → 25 | Return, recovery: rests | Cap error: steady | Time used: steady |
|---|---|---|---|---|---|---|
| weighted, half-life 3 | 9.96 / 6.89 / 12.48 / 8.05 / 9.32 | 0.203 / 0.309 | 17.4 / 18.4 | 0.40, 1.3 | 0.113 | 0.91 |
| weighted, half-life 7 | 7.54 / 4.83 / 9.31 / 6.57 / 6.79 | 0.187 / 0.294 | 23.8 / 23.4 | 0.42, 1.2 | 0.110 | 0.86 |
| weighted, half-life 14 | 6.72 / 4.06 / 8.23 / 5.44 / 5.91 | 0.180 / 0.289 | 26.7 / 22.0 | 0.41, 1.1 | 0.111 | 0.82 |
| plain mean of the window | 6.14 / 3.73 / 7.21 / 4.87 / 5.32 | 0.173 / 0.273 | 25.9 / 18.1 | 0.38, 1.1 | 0.110 | 0.78 |
| mean of the last 7 | 8.73 / 6.37 / 11.22 / 7.57 / 9.51 | 0.202 / 0.317 | 11.3 / 17.7 | 0.42, 1.4 | 0.113 | 0.90 |
| median of the last 7 | 8.10 / 5.70 / 10.32 / 6.20 / 8.09 | 0.188 / 0.313 | 12.5 / 21.3 | 0.41, 1.4 | 0.112 | 0.84 |

### Change bound

| Candidate | Swing: steady / rests / irregular / 25 → 8 / 8 → 25 | Fit: steady / irregular | Follow: 25 → 8 / 8 → 25 | Return, recovery: rests | Cap error: steady | Time used: steady |
|---|---|---|---|---|---|---|
| ±10% | 7.33 / 4.73 / 8.73 / 5.93 / 6.97 | 0.183 / 0.285 | 22.5 / 22.8 | 0.43, 1.2 | 0.111 | 0.85 |
| ±20% | 7.49 / 4.81 / 9.22 / 6.45 / 6.83 | 0.184 / 0.294 | 24.4 / 23.4 | 0.42, 1.2 | 0.111 | 0.86 |
| ±30% | 7.54 / 4.83 / 9.31 / 6.57 / 6.79 | 0.187 / 0.294 | 23.8 / 23.4 | 0.42, 1.2 | 0.110 | 0.86 |
| ±50% | 7.54 / 4.83 / 9.31 / 6.57 / 6.79 | 0.187 / 0.294 | 23.8 / 23.4 | 0.42, 1.2 | 0.110 | 0.86 |
| unbounded | 7.54 / 4.83 / 9.31 / 6.57 / 6.79 | 0.187 / 0.294 | 23.8 / 23.4 | 0.42, 1.2 | 0.110 | 0.86 |

### Pace half-life

| Candidate | Swing: steady / rests / irregular / 25 → 8 / 8 → 25 | Fit: steady / irregular | Follow: 25 → 8 / 8 → 25 | Return, recovery: rests | Cap error: steady | Time used: steady |
|---|---|---|---|---|---|---|
| pace half-life 3 | 7.55 / 5.26 / 8.86 / 6.28 / 7.16 | 0.187 / 0.296 | 28.0 / 22.9 | 0.42, 1.2 | 0.112 | 0.85 |
| pace half-life 7 | 7.33 / 4.73 / 8.73 / 5.93 / 6.97 | 0.183 / 0.285 | 22.5 / 22.8 | 0.43, 1.2 | 0.111 | 0.85 |
| pace half-life 14 | 7.31 / 4.74 / 9.13 / 5.99 / 6.89 | 0.182 / 0.295 | 24.4 / 21.2 | 0.42, 1.1 | 0.112 | 0.84 |
| pace half-life 28 | 6.76 / 4.63 / 9.38 / 6.19 / 7.16 | 0.181 / 0.288 | 24.0 / 22.6 | 0.41, 1.1 | 0.109 | 0.82 |

### Cold start

| Candidate | Swing: steady / rests / irregular / 25 → 8 / 8 → 25 | Fit: steady / irregular | Follow: 25 → 8 / 8 → 25 | Return, recovery: rests | Cap error: steady | Time used: steady |
|---|---|---|---|---|---|---|
| 1 study days | 6.30 / 3.57 / 7.48 / 4.96 / 6.23 | 0.184 / 0.277 | 14.2 / 22.3 | 0.43, 1.1 | 0.108 | 0.74 |
| 3 study days | 6.75 / 4.30 / 8.80 / 5.47 / 6.97 | 0.177 / 0.289 | 23.0 / 22.8 | 0.43, 1.1 | 0.109 | 0.80 |
| 5 study days | 7.33 / 4.73 / 8.73 / 5.93 / 6.97 | 0.183 / 0.285 | 22.5 / 22.8 | 0.43, 1.2 | 0.111 | 0.85 |
| 7 study days | 7.74 / 5.11 / 9.32 / 6.45 / 7.01 | 0.191 / 0.294 | 27.1 / 23.4 | 0.42, 1.2 | 0.112 | 0.87 |
| 10 study days | 7.71 / 5.56 / 9.69 / 7.02 / 6.95 | 0.188 / 0.306 | 26.3 / 22.5 | 0.42, 1.3 | 0.114 | 0.88 |

### Window

| Candidate | Swing: steady / rests / irregular / 25 → 8 / 8 → 25 | Fit: steady / irregular | Follow: 25 → 8 / 8 → 25 | Return, recovery: rests | Cap error: steady | Time used: steady |
|---|---|---|---|---|---|---|
| 14 study days | 8.14 / 5.68 / 10.38 / 6.73 / 8.01 | 0.197 / 0.311 | 18.1 / 21.7 | 0.47, 1.2 | 0.115 | 0.89 |
| 30 study days | 7.33 / 4.73 / 8.73 / 5.93 / 6.97 | 0.183 / 0.285 | 22.5 / 22.8 | 0.43, 1.2 | 0.111 | 0.85 |
| 60 study days | 7.28 / 4.64 / 8.90 / 5.84 / 6.79 | 0.181 / 0.284 | 25.7 / 21.4 | 0.43, 1.1 | 0.111 | 0.84 |

### Reviews set aside

| Candidate | Swing: steady / rests / irregular / 25 → 8 / 8 → 25 | Fit: steady / irregular | Follow: 25 → 8 / 8 → 25 | Return, recovery: rests | Cap error: steady | Time used: steady |
|---|---|---|---|---|---|---|
| A: reviews due today | 18.83 / 13.33 / 19.08 / 15.15 / 18.56 | 0.160 / 0.222 | 27.1 / 24.6 | 0.00, 1.9 | 0.112 | 0.86 |
| B: reviews due today, figure bounded ±5 cards | 4.44 / 4.24 / 4.55 / 4.04 / 4.29 | 0.201 / 0.285 | 32.0 / 23.9 | 0.71, 3.5 | 0.116 | 0.80 |
| E: daily load | 4.99 / 3.32 / 6.22 / 4.40 / 4.89 | 0.197 / 0.325 | 24.2 / 23.8 | 0.99, 0.3 | 0.111 | 0.87 |
| F: larger of daily load and reviews due | 12.76 / 6.49 / 14.12 / 10.05 / 10.68 | 0.143 / 0.194 | 23.9 / 17.9 | 0.00, 1.4 | 0.112 | 0.74 |
| G: daily load + excess over 2 days | 12.34 / 6.26 / 13.43 / 9.35 / 10.56 | 0.155 / 0.221 | 24.6 / 22.1 | 0.00, 1.3 | 0.112 | 0.78 |
| G: daily load + excess over 3 days | 10.60 / 5.96 / 12.44 / 8.45 / 9.39 | 0.167 / 0.257 | 24.5 / 20.8 | 0.02, 1.2 | 0.111 | 0.82 |
| G: daily load + excess over 5 days | 8.58 / 5.38 / 9.72 / 6.87 / 7.73 | 0.186 / 0.278 | 25.9 / 23.6 | 0.21, 1.2 | 0.111 | 0.84 |
| G: daily load + excess over 7 days (chosen) | 7.33 / 4.73 / 8.73 / 5.93 / 6.97 | 0.183 / 0.285 | 22.5 / 22.8 | 0.43, 1.2 | 0.111 | 0.85 |
| G: daily load + excess over 10 days | 6.63 / 4.34 / 8.64 / 5.51 / 6.42 | 0.190 / 0.313 | 23.3 / 24.1 | 0.57, 1.1 | 0.112 | 0.85 |
| G: daily load + excess over 14 days | 6.01 / 3.99 / 7.51 / 5.05 / 5.87 | 0.195 / 0.310 | 25.5 / 23.5 | 0.71, 1.0 | 0.111 | 0.86 |

### Duration cap

| Candidate | Swing: steady / rests / irregular / 25 → 8 / 8 → 25 | Fit: steady / irregular | Follow: 25 → 8 / 8 → 25 | Return, recovery: rests | Cap error: steady | Time used: steady |
|---|---|---|---|---|---|---|
| 20 s | 7.47 / 4.83 / 8.97 / 6.07 / 7.10 | 0.187 / 0.307 | 19.1 / 26.4 | 0.44, 1.1 | 0.043 | 0.84 |
| 30 s | 7.33 / 4.73 / 8.73 / 5.93 / 6.97 | 0.183 / 0.285 | 22.5 / 22.8 | 0.43, 1.2 | 0.111 | 0.85 |
| 45 s | 7.32 / 4.86 / 9.20 / 6.28 / 6.84 | 0.197 / 0.278 | 37.6 / 18.8 | 0.40, 1.2 | 0.184 | 0.85 |
| 60 s | 7.73 / 5.16 / 9.30 / 6.21 / 7.56 | 0.219 / 0.288 | 49.9 / 17.3 | 0.40, 1.1 | 0.240 | 0.85 |
| 120 s | 7.87 / 5.03 / 9.96 / 6.31 / 7.59 | 0.278 / 0.316 | 69.0 / 9.2 | 0.38, 1.1 | 0.406 | 0.84 |
| 300 s | 8.12 / 5.40 / 10.25 / 6.60 / 8.65 | 0.351 / 0.365 | 67.3 / 4.3 | 0.35, 1.1 | 0.612 | 0.84 |
| none | 8.50 / 5.69 / 10.70 / 6.36 / 8.40 | 0.394 / 0.395 | 68.5 / 1.6 | 0.34, 1.2 | 0.744 | 0.83 |
- Reading the tables: the bound on T barely moves the swing (±10% to unbounded give 7.3 to 7.5 cards in the steady habit), since the swing comes from the reviews set aside; setting aside the reviews due today (A) swings by 18.8 cards a day in the steady habit, on a mean of 17.0 new cards a day. The daily load alone (E) swings least but takes new cards on a return from rest as if nothing were due (return 0.99), which drops the owner's rule that reviews piled up while resting lower new cards. G over 7 days keeps the swing within 2.5 cards of E's in every habit while a two-day rest still lowers the return day's new cards to 43% of the days before, recovering in about a day; each longer spread lowers the swing by under a card while new cards fall less on return (0.57 at 10 days, 0.71 at 14).
- Alternatives the issue names, measured above: the plain mean of the window and the mean or median of the last 7 study days. The plain mean swings least but leaves the most time unused (0.78) and follows a shrinking habit in 25.9 study days against the half-life of 7's 23.8; the last-7 estimators follow it fastest (11.3 and 12.5 study days) and swing more (8.73 and 8.10 against 7.54). A half-life of 7 is also about the longest with which a recent week outweighs the 23 study days before it in a window of 30, the recency the issue asks for, for the study time and the pace alike; the pace's half-life moves no measure by more than its noise between 7 and 14.
- The other constants, from the tables: ±10% has the lowest swing in four habits of five and the best fit in the steady and irregular ones, and 30% or more is the same as no bound; a cold start of 1 or 3 study days swings less but anchors T on the first short days and uses 74 to 80% of the time available, while 7 or 10 add at most 0.03 of it and swing more; a window of 60 study days moves the swing by under 0.2 of a card and the fit by under 0.01, follows a shrinking habit 3 study days slower and reads twice as much, and 14 swings and fits worse; a cap of 30 s halves the cap error of 60 s (0.111 against 0.240) and follows a shrinking habit in 22.5 study days against 49.9. 20 s has the least error in the model, but cuts the slowest 5% of production's first answers (p95 20.3 s); 30 s sits above that and above the model's 98th percentile of a first answer's own time (29 s), so it cuts mostly time away.

## Decision

- **Foreground time.** An answer's duration counts only the time its card was on screen with the app resumed on the phone (`AppLifecycleState.resumed`) or the page visible on the web (`visibilitychange`). An answer given while away counts up to leaving, and the next card's clock starts on return. Nothing else pauses it: no window focus, idle timer or inactivity detection.
- **Study days.** A study day runs from 04:00 to 04:00 ([ADR 0033](0033-count-cards-left-per-study-day-from-04-00-and-continue-as-unrecorded-practice.md)) and is one with at least one live answer. The estimates read the latest `studyDayWindow` (30) study days before today, whatever rest lies between them, and nothing of today, so a figure does not move as the user studies. Each answer counts up to `answerCapMs` (30 s); the stored row keeps its whole duration.
- **Study time T.** Each study day's total, its answers' capped durations, is weighted 0.5^(age / `studyTimeHalfLife`) with the age in study days (7); each day's estimate is the weighted mean of the window's days up to it, held within `studyTimeStepPercent` (10%) of the previous day's, and T is the last, in whole milliseconds.
- **Pace.** For a review (an answer that is not its card's first live answer) and for a card's first answer apart: the capped time of that kind's answers over their number, each day weighted 0.5^(age / `paceHalfLife`) (7), in whole milliseconds; a kind with fewer than `paceMinimum` (20) answers in the window takes `defaultAnswerMs` (10 s).
- **New cards.** While the window holds fewer than `coldStartStudyDays` (5) study days, a day takes `coldStartNewCards` (20). Otherwise it takes max(0, floor((T − round(R × review pace)) / first-answer pace)), where R, the reviews set aside, is the daily load L plus max(0, D − L) / `reviewSpreadDays` (7), with D the reviews due in the day. D and L stand as the day stood when it started: D is the cards due before it ends that were not answered in it, plus those answered in it that had an answer before; L is `dailyLoad` over the states of the first, plus, for each of the second, one over the days between its last answer before the day and its first in it. As before, the day's new cards less those first answered in it, across every deck, never below zero, are what it has left; a backlog still pauses them.
- **Minutes.** The count's minutes are its reviews at the review pace plus its new cards at the first-answer pace, rounded up; a forecast day's reviews take the review pace.
- **Both clients.** The constants above are defined once per client, in `app/lib/study/src/queue.dart` and `web/src/features/study/queue.ts`, which `web/src/features/study/__tests__/rules.test.ts` compares. The phone reads the window from its database, walking back one study day at a time through `reviews_live_reviewed_at`; the web reads it in one request through the server's `study_days_before`, which groups the same days in the browser's zone with the same cap.
- **Supersessions.** This replaces ADR 0033's fixed 20 new cards a day (`newCardLimit`), which becomes the cold start, and ADR 0027's pace, the median of the latest 200 reviews.

## Consequences

- A user who studies longer and faster is offered more new cards and one who studies less fewer, following a large change of habit in about 23 study days (follow 22.5 and 22.8 above).
- What the user does not study is not learned: a queue finished early leaves T at the time that queue took, so the figure grows only as the pace improves, the daily load falls, or a day runs out of time before its queue. The simulation's users used 73 to 85% of the time they had.
- Re-shows of a "Don't know" are reviews in the pace and take time T counts, but the reviews set aside are cards, not answers, so a user who misses many cards runs out of time before the day's cards more often (in the simulation, 26 to 43% of study days).
- The cap undercounts a truly slow answer past 30 s and still counts up to 30 s of time away on a visible page. The bound is revisited once production holds foreground-timed answers from at least 20 users: the same two queries, read by the PM, with the cap moved toward the 99th percentile of first answers if it lies above 30 s, and the simulation re-run.
- Each count reads up to 31 index probes and the window's answers on the phone, and one more request on the web; the deck rows read once per row.
- Sync delivering another device's answers during the day can change the day's figure, since they join today's or the window's answers.

## Signs the decision was wrong

- Users report the day's new cards jumping between days, or rising during a day while they study.
- Users who want more new cards report the figure stuck though they have time, the censoring above.
- Users who rest for a few days report a return day with no new cards, or one with as many as before.
- Production's foreground-timed first answers put more than 2% above 30 s, so the cap cuts real answers.
- The web's and the phone's counts differ for the same user at the same moment, beyond the zone the cookie names.
