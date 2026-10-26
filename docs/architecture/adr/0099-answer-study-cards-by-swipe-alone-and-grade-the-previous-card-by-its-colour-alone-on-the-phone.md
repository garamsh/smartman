# ADR 0099: Answer study cards by swipe alone and grade the previous card by its colour alone, on the phone

> Status: accepted
> Date: 2026-10-26

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #375.** The owner decided on 2026-10-26, in the issue and its comments:
  - the phone's study screen is answered by swiping alone, with no "모른다" or "안다" button, and no setting brings them back;
  - "안내 다시 보기" stays at the bottom of the screen, alone and centred under the cards, with its label;
  - the previous card shows no "안다" or "모른다" chip.
- **What this changes.**
  - [ADR 0035](0035-show-the-previous-and-current-study-card-reach-earlier-cards-three-at-a-time-re-decide-the-centred-card-and-grade-each-card-by-its-colour-and-a-chip.md) put two things on the phone that go here: answer buttons under the current card, and a chip on the previous card "so the grade never rests on colour alone".
  - [ADR 0042](0042-show-only-the-previous-and-the-current-study-card-at-one-size-re-decide-the-previous-card-by-a-swipe-and-open-it-on-a-tap.md) sized the two cards over the answer buttons' row.
  - [ADR 0049](0049-study-in-one-flow-that-goes-on-past-today-s-cards-as-recorded-study-with-the-current-card-showing-its-front-alone.md) kept "a swipe, the answer buttons, and on the web the keys" as the ways to answer.
- **Dragging.** `docs/convention/` has no rule on gestures. WCAG 2.2's "Dragging Movements" asks for a single-pointer alternative to a drag. The current card already carries the custom actions "안다" and "모른다", and the previous card "안다로 바꾸기" or "모른다로 바꾸기". The owner chose those screen-reader actions over visible buttons.
- **The chip.** The owner's design round wants nothing on a card that is not its content. The owner chose this knowing what it costs: a colour-blind user who does not use a screen reader can no longer read the grade from the card.
- **The guide's row.** "안내 다시 보기" is a text button with Material's 48 tap target, the height the answer buttons had. Alone in the row, it keeps the row's height: the 20 above it and the 48 of its target. So the cards keep their height; what the buttons freed is the width beside the guide.
- **Alternatives considered:**
  - **"안내 다시 보기" in the top bar, as "사용법", with the coach's caption over the current card's bottom.** The cards would have grown by about 34 each. The PM chose this on the issue first; the owner withdrew it and kept the guide at the bottom.
  - **A setting that brings the buttons back.** The owner ruled it out.
  - **A grade shown by an icon or a word in the card's corner, smaller than the chip.** That is still something on the card that is not its content.

## Decision

- **Answering.** On the phone the current card is answered by a horizontal swipe, right for "안다" and left for "모른다", or by a screen reader's custom actions "안다" and "모른다". There is no answer button. The previous card changes by a horizontal swipe, or by its action "안다로 바꾸기" or "모른다로 바꾸기".
- **The guide.** "안내 다시 보기" sits alone and centred in a row under the current card. While the coach runs, its caption takes that row's place, as ADR 0064 placed it. The two cards share the height above the row equally, as ADR 0042 sized them.
- **Grades.** A previous card shows its grade by its fill and its line alone: `knowCard` and `knowLine` for "안다", `dontKnowCard` and `dontKnowLine` for "모른다". It shows no chip, and its semantics label names the grade.
- **Colours.** "안다" is green and "모른다" is red wherever an answer shows: the drag's reveal, the previous card's surface, and the coach. Nothing tied to an answer takes the navy.
- **The drag's reveal.** The tint and the word behind a card while it moves stay. They are feedback for an action in progress, not a chip.
- **Scope.** All of this is the phone's. The web keeps its buttons and keys for a mouse and a keyboard ([`web-study.md`](../web-study.md)), and its previous card is left for a separate issue.
- **Supersessions.** On the phone, this replaces:
  - ADR 0035's answer buttons under the current card and its grade chip;
  - the answer buttons in ADR 0042's row under the current card, which now holds the guide alone;
  - "the answer buttons" among ADR 0049's ways to answer.

## Consequences

- The screen holds two cards and one quiet link. Every answer is a swipe or a screen reader's action.
- A pointer user who cannot drag, and does not use a screen reader, cannot answer or change a card.
- A colour-blind user who does not use a screen reader cannot tell a previous card's grade.
- The cards keep their height, since the guide keeps the row the buttons stood in.
- Tests answer by a swipe of the current card or by its actions, and check that no answer button and no chip is drawn.

## Signs the decision was wrong

- Users ask how to answer without swiping, or leave sessions on their first card.
- Users misread a previous card's grade, or say they cannot tell the two cards' colours apart.
- Accessibility feedback or a store review names the missing single-pointer alternative.
