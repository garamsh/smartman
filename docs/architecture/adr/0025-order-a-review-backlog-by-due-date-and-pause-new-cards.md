# ADR 0025: Order a review backlog earliest due first in shuffled runs of ten, and pause new cards while more than three days of reviews are due

> Status: accepted
> Date: 2026-10-15

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #53 asks that a session with reviews piled up spend the user's time where it saves the most memory, that new cards pause until the backlog clears, and that the order still cannot be memorized. The PM decided there:
  - the order is chosen by a seeded, deterministic simulation in this repository that drives `engine/` itself, comparing at least the current shuffle, ascending and descending retrievability, and due date ascending;
  - [ADR 0009](0009-multi-deck-session-and-random-queue-order.md)'s anti-memorization stays: the order is applied in buckets of consecutive cards, each shuffled with the session's `Random`, with the bucket size chosen from the simulation;
  - new cards pause during a backlog, which a threshold decides, proposed from the simulation; the deck screens say so in one plain sentence;
  - the rule lives once in each client's queue, `app/lib/study/src/queue.dart` and `web/src/features/study/queue.ts`, so the counts follow it.
- ADR 0009 shuffles every due card and up to 20 new ones together, so a session the user leaves early studies a random part of a backlog. It named that as a consequence, and "users with a large backlog leave sessions early and find their most overdue cards keep going unstudied" as a sign it was wrong.
- The sources issue #53 cites disagree. As the issue reports them, and not read for this ADR: Anki's manual (docs.ankiweb.net/deck-options.html) recommends relative overdueness for a large backlog, which under FSRS is ascending retrievability, and stopping new cards until it is caught up; the FSRS author's sort-order simulations on the Anki forums ("Improving sort orders", "Ordering Request: Reverse Relative Overdueness"), not peer-reviewed, favour descending retrievability under a daily cap and rank due date ascending among the worst.
- **The simulation**, `engine/examples/backlog.rs`, run from `engine/` with `cargo run --locked --release --example backlog`, seeds 1 to 20, SplitMix64:
  - a user studies every day for 120 days at 20 new cards a day, which leaves 2400 cards asking for about 169 reviews a day, then skips 7 or 30 days, then studies daily for a horizon with a budget of reviews a day, standing in for a user who stops early, since the app sets no limit;
  - a reviewed card is recalled with the probability the engine's `MemoryState::retrievability` gives, a new card with 0.5; "Don't know" re-shows the card ten minutes later, recalled, for one more review of the budget; every review draws a fuzz factor;
  - the orders by retrievability sort by the engine's own retrievability, not by a key standing in for it;
  - metrics: the mean, over the horizon's days, of the expected retained cards (the sum of retrievability over every reviewed card) at each session's start; the same at the horizon's end; both again over the pre-skip cards alone, the cards reviewed before the skip, which are the backlog's own; the reviews spent; the new cards introduced. Each retained figure is a mean over the 20 seeds ± its standard error.
  - the sum over every reviewed card grows with each new card introduced, so it ranks orders but cannot judge pausing new cards, which trades new learning for the backlog's retention. The pause is judged on the pre-skip cards.
- **Order.** Every session of the horizon in backlog, its due cards in the strict order, no new card; today's queue, with its new cards, for comparison. The first four scenarios are those the issue names; the last eight check other budgets and horizons:

| Skip | Budget | Horizon | Order | Mean retained over the horizon | Retained at end | Reviews | New cards |
|---|---|---|---|---|---|---|---|
| 7 | 50 | 60 | today: shuffle with new cards | 2225.8 ± 1.2 | 2270.4 ± 1.9 | 3000 | 71 |
| 7 | 50 | 60 | shuffle (today) | 2205.5 ± 0.9 | 2227.9 ± 1.0 | 3000 | 0 |
| 7 | 50 | 60 | retrievability ascending | 2202.3 ± 0.9 | 2210.7 ± 1.4 | 3000 | 0 |
| 7 | 50 | 60 | retrievability descending | 2180.9 ± 1.0 | 2188.9 ± 1.7 | 3000 | 0 |
| 7 | 50 | 60 | due date ascending | 2215.2 ± 0.9 | 2239.7 ± 1.0 | 3000 | 0 |
| 7 | 200 | 60 | today: shuffle with new cards | 2759.7 ± 1.8 | 3322.2 ± 2.3 | 11197 | 1116 |
| 7 | 200 | 60 | shuffle (today) | 2273.2 ± 0.1 | 2270.9 ± 0.4 | 5170 | 0 |
| 7 | 200 | 60 | retrievability ascending | 2273.7 ± 0.1 | 2271.4 ± 0.3 | 5152 | 0 |
| 7 | 200 | 60 | retrievability descending | 2272.3 ± 0.2 | 2271.6 ± 0.3 | 5139 | 0 |
| 7 | 200 | 60 | due date ascending | 2273.5 ± 0.2 | 2270.5 ± 0.3 | 5146 | 0 |
| 30 | 50 | 60 | today: shuffle with new cards | 2168.7 ± 1.0 | 2248.0 ± 1.9 | 3000 | 58 |
| 30 | 50 | 60 | shuffle (today) | 2156.7 ± 1.0 | 2216.6 ± 1.8 | 3000 | 0 |
| 30 | 50 | 60 | retrievability ascending | 2154.9 ± 1.0 | 2191.9 ± 1.5 | 3000 | 0 |
| 30 | 50 | 60 | retrievability descending | 2124.0 ± 1.1 | 2166.9 ± 1.6 | 3000 | 0 |
| 30 | 50 | 60 | due date ascending | 2170.1 ± 0.9 | 2232.0 ± 1.0 | 3000 | 0 |
| 30 | 200 | 60 | today: shuffle with new cards | 2667.6 ± 1.5 | 3224.3 ± 1.7 | 10954 | 1021 |
| 30 | 200 | 60 | shuffle (today) | 2262.9 ± 0.2 | 2260.7 ± 0.3 | 5465 | 0 |
| 30 | 200 | 60 | retrievability ascending | 2266.6 ± 0.2 | 2261.3 ± 0.2 | 5515 | 0 |
| 30 | 200 | 60 | retrievability descending | 2258.7 ± 0.2 | 2259.9 ± 0.3 | 5503 | 0 |
| 30 | 200 | 60 | due date ascending | 2266.0 ± 0.2 | 2260.2 ± 0.3 | 5467 | 0 |
| 7 | 25 | 60 | today: shuffle with new cards | 2150.4 ± 0.7 | 2129.7 ± 1.3 | 1500 | 26 |
| 7 | 25 | 60 | shuffle (today) | 2143.1 ± 0.8 | 2117.2 ± 1.3 | 1500 | 0 |
| 7 | 25 | 60 | retrievability ascending | 2148.7 ± 0.8 | 2118.5 ± 1.1 | 1500 | 0 |
| 7 | 25 | 60 | retrievability descending | 2124.4 ± 0.8 | 2083.5 ± 1.2 | 1500 | 0 |
| 7 | 25 | 60 | due date ascending | 2151.9 ± 0.8 | 2131.0 ± 1.0 | 1500 | 0 |
| 30 | 25 | 60 | today: shuffle with new cards | 2085.4 ± 0.9 | 2094.5 ± 1.4 | 1500 | 20 |
| 30 | 25 | 60 | shuffle (today) | 2080.3 ± 0.9 | 2085.3 ± 1.3 | 1500 | 0 |
| 30 | 25 | 60 | retrievability ascending | 2088.8 ± 1.2 | 2085.1 ± 1.6 | 1500 | 0 |
| 30 | 25 | 60 | retrievability descending | 2059.8 ± 0.9 | 2049.0 ± 1.4 | 1500 | 0 |
| 30 | 25 | 60 | due date ascending | 2094.4 ± 0.8 | 2098.8 ± 1.0 | 1500 | 0 |
| 7 | 100 | 60 | today: shuffle with new cards | 2389.7 ± 1.9 | 2593.5 ± 3.6 | 6000 | 357 |
| 7 | 100 | 60 | shuffle (today) | 2264.6 ± 0.3 | 2268.1 ± 0.2 | 4876 | 0 |
| 7 | 100 | 60 | retrievability ascending | 2265.6 ± 0.3 | 2265.4 ± 0.3 | 4830 | 0 |
| 7 | 100 | 60 | retrievability descending | 2260.4 ± 0.4 | 2269.8 ± 0.3 | 4978 | 0 |
| 7 | 100 | 60 | due date ascending | 2266.4 ± 0.3 | 2265.2 ± 0.3 | 4814 | 0 |
| 30 | 100 | 60 | today: shuffle with new cards | 2332.4 ± 1.8 | 2557.7 ± 3.4 | 6000 | 323 |
| 30 | 100 | 60 | shuffle (today) | 2236.8 ± 0.4 | 2264.3 ± 0.2 | 5060 | 0 |
| 30 | 100 | 60 | retrievability ascending | 2241.5 ± 0.6 | 2270.2 ± 0.3 | 5096 | 0 |
| 30 | 100 | 60 | retrievability descending | 2223.5 ± 0.5 | 2260.2 ± 0.2 | 5082 | 0 |
| 30 | 100 | 60 | due date ascending | 2243.9 ± 0.4 | 2264.5 ± 0.3 | 5034 | 0 |
| 7 | 50 | 30 | today: shuffle with new cards | 2208.1 ± 1.0 | 2221.9 ± 1.5 | 1500 | 34 |
| 7 | 50 | 30 | shuffle (today) | 2197.6 ± 0.8 | 2201.5 ± 1.2 | 1500 | 0 |
| 7 | 50 | 30 | retrievability ascending | 2202.4 ± 0.8 | 2199.1 ± 0.9 | 1500 | 0 |
| 7 | 50 | 30 | retrievability descending | 2182.0 ± 0.8 | 2173.2 ± 1.2 | 1500 | 0 |
| 7 | 50 | 30 | due date ascending | 2205.4 ± 0.8 | 2212.4 ± 1.0 | 1500 | 0 |
| 30 | 50 | 30 | today: shuffle with new cards | 2128.0 ± 0.6 | 2170.4 ± 1.2 | 1500 | 22 |
| 30 | 50 | 30 | shuffle (today) | 2123.2 ± 0.8 | 2159.5 ± 1.0 | 1500 | 0 |
| 30 | 50 | 30 | retrievability ascending | 2135.5 ± 1.0 | 2161.4 ± 1.1 | 1500 | 0 |
| 30 | 50 | 30 | retrievability descending | 2101.4 ± 0.9 | 2125.2 ± 1.4 | 1500 | 0 |
| 30 | 50 | 30 | due date ascending | 2137.6 ± 0.8 | 2169.7 ± 1.0 | 1500 | 0 |
| 7 | 100 | 120 | today: shuffle with new cards | 2591.6 ± 2.7 | 2990.6 ± 4.9 | 12000 | 787 |
| 7 | 100 | 120 | shuffle (today) | 2264.0 ± 0.2 | 2262.8 ± 0.3 | 7912 | 0 |
| 7 | 100 | 120 | retrievability ascending | 2265.5 ± 0.1 | 2263.2 ± 0.3 | 7934 | 0 |
| 7 | 100 | 120 | retrievability descending | 2261.5 ± 0.2 | 2262.8 ± 0.2 | 8029 | 0 |
| 7 | 100 | 120 | due date ascending | 2265.1 ± 0.2 | 2264.0 ± 0.3 | 7922 | 0 |
| 30 | 100 | 120 | today: shuffle with new cards | 2543.4 ± 3.1 | 2948.6 ± 5.9 | 12000 | 733 |
| 30 | 100 | 120 | shuffle (today) | 2251.2 ± 0.2 | 2274.3 ± 0.4 | 8380 | 0 |
| 30 | 100 | 120 | retrievability ascending | 2256.2 ± 0.3 | 2277.4 ± 0.4 | 8333 | 0 |
| 30 | 100 | 120 | retrievability descending | 2243.1 ± 0.3 | 2273.5 ± 0.4 | 8470 | 0 |
| 30 | 100 | 120 | due date ascending | 2255.2 ± 0.2 | 2273.7 ± 0.4 | 8321 | 0 |

- Descending retrievability, the forum's result, has the lowest mean over the horizon in every scenario here. Under a budget well below the daily load (25 and 50) it keeps reviewing the cards that just fell due, which leave the queue with longer intervals, while the oldest part of the backlog is never reached.
- Due date ascending has the highest mean in all six scenarios with a budget of 25 or 50, by 2 to 13 cards over the next best. With 100 or 200, where the backlog clears and the orders differ by little, it is the highest in two of six and within 1.0 card (0.05%) of the highest, ascending retrievability, in the other four. Ascending retrievability ranks second or third under the tight budgets.
- **Bucket size**, due date ascending, every session in backlog. Every size up to 100 is within 2.4 cards (0.1%) of the strict order on both metrics:

| Skip | Budget | Bucket | Mean retained over the horizon | Retained at end |
|---|---|---|---|---|
| 7 | 50 | bucket 1 | 2215.2 ± 0.9 | 2239.7 ± 1.0 |
| 7 | 50 | bucket 5 | 2214.4 ± 0.8 | 2238.6 ± 1.2 |
| 7 | 50 | bucket 10 | 2212.8 ± 0.8 | 2237.4 ± 1.0 |
| 7 | 50 | bucket 20 | 2213.6 ± 1.1 | 2238.3 ± 1.3 |
| 7 | 50 | bucket 50 | 2214.0 ± 0.6 | 2239.2 ± 0.9 |
| 7 | 50 | bucket 100 | 2214.0 ± 0.8 | 2239.0 ± 1.0 |
| 7 | 200 | bucket 1 | 2273.5 ± 0.2 | 2270.5 ± 0.3 |
| 7 | 200 | bucket 5 | 2273.5 ± 0.1 | 2270.0 ± 0.3 |
| 7 | 200 | bucket 10 | 2273.4 ± 0.1 | 2270.2 ± 0.4 |
| 7 | 200 | bucket 20 | 2273.5 ± 0.1 | 2270.5 ± 0.3 |
| 7 | 200 | bucket 50 | 2273.5 ± 0.2 | 2270.1 ± 0.3 |
| 7 | 200 | bucket 100 | 2273.6 ± 0.1 | 2270.2 ± 0.3 |
| 30 | 50 | bucket 1 | 2170.1 ± 0.9 | 2232.0 ± 1.0 |
| 30 | 50 | bucket 5 | 2169.2 ± 0.8 | 2231.8 ± 1.3 |
| 30 | 50 | bucket 10 | 2169.6 ± 1.3 | 2232.2 ± 1.3 |
| 30 | 50 | bucket 20 | 2169.9 ± 0.8 | 2232.0 ± 1.1 |
| 30 | 50 | bucket 50 | 2168.5 ± 0.6 | 2229.4 ± 1.0 |
| 30 | 50 | bucket 100 | 2169.7 ± 1.0 | 2231.8 ± 0.9 |
| 30 | 200 | bucket 1 | 2266.0 ± 0.2 | 2260.2 ± 0.3 |
| 30 | 200 | bucket 5 | 2265.9 ± 0.2 | 2260.4 ± 0.2 |
| 30 | 200 | bucket 10 | 2266.0 ± 0.2 | 2260.3 ± 0.3 |
| 30 | 200 | bucket 20 | 2265.8 ± 0.2 | 2260.4 ± 0.2 |
| 30 | 200 | bucket 50 | 2266.0 ± 0.2 | 2260.5 ± 0.2 |
| 30 | 200 | bucket 100 | 2265.9 ± 0.2 | 2260.5 ± 0.2 |

- **Threshold.** The due count is compared with the daily load: the sum, over every reviewed card, of one over its interval in days, at least one. Their ratio is how many days of reviews are due. A skip of a week reads as about four days, since a card with an interval under the skip is due once however long the skip:

| Skip | Due | Daily load | Days of reviews due |
|---|---|---|---|
| 1 | 267 | 169.0 | 1.58 |
| 2 | 347 | 169.0 | 2.05 |
| 3 | 421 | 169.0 | 2.49 |
| 7 | 680 | 169.0 | 4.02 |
| 14 | 988 | 169.0 | 5.85 |
| 30 | 1400 | 169.0 | 8.28 |

- How often each threshold calls a backlog for a user who studies with no budget but skips days each week, over the 120 days:

| Threshold | Skips no day | Skips 1 day a week | Skips 2 days a week |
|---|---|---|---|
| over 1 days due | 0.0 | 17.1 | 17.0 |
| over 1.5 days due | 0.0 | 7.5 | 15.4 |
| over 2 days due | 0.0 | 0.0 | 1.6 |
| over 3 days due | 0.0 | 0.0 | 0.0 |
| over 5 days due | 0.0 | 0.0 | 0.0 |

- The threshold, due date ascending in runs of ten; out of backlog, today's queue:

| Skip | Budget | Backlog | Mean retained over the horizon | Retained at end | Retained at end, cards from before the skip | New cards | Backlog days |
|---|---|---|---|---|---|---|---|
| 7 | 50 | never in backlog (today) | 2225.8 ± 1.2 | 2270.4 ± 1.9 | 2212.8 | 71 | 0.0 |
| 7 | 50 | over 1 days due | 2212.8 ± 0.8 | 2237.4 ± 1.0 | 2237.4 | 0 | 60.0 |
| 7 | 50 | over 1.5 days due | 2212.8 ± 0.8 | 2237.4 ± 1.0 | 2237.4 | 0 | 60.0 |
| 7 | 50 | over 2 days due | 2212.8 ± 0.8 | 2237.4 ± 1.0 | 2237.4 | 0 | 60.0 |
| 7 | 50 | over 3 days due | 2212.8 ± 0.8 | 2239.0 ± 1.2 | 2233.3 | 7 | 56.5 |
| 7 | 50 | over 5 days due | 2225.8 ± 1.2 | 2270.4 ± 1.9 | 2212.8 | 71 | 0.0 |
| 7 | 50 | always in backlog | 2212.8 ± 0.8 | 2237.4 ± 1.0 | 2237.4 | 0 | 60.0 |
| 7 | 200 | never in backlog (today) | 2759.7 ± 1.8 | 3322.2 ± 2.3 | 2270.5 | 1116 | 0.0 |
| 7 | 200 | over 1 days due | 2720.3 ± 1.3 | 3279.7 ± 2.2 | 2270.3 | 1072 | 6.1 |
| 7 | 200 | over 1.5 days due | 2734.7 ± 1.0 | 3294.7 ± 1.3 | 2270.0 | 1088 | 5.1 |
| 7 | 200 | over 2 days due | 2743.6 ± 1.2 | 3302.2 ± 2.2 | 2269.8 | 1096 | 4.0 |
| 7 | 200 | over 3 days due | 2748.8 ± 1.2 | 3309.3 ± 1.9 | 2269.7 | 1104 | 3.0 |
| 7 | 200 | over 5 days due | 2759.7 ± 1.8 | 3322.2 ± 2.3 | 2270.5 | 1116 | 0.0 |
| 7 | 200 | always in backlog | 2273.4 ± 0.1 | 2270.2 ± 0.4 | 2270.2 | 0 | 60.0 |
| 30 | 50 | never in backlog (today) | 2168.7 ± 1.0 | 2248.0 ± 1.9 | 2202.1 | 58 | 0.0 |
| 30 | 50 | over 1 days due | 2169.6 ± 1.3 | 2232.2 ± 1.3 | 2232.2 | 0 | 60.0 |
| 30 | 50 | over 1.5 days due | 2169.6 ± 1.3 | 2232.2 ± 1.3 | 2232.2 | 0 | 60.0 |
| 30 | 50 | over 2 days due | 2169.6 ± 1.3 | 2232.2 ± 1.3 | 2232.2 | 0 | 60.0 |
| 30 | 50 | over 3 days due | 2169.7 ± 1.3 | 2234.2 ± 1.7 | 2217.8 | 20 | 47.0 |
| 30 | 50 | over 5 days due | 2171.1 ± 1.3 | 2240.3 ± 2.2 | 2208.3 | 40 | 26.6 |
| 30 | 50 | always in backlog | 2169.6 ± 1.3 | 2232.2 ± 1.3 | 2232.2 | 0 | 60.0 |
| 30 | 200 | never in backlog (today) | 2667.6 ± 1.5 | 3224.3 ± 1.7 | 2260.8 | 1021 | 0.0 |
| 30 | 200 | over 1 days due | 2633.7 ± 1.2 | 3182.4 ± 1.1 | 2260.6 | 977 | 11.1 |
| 30 | 200 | over 1.5 days due | 2645.2 ± 1.2 | 3195.7 ± 1.3 | 2260.5 | 991 | 10.2 |
| 30 | 200 | over 2 days due | 2653.7 ± 1.0 | 3205.8 ± 1.3 | 2260.4 | 1003 | 9.0 |
| 30 | 200 | over 3 days due | 2659.1 ± 1.2 | 3212.5 ± 1.4 | 2260.5 | 1009 | 7.2 |
| 30 | 200 | over 5 days due | 2659.3 ± 1.4 | 3212.9 ± 1.4 | 2260.6 | 1009 | 5.0 |
| 30 | 200 | always in backlog | 2266.0 ± 0.2 | 2260.3 ± 0.3 | 2260.3 | 0 | 60.0 |

- **New cards.** The same seeds and budgets, each run against three queues: due date ascending in runs of ten with new cards paused while in backlog (over three days due), the same with today's 20 new cards a day, each at a random place among the due cards, and today's queue. "Paused leads" is the paused queue's retained pre-skip cards less the other queue's, seed by seed, ± the standard error of that paired difference:

| Skip | Budget | Policy | Mean retained over the horizon, pre-skip cards | Retained at end, pre-skip cards | Paused leads, pre-skip, over the horizon | Paused leads, pre-skip, at end | Mean retained over the horizon, every card | Retained at end, every card | New cards |
|---|---|---|---|---|---|---|---|---|---|
| 7 | 50 | due date runs, new cards paused | 2212.6 ± 0.8 | 2233.3 ± 1.1 | — | — | 2212.8 ± 0.8 | 2239.0 ± 1.2 | 7 |
| 7 | 50 | due date runs, new cards as today | 2209.4 ± 1.1 | 2224.0 ± 1.2 | 3.2 ± 1.0 | 9.3 ± 1.2 | 2234.1 ± 1.4 | 2280.5 ± 2.0 | 71 |
| 7 | 50 | today: shuffle with new cards | 2199.2 ± 0.9 | 2212.8 ± 1.1 | 13.4 ± 0.9 | 20.5 ± 1.3 | 2225.8 ± 1.2 | 2270.4 ± 1.9 | 71 |
| 7 | 200 | due date runs, new cards paused | 2273.4 ± 0.1 | 2269.7 ± 0.3 | — | — | 2748.8 ± 1.2 | 3309.3 ± 1.9 | 1104 |
| 7 | 200 | due date runs, new cards as today | 2273.3 ± 0.1 | 2269.6 ± 0.4 | 0.1 ± 0.1 | 0.1 ± 0.4 | 2758.1 ± 1.6 | 3317.6 ± 2.7 | 1112 |
| 7 | 200 | today: shuffle with new cards | 2272.7 ± 0.2 | 2270.5 ± 0.3 | 0.7 ± 0.1 | -0.8 ± 0.2 | 2759.7 ± 1.8 | 3322.2 ± 2.3 | 1116 |
| 30 | 50 | due date runs, new cards paused | 2167.9 ± 1.3 | 2217.8 ± 1.8 | — | — | 2169.7 ± 1.3 | 2234.2 ± 1.7 | 20 |
| 30 | 50 | due date runs, new cards as today | 2164.7 ± 0.8 | 2210.0 ± 1.3 | 3.2 ± 1.2 | 7.8 ± 1.8 | 2180.0 ± 0.9 | 2252.9 ± 1.6 | 55 |
| 30 | 50 | today: shuffle with new cards | 2150.4 ± 0.9 | 2202.1 ± 1.5 | 17.5 ± 1.3 | 15.7 ± 2.0 | 2168.7 ± 1.0 | 2248.0 ± 1.9 | 58 |
| 30 | 200 | due date runs, new cards paused | 2265.6 ± 0.2 | 2260.5 ± 0.2 | — | — | 2659.1 ± 1.2 | 3212.5 ± 1.4 | 1009 |
| 30 | 200 | due date runs, new cards as today | 2265.2 ± 0.2 | 2260.5 ± 0.3 | 0.4 ± 0.2 | -0.0 ± 0.3 | 2672.0 ± 1.2 | 3226.8 ± 1.5 | 1024 |
| 30 | 200 | today: shuffle with new cards | 2261.7 ± 0.3 | 2260.8 ± 0.3 | 3.9 ± 0.2 | -0.3 ± 0.4 | 2667.6 ± 1.5 | 3224.3 ± 1.7 | 1021 |
| 7 | 25 | due date runs, new cards paused | 2151.5 ± 0.8 | 2130.8 ± 1.1 | — | — | 2151.5 ± 0.8 | 2130.8 ± 1.1 | 0 |
| 7 | 25 | due date runs, new cards as today | 2149.1 ± 0.9 | 2126.6 ± 1.4 | 2.4 ± 0.7 | 4.2 ± 1.5 | 2156.6 ± 1.0 | 2140.5 ± 1.6 | 22 |
| 7 | 25 | today: shuffle with new cards | 2140.7 ± 0.7 | 2111.5 ± 1.0 | 10.8 ± 0.7 | 19.3 ± 1.5 | 2150.4 ± 0.7 | 2129.7 ± 1.3 | 26 |
| 30 | 25 | due date runs, new cards paused | 2093.3 ± 1.2 | 2097.1 ± 1.6 | — | — | 2093.3 ± 1.2 | 2097.1 ± 1.6 | 0 |
| 30 | 25 | due date runs, new cards as today | 2091.2 ± 0.9 | 2093.5 ± 1.0 | 2.1 ± 0.8 | 3.6 ± 1.3 | 2096.8 ± 1.1 | 2104.4 ± 1.4 | 18 |
| 30 | 25 | today: shuffle with new cards | 2078.7 ± 0.8 | 2081.1 ± 1.3 | 14.6 ± 1.2 | 16.0 ± 2.2 | 2085.4 ± 0.9 | 2094.5 ± 1.4 | 20 |
| 7 | 100 | due date runs, new cards paused | 2259.9 ± 0.4 | 2261.2 ± 0.4 | — | — | 2382.9 ± 2.4 | 2594.0 ± 4.3 | 359 |
| 7 | 100 | due date runs, new cards as today | 2258.3 ± 0.4 | 2260.5 ± 0.5 | 1.6 ± 0.4 | 0.6 ± 0.5 | 2387.2 ± 2.3 | 2591.4 ± 4.5 | 358 |
| 7 | 100 | today: shuffle with new cards | 2257.0 ± 0.4 | 2262.8 ± 0.4 | 2.8 ± 0.4 | -1.6 ± 0.4 | 2389.7 ± 1.9 | 2593.5 ± 3.6 | 357 |
| 30 | 100 | due date runs, new cards paused | 2238.6 ± 0.5 | 2260.8 ± 0.3 | — | — | 2327.8 ± 1.7 | 2552.6 ± 4.1 | 315 |
| 30 | 100 | due date runs, new cards as today | 2236.4 ± 0.5 | 2260.3 ± 0.3 | 2.3 ± 0.5 | 0.5 ± 0.4 | 2335.9 ± 1.8 | 2552.4 ± 3.7 | 315 |
| 30 | 100 | today: shuffle with new cards | 2230.2 ± 0.6 | 2259.0 ± 0.4 | 8.5 ± 0.7 | 1.8 ± 0.3 | 2332.4 ± 1.8 | 2557.7 ± 3.4 | 323 |

- Under the tight budgets, 25 and 50, the pause keeps more of the pre-skip cards than today's new cards do with the same order, in every scenario and on both metrics: by 2.1 to 3.2 cards over the horizon and 3.6 to 9.3 at its end, each more than twice its standard error. Under 100 and 200, where the backlog clears in days, the lead is at most 2.3 cards over the horizon and within about one standard error at the end.
- The cost is new learning: under the tight budgets the pause introduces 18 to 64 fewer new cards over the 60 days, and the retained sum over every card is 7 to 42 cards lower at the end.
- Alternatives considered:
  - Descending or ascending retrievability, through a key of whole elapsed days over stability, which orders cards as FSRS-6's retrievability does while one decay holds for every card. The PM chose that key before the simulation ran; due date ascending won it, needs no key, and the key and its order-equivalence tests against the engine were dropped.
  - A backlog measured against the reviews done in recent days. It needs each client to read the review history, and a rule for a user with little history, whose first cards fall due against almost none. The daily load reads only the card states both clients already read.
  - A threshold of 2: it pauses new cards for a user who skips two days a week on a few days of the 120. A threshold of 5 misses a week's skip.

## Decision

- **Backlog.** A selection of decks is in backlog when more than `backlogDays` (3) days of reviews are due: its due cards outnumber three times the daily load of its reviewed cards.
- **Membership.** In backlog the session takes every due card and no new card: the pause keeps more of the backlog's own cards under a tight budget, beyond the standard error, at the cost of new cards learned. Otherwise it takes every due card and up to 20 new ones, as ADR 0009 does.
- **Order.** In backlog the due cards are sorted earliest due first, equal due times in the order read, and each run of `backlogBucketSize` (10) consecutive cards is shuffled in its place with the session's `Random`. Otherwise the queue is shuffled as a whole, as ADR 0009 does, with the same draws. This supersedes ADR 0009's order for a backlog.
- **Counts and sentence.** The counts the deck screens show come from the same selection, so a backlog shows no new card, and the deck list's header and the deck's screen add one sentence, "밀린 복습을 마칠 때까지 새 카드는 쉬어요.".
- **Where.** `queue.dart` and `queue.ts` hold the rule, with the same constants; a change to one changes both.
- **Ten.** Bucketing costs nothing measurable at any size up to 100. Ten keeps the first cards of a session a user leaves after a few cards among the ten most overdue, while no card's place within its run can be learned.

## Consequences

- A user back from a week or more away studies the oldest part of the backlog first, a run of ten at a time, and sees no new card until at most three days of reviews are due; the deck screens say why.
- During a backlog the user learns no new card. Under a tight budget the simulation keeps 2 to 9 more of the backlog's own cards that way, and learns 18 to 64 fewer new cards over 60 days.
- A user who studies daily, or misses a day or two a week, sees today's queue: no backlog was called on any such day in the simulation.
- The order is no longer uniformly random during a backlog: which run a card falls in follows its due date. Within a run it is random, and runs change as due dates do.
- The simulation is committed with its seeds, so the evidence for the constants can be rerun, or extended to a new candidate, against the engine as it then is.
- The model is a simulation of a simulated user whose memory follows FSRS-6 exactly; where real users forget otherwise, the ranking may differ.

## Signs the decision was wrong

- Users back from a long break report that new cards stay paused long after they have caught up, or that the sentence shows while the review count is small.
- Users who miss a day or two report new cards pausing in an ordinary week.
- Users with a backlog that never clears, studying a little each day, learn no new card for weeks and stop studying.
- A simulation with the engine's next model, or real review logs, ranks retrievability above due date under a daily cap.
- Users report learning the order of their overdue cards across sessions.
