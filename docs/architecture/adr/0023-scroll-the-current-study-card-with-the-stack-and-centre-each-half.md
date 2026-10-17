# ADR 0023: Scroll the current study card with the stack as one column, and centre each half of a split card vertically

> Status: accepted; its "Gestures" and the bottom gap of its "Placement" superseded by ADR-0035; its centring of the current card's halves superseded by ADR-0049
> Date: 2026-10-15

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #56: the owner tried a release build on an iPhone on 2026-10-15 and gave two pieces of feedback:
  - when dragging down to look back through earlier cards, they expected the current card to move down with the stack, as one column. Under [ADR 0007](0007-study-swipe-screen-and-session-toggle.md) the current card stays fixed with its centre at 57% of the screen height, and only the stack above it scrolls;
  - card text sits at the top of each half, while the approved design (canvas "Main"/"DarkStudy") centres it vertically.
- The PM decided in the issue:
  - the previous cards and the current card form one scrollable column, with the current card last;
  - at rest and after every answer the view is at its end, where the current card sits as it does today;
  - lazy building, the stack's depth, blur and dots, the transitions and reduce motion are kept;
  - each half centres its content while it fits, and longer content scrolls inside it from the top, wherever the split card appears;
  - a horizontal drag answers and a vertical drag scrolls.
- The issue left open what an answer or a toggle does while the view is scrolled back. The only constraint was that the swipe must never act on a card the user cannot see. The coordinator confirmed this reading in the dispatch of issue #56:
  - a swipe can start only on the part of the card that is on screen, and once the answer commits the view returns to its end;
  - a screen reader's answer action can reach the card off screen, so it brings the card into view first;
  - a toggle acts on a card that is on screen, so the view stays where it is. Returning to the end first would act on a card no longer in view.
- The coordinator also settled the narrow layout, in which the answer sits under the question. ADR 0007 drew it as one scroll. It becomes two halves of equal height, divided at the middle, each centred: the side-by-side rule turned on its side.
- Alternatives considered for the column:
  - A reversed scroll view, which starts at its end and stays there as cards are added. A list paints its children in index order, so in reverse each older card would paint over the newer one below it, against the stack's depth.
  - Keeping the view at its end by jumping there after each frame that adds a card. For that one frame the stack shows one card too far down. Here a position that is at its end is moved to the new end in the same layout pass.
  - The current card as the last item of the lazy list. The list needs each item's height before it builds the item, and the current card's height comes from its content.
  - Disabling the swipe while the card is partly off screen. A card the user can see part of can still be swiped with no doubt about which card it is.

## Decision

- **One column.** The study screen's body is one scroll view: the stack of previous cards, built lazily, and then the current card, or the summary in its place, which paints over the stack as each card does over the one above it. Fewer cards than fill the view sit at its bottom.
- **Placement.** The space below the current card puts its centre at 57% of the screen height when the view is at its end, while it fits above the bottom gap. This replaces ADR 0007's fixed placement. The card's width, its growth from 200 to 55% of the screen height, and the gap above it are unchanged.
- **At the end.** While the view is at its end it stays there as cards are added or change size. Dragging down reveals earlier cards and moves the current card with them.
- **Scrolled back.**
  - An answer, by swipe or by a screen reader's action, returns the view to its end once it commits, animated or at once under reduce motion.
  - A screen reader's answer action first brings the card into view.
  - A toggle leaves the view where it is, a toggle that puts its card back included.
- **Gestures.** A horizontal drag on the current card answers, and a vertical drag scrolls the column.
- **Centring.** Each half of a split card centres its content vertically while it fits; longer content scrolls inside the half from the top. This covers the current card side by side and stacked, the previous cards, the card preview in the card editor and the duplicate sheet, and the photo review rows. In the stacked layout the halves are the same height, with the divider at the middle.

## Consequences

- Looking back through the session and answering happen in one surface, which matches what the owner expected.
- The current card can be partly or wholly off screen while the session is open; the answer path returns it before the user meets the next card.
- A scrolled-back view does not follow a toggle that reopens a finished session; the reopened card appears at the end, where the user returns by scrolling or by answering.
- The previous cards no longer have their own scroll view; the stack is a sliver of the session's.
- A previous card's text no longer starts below its dot, so the study screen writes no computed inset, and `app/test/shared/theme_test.dart` lists no exception.
- A short side of a split card sits in the middle of its half, beside a longer side that fills its own.

## Signs the decision was wrong

- Users scroll back, answer, and are surprised to lose their place, or ask to keep the view where it was.
- Vertical scrolls that start on the current card are taken as swipes, or swipes as scrolls, often enough that users retry.
- Users toggle a card while scrolled back, expect the session to continue at once, and look for the reopened card.
- Centred text in tall halves reads as floating, and users or the owner ask for text to start at the top again.
- In the stacked layout, equal halves leave a short question with a large empty half above a long answer that has to scroll.
