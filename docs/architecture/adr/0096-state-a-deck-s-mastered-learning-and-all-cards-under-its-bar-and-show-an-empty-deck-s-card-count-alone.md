# ADR 0096: State a deck's mastered, learning and all cards under its bar, and show an empty deck's card count alone

> Status: accepted
> Date: 2026-10-26

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- [ADR 0036](0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md) gives each 덱 tab row a progress bar and "m장 중 n장 익힘", and the deck page's navy card "n / m 익힘" over the same bar. The bar draws three shares: the mastered cards in ink, the learning ones in ink at 45%, and the new ones as its track.
- Issue #320 found two faults in that wording:
  - an empty deck reads "0장 중 0장 익힘" over an empty bar;
  - a deck whose cards are all learning shows a bar filled end to end over "4장 중 0장 익힘", which reads as an error, since the line counts one share and the bar draws two.
- The same deck was also worded two ways, as a row and as the navy card.
- The PM decided on 2026-10-26, on #320, that the line says what the bar shows: mastered, learning and all, as in the issue's example "익힘 0 · 학습 중 4 · 전체 4". The bar stays as it is. The exact wording and the empty deck's line were left to the worker, within `design.md` §Principles 2.

## Decision

- **The line.** Under a deck row's bar and over the navy card's bar, one line reads "익힘 m · 학습 중 l · 전체 n" ("m mastered · l learning · n in all"). It uses the terms `study.md` defines: 익힘 at an interval of 21 days or more, 학습 중 when reviewed below it. One string, `deckProgress`, serves both places, so one deck reads the same in both. It replaces "m장 중 n장 익힘" and "n / m 익힘", whose strings are removed.
- **The bar.** Unchanged. On the navy card a screen reader now hears the line and not the bar, as on the row, since the line states the counts the bar draws.
- **An empty deck.** Its row shows "카드 0장", the line it shows while its progress is read, and no bar. The deck page already shows no navy card for an empty deck (#315).
- The web's deck list keeps its wording until a later issue moves it to this one, as the PM's decision on #320 records.
- **Alternatives considered:**
  - **Keep "m장 중 n장 익힘" and draw only the mastered share.** The line would then be true, but the bar would stop showing a deck being learned, which is most of a new deck's life.
  - **Name the new cards too, "새 카드 k".** All, mastered and learning already give it, and a fourth figure on a row of 13 pt crowds it.

## Consequences

- A deck being learned reads as learning on both screens, and an empty deck says only how many cards it holds.
- The line is longer than "m장 중 n장 익힘", by one figure and two separators.
- Until the web follows, a deck reads differently on the web's deck list than in the app.

## Signs the decision was wrong

- The line wraps on a phone's narrow row at the default text size.
- Users read "학습 중" as cards due now, rather than cards seen and not yet mastered.
