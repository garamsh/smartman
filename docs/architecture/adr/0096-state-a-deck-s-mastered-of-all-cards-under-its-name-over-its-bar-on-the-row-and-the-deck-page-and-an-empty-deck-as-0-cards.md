# ADR 0096: State a deck's mastered of all cards under its name over its bar, on the row and the deck page, and an empty deck as 0 cards

> Status: accepted
> Date: 2026-10-26

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- [ADR 0036](0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md) gives each 덱 tab row a progress bar with "m장 중 n장 익힘" under it, and gives the deck page's navy card "n / m 익힘" over the same bar. The bar draws three shares: the mastered cards in ink, the learning ones in ink at 45%, and the new ones as its track.
- Issue #320 found two faults:
  - an empty deck reads "0장 중 0장 익힘" over an empty bar;
  - a deck whose cards are all learning shows a bar filled end to end over "4장 중 0장 익힘". Nothing tells the quieter share from the mastered one.
- The same deck was also worded two ways, on its row and on the navy card.
- The decision on #320 moved several times on 2026-10-26:
  - The PM first chose a line stating all three counts, "익힘 m · 학습 중 l · 전체 n".
  - The owner replaced it with no line of counts at all.
  - The owner then added the deck's size, "n장", beside the name.
  - The owner's last refinement put both figures back as numbers, the cards and the mastered ones, in the existing "n장 중 m장 익힘", on a line under the name. The learning breakdown stays out.

## Decision

- **A deck row** on the 덱 tab shows:
  - its name, with "공개" and "오늘 n" beside it as before;
  - under the name, "n장 중 m장 익힘" ("m of n mastered");
  - under that line, the progress bar.

  The line moves from under the bar to over it.
- **The deck page's navy card** follows the same rule. Its "n / m 익힘" becomes the same "n장 중 m장 익힘", over its bar, so one deck reads the same in both places. One string, `deckMastered`, serves both, and `masteredOf` is removed.
- **The learning count** is not shown as text. A screen reader reads it from the bar's own label, "익힘 m장, 학습 중 l장, 새 카드 k장", which the row now keeps instead of excluding it.
- **An empty deck** shows "0장" under its name and no bar. The same "n장" stands while a deck's progress is read. The deck page already shows no navy card for an empty deck (#365).
- The web's deck list follows in #369.
- **Alternatives considered:**
  - **A line stating all three counts, "익힘 m · 학습 중 l · 전체 n".** It made the bar's quieter share legible, but the owner judged it a list of figures the row does not need, on #320.
  - **No line, with "n장" beside the name.** The owner first chose it, then asked for the mastered count as a number too.
  - **Show an empty deck as "비어 있음".** The owner chose "0장", the same figure the row shows in the same place for every deck while its progress is read.

## Consequences

- A row states the deck's size and how much of it is mastered in figures. The bar shows the rest.
- A deck being learned still reads "4장 중 0장 익힘" over a bar filled in its quieter shade, the second fault #320 found. The owner accepted that, and kept the breakdown out.
- Until #369 lands, a deck reads differently on the web's deck list than in the app.

## Signs the decision was wrong

- Users read a deck being learned, a full quiet bar over "0장 익힘", as an error, as #320 reported.
- Users ask how many of a deck's cards are being learned.
