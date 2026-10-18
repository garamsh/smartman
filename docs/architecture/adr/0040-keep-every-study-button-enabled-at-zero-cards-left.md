# ADR 0040: Keep every study button enabled at zero cards left, and offer 계속 학습 on the done today card

> Status: accepted; its study button on a deck that holds no card superseded by ADR-0066
> Date: 2026-10-17

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- On `main` at `ccbbe7aa49cea7a0b9100f31b81b1aed54cf5d03`, with no card left today, both clients' today cards read "오늘 할 카드를 다 했어요" and offer no session ([ADR 0027](0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)), and the deck page's "학습하기 · 0장" is disabled, on the phone also while the count is pending or unreadable.
- Issue #120 records the owner's decision of 2026-10-17: once today's cards are done, the study button is not disabled; it stays enabled so the user can keep studying.
- The PM settled the today card on the worker's question in the dispatch of issue #120: the approved `HomeDone` artboard draws a "계속 학습" button on the done today card, so the card keeps "오늘 할 카드를 다 했어요" and shows that button, where #120 had said the label stays as it is.
- The study screen already shows both zero states: the completion card when a card of its decks was answered today, and "오늘은 학습할 카드가 없어요" otherwise.
- Alternatives considered:
  - Keep the done today card without a button, and enable only the deck page's. The owner named the today screen, and the artboard draws the button there.
  - Label the done today card's button "모두 학습". It would promise cards the card has just said are done; "계속 학습" names what the completion card offers.

## Decision

- **Enabled.** Every study button on both clients opens the study screen whatever the count, including, on the phone, while the count is pending or cannot be read.
- **Done today card.** With no card left today, the today card keeps "오늘 할 카드를 다 했어요" and shows a white "계속 학습", which opens the session over every deck that "모두 학습" opens.
- **Deck page.** "학습하기 · n장" keeps its label and its count, 0 included.
- **At zero.** The study screen opens on the completion card, from which "계속 학습" goes on as practice, when a card of its decks was answered today, and on "오늘은 학습할 카드가 없어요" otherwise.
- **Supersessions.** This replaces ADR 0027's today card that offers no session with nothing to study.

## Consequences

- Practice over the day's answers ([ADR 0033](0033-count-cards-left-per-study-day-from-04-00-and-continue-as-unrecorded-practice.md)) is one tap from the today card and from each deck page, at any time of the day.
- A tap at zero always leads somewhere; when nothing was answered today it leads to a screen that says so, one tap away from where the count already said it.
- The web's `StudyLink` no longer takes the count, since nothing in it depends on it.

## Signs the decision was wrong

- Users at zero open the study screen, find "오늘은 학습할 카드가 없어요", and report the button as broken.
- Users read "계속 학습" on the done today card as new cards and are surprised by practice.
- Practice sessions opened from the today card are rare enough that the button reads as clutter on a finished day.
