# ADR 0042: Show only the previous and the current study card at one size, re-decide the previous card by a swipe, and open it on a tap

> Status: accepted; its "First session" guide superseded by ADR-0044; its tap on the current card that shows the answer superseded by ADR-0049; on the web, the current card answered by ← and → alone superseded by ADR-0084; on the phone, the answer buttons in its row under the current card superseded by ADR-0099
> Date: 2026-10-17

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- On `main` at `5dbf7e4644ffe8d3c6c031aca5040cd4d300184d`, the study screen follows [ADR 0035](0035-show-the-previous-and-current-study-card-reach-earlier-cards-three-at-a-time-re-decide-the-centred-card-and-grade-each-card-by-its-colour-and-a-chip.md): the newest previous card rests above the current card, smaller and 120 high, with two lines of each side; dragging down scrolls earlier cards into view, three at a time; only the centred card, while scrolled back, is dragged to change its answer; "지금 카드로" returns; a long-press opens the whole card in a sheet. On the web, ↑, the wheel or a touch drag reach earlier cards, and the centred card offers its change as a button.
- Issue #140 records the owner's decisions on the device on 2026-10-17, from a screenshot of the scrolled-back screen with "yield" cut to "양도…": no drag down to earlier cards, only the previous card and the current card on screen; the previous card the same size as the current card; a tap opening the detail where a long-press did; a larger text area for long answers.
- The PM settled the consequences in the issue: a tap on the current card still reveals its answer; the previous card keeps its fill, line and chip; the cards sized so that a two-line answer at the answer style fits without an ellipsis on a 390 by 844 screen, text that still overflows scaled down to its floor before it is cut; the web on the same model, with Z toggling the last answer and the side list kept on wide screens; issue #138, the gap between earlier cards, closed as superseded.
- The owner then decided, in a comment on the issue on 2026-10-17, replacing the PM's re-deciding from the detail view: the previous card is re-decided by a horizontal swipe with ADR 0035's threshold and fling rules, the current card is still answered by a swipe, the screen reader's change action stays as the non-drag alternative, and the detail view carries no change buttons.
- The PM settled the web's gaps on the worker's question in the dispatch: at a phone's width the side list is hidden and nothing else changed an answer, so the previous card takes the same horizontal touch swipe on the web, "마지막 답 바꾸기" (Z) shows at every width as the non-drag alternative, and a click on the previous card opens a dialog with the whole card, closed by "닫기" and Esc, returning the focus to the card.
- Alternatives considered for the card size:
  - The current card growing with its content, as before, and the previous card matching it. Each answer would move both cards and the answer buttons; a fixed size keeps every control where the thumb left it.
  - The previous card at its own fixed size above a growing current card. It is the "smaller" card the owner asked to remove.
- Alternatives considered for text that does not fit the previous card:
  - Scrolling inside its halves, as the current card's do. The previous card's halves take a swipe and a tap; the whole card is a tap away in the sheet, so a cut with an ellipsis loses nothing.
  - A fixed number of lines, as the two lines before. The cards are now as tall as the screen allows, so the lines that fit the half are the measure.

## Decision

- **Two cards.** The study screen shows the card answered just before the current one above the current card, or the completion card in its place, and no other answered card. Nothing scrolls to earlier cards; there is no "지금 카드로".
- **One size.** Both cards are full width less 20 on each side and share the height between the top bar and the answer buttons equally: each is half of that height less 20 above the previous card, 16 between the cards, the answer buttons' row (20 above a 48 high target) and 16 below. On a 390 by 844 phone with a 47 top and 34 bottom inset that is 293.5, and a half's text box about 142 wide and 261 high, nine lines at the answer's 20/28. The completion card takes the current card's place and the answer buttons'; the previous card keeps its size. Before the first answer the previous card's place is empty, or holds the first session's guide.
- **Text.** The previous card draws its sides as the current card does, the front at 30/800 and the back at 20/600, centred in halves of the same split. A side scales down, as far as its floor (18 and 15), until its widest word fits, then until the whole side fits its half; past the floor it is cut with an ellipsis at the lines that fit. The current card keeps its rule: the widest word at most to the floor, then each half scrolls.
- **Re-deciding.** The previous card follows a horizontal drag, showing the answer it would give behind it; released past 100, or flung, toward the other answer, it changes to it, replayed as a toggle is ([ADR 0007](0007-study-swipe-screen-and-session-toggle.md)); toward the answer it has it follows a quarter of the finger's travel and changes nothing. A drag on either card moves that card alone. A screen reader changes it by its action, "안다로 바꾸기" or "모른다로 바꾸기". Only the previous answer changes on the phone.
- **Detail.** A tap on the previous card opens the whole card in the sheet the long-press opened, with no action. A tap on the current card shows or hides its answer, as before.
- **First session.** The guide keeps two lines, revealing and answering, and loses the line on pulling down.
- **Web.** The same model: two rows of one height, the taller one's, at least 208 (300 from 1024 px); the previous card's sides at 30/800 and 20/600, cut after six lines. A click opens the whole card in a dialog; a horizontal touch swipe changes its answer by the phone's rules while a vertical one scrolls the page. ← and → answer the current card and re-decide nothing; ↑, ↓ and the wheel do nothing; Z and "마지막 답 바꾸기", now at every width, toggle the last answer; from 1024 px the list beside the cards keeps its one-click change of any answer.
- **Supersessions.** This replaces ADR 0035's "Rest" (the smaller previous card and the 36% slot), its "Earlier cards", its "Re-deciding" (the centred card alone, while scrolled back), its first-run guide's line on reaching earlier cards, and, on the web, its keys, wheel and drag that reach earlier cards and the centred card's change button.

## Consequences

- The screen at rest and in use is the same two cards; an answer older than the previous one is reached on the phone by no gesture, and on the web through the list beside the cards from 1024 px.
- A mistake noticed one card late is fixed by one swipe, where it took a scroll and a drag; a mistake noticed later is not fixed on the phone.
- A long answer's half is about three times as tall as a 120 high card's on a 390 by 844 phone, and the cards no longer change size with their content.
- `SessionScroll`, the snapping physics and the paint-time emphasis leave the app; `deck`'s `ContentView` gains a fit to a height, which the previous card alone uses.

## Signs the decision was wrong

- Users ask for the answers before the previous one during a session, on the phone.
- Users swipe the previous card meaning to answer the current one, and change answers they did not mean to.
- Long answers are still cut on the previous card often enough that users open the sheet for most cards.
- On short screens, or at large text scales, the two cards leave the current card's halves scrolling for ordinary answers.
