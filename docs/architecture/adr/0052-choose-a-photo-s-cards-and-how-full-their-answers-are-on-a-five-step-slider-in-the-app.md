# ADR 0052: Choose a photo's cards and how full their answers are on a five-step slider in the app

> Status: accepted
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #148 records the owner's decision of 2026-10-17: a five-step slider, from 핵심 to 세부, sets both which cards a photo offers and how full their answers are, without calling the model again or using another extraction from the daily limit. The review keeps per-card edits, "직접 고침" surviving the slider, the duplicate grouping, and nothing written before "카드 n개 추가".
- [ADR 0051](0051-extract-each-card-with-a-question-a-fullest-and-a-short-answer-and-a-detail-step-and-eval-notes-pages-by-terms.md) gives each card of the response its `kind`, `front`, `answer`, `short` and `step` from 1 to 5, with `meaning`, `partOfSpeech` and `examples` for vocabulary, and keeps `back`. Every vocabulary entry is step 1.
- On `main` at `5ab5440e4475237dc21f25911a4d9f52ab89c3a1`, the app composes each answer at one of three levels, 간단, 기본 and 자세히, on a segmented control in capture and review, stored on the device under `photoDetailLevel` ([ADR 0028](0028-extract-each-card-in-fields-and-compose-its-answer-at-a-detail-level-in-the-app.md)).
- The deployed function is still the one before ADR 0051 until the owner picks a model and the PM deploys it. Its cards carry `front`, `back`, and `meaning`, `partOfSpeech` and `examples`, but no `kind` or `step`.
- The phone app is the only reader of the response; the web has no photo import.
- The PM approved the details below on 2026-10-18, on the worker's question in the dispatch of part 2, and added the mapping of a stored level.
- Alternatives considered:
  - A slider that only filters cards, with a separate fullness control. Two controls for one choice, where the owner asked for one.
  - Reading the stored level once and resetting it to 기본. A user who chose 간단 or 자세히 would find their choice silently changed.
  - Saving rows a step hides when they stay checked. "카드 n개 추가" would then count cards the review does not show.

## Decision

- **Steps.** Five steps: 1 핵심, 2 요점, 3 기본, 4 자세히, 5 세부. The default is 3 기본, the composition the app used by default before.
- **Which cards.** At step s, a review row is offered when one of its candidates has a step at or below s. A row a step hides keeps its checkbox, its typed answer and its duplicate option, and comes back with them. Only offered rows are listed, counted in the title and in "카드 n개 추가", and saved.
- **How full.** One rule for both kinds:

| Step | Answer |
|---|---|
| 1 핵심 | `short` |
| 2 요점 | `answer` |
| 3 기본 | `partOfSpeech`, a space, then `answer`; `answer` alone when there is no part of speech, as for every note |
| 4 자세히, 5 세부 | the 기본 answer, then each example on its own line, leaving out one that repeats the answer |

- An example repeats the answer when its text and the answer's, normalized as `deck`'s card key normalizes a front, contain one another. ADR 0051 lets a page's worked example be both a card's answer and its example, and showing it twice says nothing more.
- Step 5 differs from step 4 only in offering the cards of step 5. A row combining several candidates joins the answers of those the step offers by `deck`'s merge-back rule. So a vocabulary page reads at 핵심 as 간단 did when `short` is the first meaning, and at 기본 and 자세히 as the levels of those names did.
- **Old response.** A card without `kind`, from a function deployed before ADR 0051, is vocabulary at step 1, its answer and short form its `meaning`, or its `back` when it has none. So every step offers every card, and the slider changes only how full the answers are.
- **New response.** A card with `kind` must carry a known `kind`, a non-empty `answer` and `short`, and an integer `step` from 1 to 5; otherwise the answer is outside the contract, a `ServiceFailed`.
- **Control.** A `Slider` of five divisions under "카드에 담을 내용" with the current step's name beside it, and 핵심 and 세부 under its ends, in capture and review. A screen reader hears it as one node: the label, and the step's name and number as its value.
- **Storage.** The step is stored under a new key, `photoDetailStep`. When none is stored and `photoDetailLevel` holds a level, it maps once to the nearest step — 간단 to 핵심, 기본 to 기본, 자세히 to 자세히 — which is stored under the new key while the old one is removed, so it is read no more. With neither, the step is 기본.
- **Supersessions.** This replaces ADR 0028's three levels, their segmented control in capture and review, and their storage under `photoDetailLevel`.

## Consequences

- Moving the slider is instant and free: every step reads the one extraction the screen holds.
- The app works against both the deployed function and the one ADR 0051 describes, so it can ship before the PM deploys the new function. Until then, a notes page reaches it only as the old prompt reads it.
- The review's title counts the offered rows, so it changes as the slider moves, and a row hidden at a low step is not saved even when it stays checked.
- A device keeps its user's level once, as a step; the old key is gone after the first open.

## Signs the decision was wrong

- Users check a card, lower the slider, and are surprised the card was not saved.
- Users of vocabulary pages miss 간단's meaning alone, because `short` and `answer` coincide for most entries, so 핵심 and 요점 read the same.
- The model's steps leave step 1 empty or crowded on real notes, so the default of 기본 offers too few or too many cards.
