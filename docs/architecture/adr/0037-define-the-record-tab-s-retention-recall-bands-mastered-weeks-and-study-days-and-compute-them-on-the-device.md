# ADR 0037: Define the 기록 tab's retention, recall bands, mastered weeks and study days, and compute them on the device

> Status: accepted
> Date: 2026-10-17

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #90 records the owner's 기록 tab, approved with the v3 canvas on 2026-10-16: retention per study day against the engine's 90% target, the probability of recall of each reviewed card now in three bands, the mastered cards at the end of each of the last eight weeks, and a twelve-week heatmap of study days with the current and the best streak. Each metric is one function per client over local data.
- The issue fixes the bands (단단함 at least 0.95, 보통 from 0.8 up to 0.95, 곧 잊음 below 0.8), leaves out a card's first answer and practice from the retention, and takes 익힘 and the streak from [ADR 0036](0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md). The engine schedules for `DESIRED_RETENTION = 0.9` (`engine/src/fsrs.rs` at `96e3e765b2fa6b16cabbeaf11273181c9596eccd`).
- The PM's comment on the issue: deleting a card keeps its reviews ([ADR 0034](0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md)), the retention and the streak count every review, and this ADR decides whether the bands and the mastered counts take deleted cards.
- Two definitions the issue leaves open, the PM decided on 2026-10-17 on the worker's question in the dispatch of #90: a re-show after "Don't know" on the same study day is not a scheduled review, and the heatmap counts distinct cards a day.
- On the phone, deleting a card tombstones its `cards` row and leaves its `card_states` row live (`app/lib/deck/src/deck_repository.dart` at the same commit), so the stored states alone cannot tell a deleted card's state from a live one.
- The web reads only what each page shows ([ADR 0030](0030-read-only-what-each-web-page-shows-and-size-the-web-from-the-app-tokens.md)); no web page reads the whole review history or a card's recall, so the web's copies wait for its restructure, issue #91.
- Alternatives considered:
  - Every answer after a card's first, re-shows included, as a scheduled review. A re-show minutes after "Don't know" is answered from short-term memory and would raise the line above what the 90% target predicts.
  - Every stored answer a day in the heatmap. A day with many re-shows would read darker than a day with more cards studied.
  - Calendar weeks from Monday for the mastered weeks. A week then ends at a different study day than today's, and the last point would not be the count the 덱 tab shows now.
  - Deleted cards in the bands and the mastered weeks. A deleted card is never reviewed again, so its falling recall would be a count the user cannot act on, and the latest week would differ from the 덱 tab's "n장 익힘".

## Decision

- **Study day.** Every metric reads days as [ADR 0033](0033-count-cards-left-per-study-day-from-04-00-and-continue-as-unrecorded-practice.md) does: from 04:00 to 04:00 in the device's zone, each boundary at its own instant.
- **Retention.** A review is scheduled when it is a card's first answer of a study day and the card has an answer on an earlier study day. For each study day with one, the retention is its scheduled reviews answered "Know" over its scheduled reviews. A period's value is its days' known reviews over their reviews, and its gap is that share less `targetRetention`, 0.9, the engine's target.
- **Recall bands.** For each card in the decks with a stored state, the engine's probability of recall now: `strong` from `strongRecall` (0.95), `fair` from `fadingRecall` (0.8) below it, `fading` below 0.8, each bound in the upper band; with the counts and their mean, none without a card.
- **Mastered weeks.** `masteredWeeks` (8) weeks of seven study days, the last ending with today's study day. At each week's end, a card in the decks has the state its stored reviews reach before that instant, folded through the engine, and counts when ADR 0036's `progressOf` calls it mastered.
- **Study days.** `heatmapDays` (84) study days ending with today's, each with the calendar date it starts on and the distinct cards answered in it.
- **Streaks.** The current streak is ADR 0033's `streak` over every stored answer; the best is the longest run of consecutive study days with one.
- **Deleted cards.** The retention, the study days and both streaks count every stored answer, whether or not its card is still in a deck. The recall bands and the mastered weeks count only the cards of the decks.
- **Practice** stores nothing, so it is in no metric.
- **Where.** The phone computes each metric in `app/lib/study/src/stats.dart` from its own database and the engine, through one read, `readStats`. The web's copies are issue #91's.

## Consequences

- The retention line is comparable with the 90% target: each point is recall after an interval the engine chose.
- A card first studied in a period adds nothing to its retention until it comes back on a later day.
- The mastered weeks fold every review of the decks' cards through the engine each time they are read, which grows with the history.
- Deleting a deck lowers the bands' counts and every mastered week, past ones included, while the retention, the heatmap and the streaks keep its cards' answers.
- Until issue #91, the web has none of these metrics.

## Signs the decision was wrong

- The retention line sits far from 90% for users the engine schedules well, so the definition measures something else than the engine predicts.
- Users read the mastered weeks dropping after a deletion as having forgotten cards.
- Reading the 기록 tab takes long enough to notice on a device with years of reviews.
- Users expect the heatmap to count every answer, re-shows included, as the completion card's line does.
