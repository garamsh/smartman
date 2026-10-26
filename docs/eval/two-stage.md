# Two-stage photo import eval

Results of `tools/eval/two_stage_run.ts` (#414): today's single call against stage 1, a page's sections, then stage 2, each section's card shapes.

- Run on 2026-10-26 over 87 images in `tools/eval/samples/`; every reply is kept in `tools/eval/replies/2026-10-26T21-36-51Z-two-stage/`, which git ignores.
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
- PM note (2026-10-27)

## Models

- B: Claude Haiku 5.5, then Claude Haiku 5.5: stage 1 `anthropic/claude-haiku-5.5` ($0.1000/M prompt, $0.5000/M completion, $0.0100/M cache read), stage 2 `anthropic/claude-haiku-5.5` ($0.1000/M prompt, $0.5000/M completion, $0.0100/M cache read)

## Cards

| Configuration | Vocabulary F1 | Coverage | Unsupported | Invented examples | Cost per photo | Spend |
|---|---|---|---|---|---|---|
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 83.4 | 79.4 | 28.3 | — | $0.0041 | $0.6626 |

## Structure and blanks

| Configuration | Section F1 | Columns | Rows | Lines | Mark recall | Mark precision | Span recall | Span precision |
|---|---|---|---|---|---|---|---|---|
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 91.9 | 85.4 | 83.8 | 83.6 | 79.5 | 93.8 | 42.5 | 93.0 |

## Shapes

| Configuration | Fidelity | vocabulary | table_cells | table_spans | qa | cloze | Fabrication | Composed judged |
|---|---|---|---|---|---|---|---|---|
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 98.5 | 100.0 | 100.0 | 97.0 | 100.0 | 97.8 | 2.4 | 677 |

## Latency

| Configuration | Stage 1 p50 | Stage 1 p95 | Total p50 | Total p95 |
|---|---|---|---|---|
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 9.4 s | 27.4 s | 16.8 s | 30.2 s |

## Decision

A two-stage configuration is adopted only if its coverage is no more than 3 points below today's, its unsupported share at or below today's, its shape fidelity at least 95%, and its p50 latency at most 1.5 times today's.

- None: today's single call did not run.

## Human check

Up to 30 composed sentences, spread evenly over the run, for the PM to mark by hand against their pages.

| Configuration | Sentence | Judge | PM |
|---|---|---|---|
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | What is the Korean word for "slowly"? | — | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | What is the Korean meaning of "careful"? | — | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | garden은 정원이라는 뜻이다. | — | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 明るいの韓国語訳は「밝다」です。 | — | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 「写真」の韓国語は？ | — | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 논증은 전제와 결론으로 이루어진 문장들의 집합이다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 지금까지 본 백조는 모두 희다에서 모든 백조는 희다로 가는 추론은 귀납이다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | Demand shifters include income, tastes, prices of related goods, and expectations. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | The price at which quantity demanded equals quantity supplied is the equilibrium price. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | '잡+아'는 '잡아'가 되고, '먹+어'는 '먹어'가 된다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 어간 끝 'ㅡ'는 '-아/-어' 앞에서 떨어진다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 보조 형용사에는 싶다, 보다, 하다 등이 있다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 보조 동사의 쓰임은? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 수사는 수량이나 순서를 나타내는 체언으로, 뒤에 조사가 붙는다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 한자어로 된 서수사는? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 상대 높임은 어떻게 실현하는가? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 주체 높임은 문장의 주어를 높이는 것이다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 예외적으로 부사어도 체언을 꾸밀 때가 있다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 고구려에는 데릴사위제인 서옥제가 있었다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 삼한에서는 벼농사가 발달했다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 부여는 반농반목 경제였다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 고구려는 5부 연맹체였다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 세포 호흡의 장소는 미토콘드리아이다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 세포 호흡은 밤낮없이 항상 일어난다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 세포 호흡의 에너지는? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | An oligopoly is dominated by a few large firms. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | Firms in a monopoly are price makers. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 청유문의 종결 어미는? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 의문문의 종결 어미는 -니, -까이다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | What membrane does the chloroplast have? | supported | |

## Spend

- This run: $0.6626.
- All runs: $12.0015 of the $110.0000 budget, recorded in `tools/eval/spend.json`.

## PM note (2026-10-27)

This run is configuration B only, after #433 changed stage 2's cloze and table prompts. It is compared here with the previous full run, recorded in this file as #417 merged it (commit `013c01c030e8adebb53f725c573819f4daee3675`).

| | Coverage | Unsupported | Shape fidelity | cloze | table_cells | p50 | Cost/photo |
|---|---|---|---|---|---|---|---|
| A, single call, previous run | 95.1 | 9.4 | — | — | — | 9.0 s | $0.0022 |
| B, previous run | 52.0 | 9.4 | 61% | 33% | 77% | 17.9 s | $0.0041 |
| B, this run | 79.4 | 28.3 | 98.5% | 97.8% | 100% | 16.8 s | $0.0041 |

- **Shape fidelity now passes the decision rule's 95%.** The two causes the worker named are fixed: an empty blank list refusing the whole call, and character offsets into the model's own sentence.
- **Coverage, 79.4, is still 15.7 points below A.** The loss is concentrated in the Korean grammar and auxiliary-verb notes, at 0.56 to 0.67 per page (samples 33 to 40).
- **Unsupported, 28.3, mostly reflects how it is measured.**
  - “Unsupported” here is `metrics.ts` `scoreNotes`: a card that holds the terms of no truth fact. Stage 2 now writes one cloze per line, including example and heading lines, and those cards match no fact.
  - The judge, reading the composed sentences against the page, found 2.4% fabricated.
  - Even so, the measure is the decision rule's, and B does not pass it.
- **Decision (PM, under the owner's mandate):** photo import keeps the single call. The next iteration targets coverage on the grammar notes, and one cloze for each fact line rather than for every line. #412 records it.

