# Two-stage photo import eval

Results of `tools/eval/two_stage_run.ts` (#414): today's single call against stage 1, a page's sections, then stage 2, each section's card shapes.

- Run on 2026-10-26 over 87 images in `tools/eval/samples/`; every reply is kept in `tools/eval/replies/2026-10-26T23-05-36Z-two-stage/`, which git ignores.
- Coverage, unsupported and invented examples are the notes metrics of `docs/eval/extract-cards.md`, over the cards of each section's default shape: the vocabulary cards of a vocabulary list, a table card with whole-cell blanks for a table, and one cloze sentence a line otherwise. Vocabulary F1 is that report's, over the vocabulary shape.
- Structure, over the pages whose truth records sections: section F1 by title, and the shares of the truth's columns, row headers and lines stage 1 returned in place.
- Mark-to-blank: recall is the share of the writer's pen underlines, circles and highlights a cloze or span-table blank on the same line asks; precision the share of those blanks on a marked line that ask a mark. Spans: the same against every blank the truth names in table cells, for the span table alone.
- Shape fidelity is the share of stage-2 calls whose reply is the requested shape, valid against its section. Fabrication is the share of composed questions and sentences the judge found the page does not support.
- Cost per photo is the single call, or stage 1 with each section's default shape, as OpenRouter reported it. Latency to stage 1 is its call; total latency is stage 1 and the slowest default shape, as if the sections ran at once.
- Every two-stage call sent its own reply schema with strict structured outputs.

## Contents
- Models
- Cards
- Structure and blanks
- Shapes
- Latency
- Decision
- Human check
- Spend
- PM note (2026-10-27, round 2)

## Models

- B: Claude Haiku 5.5, then Claude Haiku 5.5: stage 1 `anthropic/claude-haiku-5.5` ($0.1000/M prompt, $0.5000/M completion, $0.0100/M cache read), stage 2 `anthropic/claude-haiku-5.5` ($0.1000/M prompt, $0.5000/M completion, $0.0100/M cache read)

## Cards

| Configuration | Vocabulary F1 | Coverage | Unsupported | Invented examples | Cost per photo | Spend |
|---|---|---|---|---|---|---|
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 92.0 | 91.4 | 11.0 | 9.4 | $0.0043 | $0.6618 |

## Structure and blanks

| Configuration | Section F1 | Columns | Rows | Lines | Mark recall | Mark precision | Span recall | Span precision |
|---|---|---|---|---|---|---|---|---|
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 97.4 | 95.8 | 95.0 | 92.9 | 83.0 | 85.9 | 48.4 | 85.9 |

## Shapes

| Configuration | Fidelity | vocabulary | table_cells | table_spans | qa | cloze | Fabrication | Composed judged |
|---|---|---|---|---|---|---|---|---|
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 98.6 | 100.0 | 100.0 | 100.0 | 100.0 | 97.3 | 3.0 | 561 |

## Latency

| Configuration | Stage 1 p50 | Stage 1 p95 | Total p50 | Total p95 |
|---|---|---|---|---|
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 10.5 s | 24.1 s | 18.0 s | 31.9 s |

## Decision

A two-stage configuration is adopted only if its coverage is no more than 3 points below today's, its unsupported share at or below today's, its shape fidelity at least 95%, and its p50 latency at most 1.5 times today's.

- None: today's single call did not run.

## Human check

Up to 30 composed sentences, spread evenly over the run, for the PM to mark by hand against their pages.

| Configuration | Sentence | Judge | PM |
|---|---|---|---|
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 「料理」の韓国語は？ | — | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 古い의 한국어는 낡다이다. | — | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 일본어 古い의 한국어 뜻은 낡다이다. | — | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 泣く의 한국어 뜻은 울다이다. | — | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 논리학은 올바른 추론과 그렇지 않은 추론을 구별하는 원리를 연구하는 학문이다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 축약에서 ㅚ+ㅓ -> ㅙ: 되+어 -> 돼 | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 보조 동사의 예는? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 본용언의 예는? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 서수사의 고유어는? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 서수사 중 고유어는 첫째, 둘째, 셋째이다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 상대 높임은 종결 어미 (-습니다, -어요)로 실현된다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 상대 높임이 높이는 대상은? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 독립 성분: 독립어는 독립 성분이다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 고구려의 정치 체제는 5부 연맹체였다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 고구려의 경제는? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 부여의 풍습에는 순장, 우계점복이 있었다. | unsupported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 고구려에서는 제가 회의에서 중대사를 결정했다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 삼한의 경제 방식은? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 고구려의 서옥제는 데릴사위제를 뜻한다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 광합성은 빛이 있을 때만 일어난다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 세포 호흡의 장소는? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 세포 호흡의 장소는? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | What is the price like in a monopoly? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | Monopoly has One firm. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | What is the product like in perfect competition? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | What is the price situation in an oligopoly? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 의문문의 종결 어미는? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 청유문은 -자로 끝난다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | The nucleus stores DNA. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | The mitochondrion has a double membrane. | supported | |

## Spend

- This run: $0.6618.
- All runs: $12.6633 of the $110.0000 budget, recorded in `tools/eval/spend.json`.

## PM note (2026-10-27, round 2)

This run is configuration B only, after #440 gave each line a role (`fact`, `example` or `heading`) and asked for marks and key terms as text. Earlier rows come from this file at #417's merge (`013c01c030e8adebb53f725c573819f4daee3675`) and at #433's merge (`c2eb2cafa9fa9fd62d50f124336549fb01b46b8c`).

| | Coverage | Unsupported | Shape fidelity | Stage 1 p50 | Total p50 | Cost/photo |
|---|---|---|---|---|---|---|
| A, single call | 95.1 | 9.4 | — | — | 9.0 s | $0.0022 |
| B, at #417 | 52.0 | 9.4 | 61% | — | 17.9 s | $0.0041 |
| B, at #433 | 79.4 | 28.3 | 98.5% | 9.4 s | 16.8 s | $0.0041 |
| B, this run | 91.4 | 11.0 | 98.6% | 10.5 s | 18.0 s | $0.0043 |

- **Quality is close to the single call.** Coverage is 3.7 points below A, where the rule allows 3. Unsupported is 1.6 above A, where the rule requires at or below. Fidelity passes.
- **Latency is what the rule cannot meet.** Two calls in sequence take 18.0 s at p50, against the rule's 13.5 s (1.5 × A). Stage 1 alone takes 10.5 s, so no stage-2 prompt can close the gap.
- **Decision (PM, under the owner's mandate):**
  - Photo import keeps the single call as its default.
  - Two-stage is now good enough for what the owner asked for: the user picks a card shape per section. After import, the app can run stage 1 once and then stage 2 per section whenever the user changes that section's shape, with no import-time latency.
  - That is a product feature, proposed to the owner on #412.

