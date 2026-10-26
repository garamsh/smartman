# ADR 0096: Show a deck's card count beside its name and its progress as a bar alone, labelled for a screen reader

> Status: accepted
> Date: 2026-10-26

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- [ADR 0036](0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md) gives each 덱 tab row a progress bar and "m장 중 n장 익힘", and the deck page's navy card "n / m 익힘" over the same bar. The bar draws three shares: the mastered cards in ink, the learning ones in ink at 45%, and the new ones as its track.
- Issue #320 found two faults in that wording:
  - an empty deck reads "0장 중 0장 익힘" over an empty bar;
  - a deck whose cards are all learning shows a bar filled end to end over "4장 중 0장 익힘", which reads as an error, since the line counts one share and the bar draws two.
- The same deck was also worded two ways, as a row and as the navy card.
- The PM first decided, on #320, that the line say what the bar shows: "익힘 m · 학습 중 l · 전체 n". The owner replaced that decision on 2026-10-26, on #320: the row does not need a line of figures. The owner then refined it the same day: the row does show how many cards the deck holds, as a short figure beside its name.

## Decision

- **A deck row** on the 덱 tab shows its name with its card count beside it, "n장" ("n cards"), its "오늘 n" while cards are due today, and the progress bar under them. It has no line of counts: "m장 중 n장 익힘" is removed and none replaces it.
- **The deck page's navy card** follows the same rule: its "n / m 익힘" is removed and the bar stays. The deck's card count is already under its name at the top of the page, "카드 n장".
- **The bar** is unchanged in what it draws. A screen reader reads its counts from its label, "익힘 m장, 학습 중 l장, 새 카드 k장", on the row, merged into the row's node, and on the navy card.
- **An empty deck** shows "0장" beside its name and no bar. The deck page already shows no navy card for an empty deck (#315).
- The web's deck list follows in #369.
- **Alternatives considered:**
  - **A line under the bar, "익힘 m · 학습 중 l · 전체 n".** It made the bar's shares legible, but the owner judged it a list of figures the row does not need, on #320.
  - **Keep "m장 중 n장 익힘" and draw only the mastered share.** The line would then be true, but the bar would stop showing a deck being learned, which is most of a new deck's life.
  - **Show an empty deck as "비어 있음".** The owner's first replacement decision on #320 did; the refinement chose "0장", the same figure every other row shows in the same place.

## Consequences

- A row reads at a glance as a name, a size and a bar, with no figure that contradicts the bar.
- A sighted user no longer reads how many cards are mastered or learning, only the bar's shares; a screen reader user hears them.
- Until #369 lands, a deck reads differently on the web's deck list than in the app.

## Signs the decision was wrong

- Users ask how many cards of a deck are mastered, or read the bar's quieter share as mastered.
- Users read "n장" beside the name as the cards due today rather than the deck's size.
