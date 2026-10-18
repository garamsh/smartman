# ADR 0057: Group a photo's cards by topic on Review, with a switch per topic and swipes per card

> Status: accepted; its "There is no other screen" superseded by ADR-0060
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #182 records the owner's request of 2026-10-18: after a photo, the user decides what becomes cards and how each kind of item is memorised, so they get the cards they meant rather than the AI's guess.
- Today one call returns every card with a step from 1 to 5, and Review offers the cards a five-step slider admits, with a checkbox on each ([ADR 0051](0051-extract-each-card-with-a-question-a-fullest-and-a-short-answer-and-a-detail-step-and-eval-notes-pages-by-terms.md), [ADR 0052](0052-choose-a-photo-s-cards-and-how-full-their-answers-are-on-a-five-step-slider-in-the-app.md)). The photo comes from the system camera or the library ([ADR 0054](0054-take-the-photo-with-the-system-camera-or-from-the-library-and-remove-the-in-app-camera-view.md)).
- **Earlier versions of this ADR**, on the same day:
  - first, a survey call before the cards, a screen to choose topics and a card shape per topic, then a make call, with a signed token so the two calls counted once;
  - then, after the owner's review, that design with a light survey on its own model and the make call routed by page.
  - The owner approved that version, then simplified the design the same day.
- **The owner's design.** The PM drew it on a private canvas, `https://claude.ai/artifact/9GxVB2RjZ36BtgcyBr6UmD`, titled "smartman 사진 대화 시안". Its one board is "사진 → 검토 (주제별로 넣고 빼기)": there is no survey and no choice screen.
  - The photo goes to today's Extracting and then to a new Review.
  - Review groups the cards by topic, and each topic's heading carries a switch that keeps or drops the whole topic.
  - Per card, a swipe left removes it, a swipe right puts it back, and a tap edits it in place. A removed card stays in the list, struck through. A coach teaches the gestures on first use.
- The function side, a `topic` on each card and the rules for writing it, goes into #179's revision, which another worker owns. The app is built against a `topic` of 1 to 60 characters on each card.
- Alternatives considered:
  - **A survey and a choice screen before the cards**, this ADR's earlier versions. A call and a wait come before any card, and the choices are made on a description rather than on the cards themselves. Grouping the cards by topic gives the same choice of what to keep, on the cards the user will save.
  - **A card shape chosen per topic.** It needs a call that knows the shape before the cards are written. The owner dropped it with the choice screen.
  - **Keeping the slider beside the switches.** Two controls would then decide which cards are kept. The switches and swipes decide it by topic and by card, and the user reads each card.
  - **Checkboxes, or an edit mode with a delete button.** The owner chose swipes, in the same directions as studying, with a tap to edit.
  - **Dropping a removed card from the list.** A card swiped by mistake could not be found again. It stays, struck through, until the cards are added.

## Decision

- **Flow.** The photo goes to today's Extracting, then to Review. There is no other screen.
- **One call.** As today, the function returns every card of the page, and each card carries a `topic`, the name of the part of the page it comes from, 1 to 60 characters. The function keeps today's fields, so an app that has not updated reads the cards as before. The app reads `front`, the answer, the part of speech and `topic`; it no longer reads `step`, `short` or `examples`.
- **Review**, as the canvas draws it:
  - **Title.** "카드 n장을 만들었어요", where n is every card made.
  - **Sections.** The cards are grouped by topic, in the order each topic first appears. A section's heading is "<topic> · n장", with a switch, on at first.
    - Switching a topic off shows each of its cards as removed, mutes its heading, and leaves its cards closed to editing.
    - Switching it on brings back each card not removed on its own.
  - **A card** shows its front and its answer side by side.
    - A swipe left removes it and a swipe right puts it back, the same directions as studying's "모른다" and "안다" (`study.md`). Under the moving card, "빼기" shows on the red tint and "다시 넣기" on the green.
    - A removed card stays in the list, struck through inside a dashed outline.
    - A tap opens it for editing in place, with "앞면" and "뒷면" fields, "이 카드 빼기" (or "다시 넣기" for a removed card) as the one-pointer alternative to the swipes, and "완료".
  - **Adding.** "덱에 n장 추가" counts the cards whose topic is on and which are not removed, and is disabled at 0.
  - **The coach.** On first use, a three-step coach shows a finger on the first card and dims the others. Its caption reads "왼쪽으로 밀면 빼요", then "오른쪽으로 밀면 다시 넣어요", then "눌러서 바로 고쳐요", with dots, "건너뛰기" and "다음", the last "시작하기".
    - It shows once per device and replaces the add button while it runs.
    - Any swipe, tap or switch ends it.
    - It is not shown under reduce motion.
  - **The answer shown** is today's 기본 composition: a vocabulary card's part of speech, a space, then its answer; a note's answer.
  - **A card without a topic**, from a function deployed before #179's revision, goes into one section with no heading and no switch.
- **Carried over from today**, which the canvas does not draw:
  - the close button, nothing written before the add button, candidates with one card key on the photo combined into one, the name sheet for a new deck, and the failure views;
  - the deck chip ("추가할 덱 · <name>") under the title and "다시 찍기" in the top bar ([ADR 0054](0054-take-the-photo-with-the-system-camera-or-from-the-library-and-remove-the-in-app-camera-view.md));
  - the duplicates: a card whose key the deck already holds starts removed, with "이미 덱에 있어요" under it. Putting it back merges its answer into the deck's card by `deck`'s merge-back rule, so no card is doubled.
- **Removed from the app:**
  - the five-step slider;
  - its offering of cards by step and its composition of answers by step;
  - the step stored under `photoDetailStep`, which a device keeps unread;
  - the checkboxes and the duplicate option chip.
- **Supersessions.** This replaces ADR 0052's slider, its offering and composition by step, and its storage, in the app. The function's `step` and `short` stay for apps that have not updated.

## Consequences

- One call and one wait, as today, and no change to the cost of a photo.
- The user decides what to keep on the cards themselves, a topic at a time or a card at a time, and a mistake is undone in place.
- The topics are only as good as the model's grouping, which #179's revision and its eval decide.
- Review's swipes match studying's directions, so the habit carries over, and every swipe has a button in the edit view.
- A device's stored step stays, unread.

## Signs the decision was wrong

- Users switch most topics off on most pages, so the model makes far more cards than people want and the page should be asked about first.
- The topics come out too fine or too coarse for one switch to mean anything, such as one card a topic.
- Users remove cards by accident with a swipe, or never find the swipe despite the coach.
- Users miss choosing how full an answer is, which the slider gave.
