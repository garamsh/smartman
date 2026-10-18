# ADR 0060: Choose which topics to memorise, and their card shape, before Review, from the one call's cards

> Status: accepted
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- [ADR 0057](0057-group-a-photo-s-cards-by-topic-on-review-with-a-switch-per-topic-and-swipes-per-card.md) decided one call and one Review, grouped by topic: "The photo goes to today's Extracting, then to Review. There is no other screen."
- Issue #190 records the owner's decision of 2026-10-18 to return to two screens: ① chooses what to memorise, and ② is ADR 0057's Review. ① is built from the cards the one call returns, grouped by their `topic`, so the cost and the call do not change. The owner chose this over a separate survey call.
- The PM's design canvas, `https://claude.ai/artifact/9GxVB2RjZ36BtgcyBr6UmD`, draws ① as the board "① 무엇을 외울까요 (한 번 만든 카드의 주제)".
- Every card carries a `topic`, from the function since #179 ([ADR 0055](0055-cover-everything-a-notes-page-teaches-at-step-5-with-prompt-v4-and-eval-a-dense-page-by-coverage-per-page.md)), and `examples` where the page prints them. On `main`, the app no longer read the examples.
- The PM confirmed three details on 2026-10-18, on the worker's question in the dispatch: the headline, the label for cards with no topic, and reading the examples again.
- Alternatives considered:
  - **A survey call before the cards**, as ADR 0057's first versions had. It costs a call and a wait, and the choice rests on a description of the page rather than on its cards.
  - **The canvas's "+ 추가" pill for a typed topic.** One call cannot make cards for a topic typed after it returns, so the pill would add a topic with no cards.
  - **The topic switches on Review alone, without ①.** The owner asked to choose what to memorise, and the shape of its cards, before reading every card.

## Decision

- **Flow.** The photo goes to Extracting, then to ①, then to ② (Review). There is still one call.
- **① 무엇을 외울까요**, as the canvas draws it:
  - **Headline.** "카드 n장을 만들었어요." then "무엇을 외울까요?", centred, where n is every card the call made. The call returns no description of the page, so the headline counts the cards instead of naming the page.
  - **Pills.** One pill per topic, in the order each first appears, on at first with a check. A tap toggles it. Cards with no topic, from a function deployed before #179, go under one pill, "이 페이지".
  - **Samples.** For each topic that is on, a scrolling list shows the topic's first card in the chosen shape.
    - A tap on its front offers "개념 이름" (the default) or "내용을 앞에", which puts the content on the front and the concept's name on the back.
    - A tap on its back offers "핵심만" (the default, the answer) or "예시까지", the answer followed by each example the page prints, one per line. With the content in front, the examples follow the content.
    - The choice applies to every card of that topic, on the device, with no new call.
  - **No "+ 추가".** No pill takes a typed topic, for the reason above.
  - **"다음"** opens ② with the cards of the topics that are on, each in its topic's shape. It is disabled when no topic is on. The deck's card keys are read then, and a failure to read them shows in a snack bar on ①.
- **② Review** is ADR 0057's, over the cards ① passes: grouped by topic, with each topic's switch, the swipes, the edits and the coach.
- **Examples.** The app reads each card's `examples` again, for "예시까지".
- **Supersessions.** This replaces ADR 0057's "There is no other screen".

## Consequences

- The user chooses what to memorise, and how its cards read, before going through every card, at no extra cost or wait.
- A topic left out on ① still has its switch on ② only if it was on, so ② shows only the topics chosen.
- The shape is one per topic, so a topic mixing several kinds of card takes one shape for all of them.
- A sample is the topic's first card, which may not be the most telling.

## Signs the decision was wrong

- Users keep every topic on ① and switch topics off on ②, so ① adds a screen for nothing.
- Users change the shape on ① and then rewrite many cards on ②, so one shape per topic is too coarse.
- Users look for the "+ 추가" pill the canvas first drew.
