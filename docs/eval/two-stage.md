# Two-stage photo import eval

Results of `tools/eval/two_stage_run.ts` (#414): today's single call against stage 1, a page's sections, then stage 2, each section's card shapes.

- Run on 2026-10-26 over 87 images in `tools/eval/samples/`; every reply is kept in `tools/eval/replies/2026-10-26T17-57-45Z-two-stage/`, which git ignores.
- Coverage, unsupported and invented examples are the notes metrics of `docs/eval/extract-cards.md`, over the cards of each section's default shape: the vocabulary cards of a vocabulary list, a table card with whole-cell blanks for a table, and one cloze sentence a line otherwise. Vocabulary F1 is that report's, over the vocabulary shape.
- Structure, over the pages whose truth records sections: section F1 by title, and the shares of the truth's columns, row headers and lines stage 1 returned in place.
- Mark-to-blank: recall is the share of the writer's pen underlines, circles and highlights a cloze or span-table blank on the same line asks; precision the share of those blanks on a marked line that ask a mark. Spans: the same against every blank the truth names in table cells, for the span table alone.
- Shape fidelity is the share of stage-2 calls whose reply is the requested shape, valid against its section. Fabrication is the share of composed questions and sentences the judge found the page does not support.
- Cost per photo is the single call, or stage 1 with each section's default shape, as OpenRouter reported it. Latency to stage 1 is its call; total latency is stage 1 and the slowest default shape, as if the sections ran at once.
- Every two-stage call sent its own reply schema with strict structured outputs.

## Models

- A: prompt v9, Claude Haiku 5.5: `anthropic/claude-haiku-5.5` ($0.1000/M prompt, $0.5000/M completion, $0.0100/M cache read)
- B: Claude Haiku 5.5, then Claude Haiku 5.5: stage 1 `anthropic/claude-haiku-5.5` ($0.1000/M prompt, $0.5000/M completion, $0.0100/M cache read), stage 2 `anthropic/claude-haiku-5.5` ($0.1000/M prompt, $0.5000/M completion, $0.0100/M cache read)
- C: Claude Sonnet 5.5, then Claude Haiku 5.5: stage 1 `anthropic/claude-sonnet-5.5` ($2.0000/M prompt, $10.0000/M completion, $0.1000/M cache read), stage 2 `anthropic/claude-haiku-5.5` ($0.1000/M prompt, $0.5000/M completion, $0.0100/M cache read)

## Cards

| Configuration | Vocabulary F1 | Coverage | Unsupported | Invented examples | Cost per photo | Spend |
|---|---|---|---|---|---|---|
| A: prompt v9, Claude Haiku 5.5 | 99.7 | 95.1 | 9.4 | 6.3 | $0.0000 | $0.0000 |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 88.6 | 52.0 | 9.4 | — | $0.0041 | $0.5628 |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | 74.4 | 76.2 | 18.0 | — | $0.0473 | $4.3975 |

## Structure and blanks

| Configuration | Section F1 | Columns | Rows | Lines | Mark recall | Mark precision | Span recall | Span precision |
|---|---|---|---|---|---|---|---|---|
| A: prompt v9, Claude Haiku 5.5 | — | — | — | — | — | — | — | — |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 100.0 | 100.0 | 100.0 | 94.3 | 85.8 | 92.1 | 47.2 | 95.2 |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | 97.4 | 95.8 | 95.0 | 95.4 | 90.9 | 86.5 | 67.5 | 70.2 |

## Shapes

| Configuration | Fidelity | vocabulary | table_cells | table_spans | qa | cloze | Fabrication | Composed judged |
|---|---|---|---|---|---|---|---|---|
| A: prompt v9, Claude Haiku 5.5 | — | — | — | — | — | — | — | 0 |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 61.3 | 100.0 | 76.7 | 83.3 | 100.0 | 33.1 | 0.0 | 291 |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | 92.0 | 100.0 | 100.0 | 100.0 | 100.0 | 84.7 | 0.3 | 594 |

## Latency

| Configuration | Stage 1 p50 | Stage 1 p95 | Total p50 | Total p95 |
|---|---|---|---|---|
| A: prompt v9, Claude Haiku 5.5 | — | — | 9.0 s | 23.5 s |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 10.2 s | 28.5 s | 17.9 s | 33.1 s |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | 17.2 s | 33.1 s | 23.4 s | 47.5 s |

## Decision

A two-stage configuration is adopted only if its coverage is no more than 3 points below today's, its unsupported share at or below today's, its shape fidelity at least 95%, and its p50 latency at most 1.5 times today's.

- B: Claude Haiku 5.5, then Claude Haiku 5.5: keep the single call (coverage no, unsupported yes, fidelity no, latency no).
- C: Claude Sonnet 5.5, then Claude Haiku 5.5: keep the single call (coverage no, unsupported no, fidelity no, latency no).

## Human check

Up to 30 composed sentences, spread evenly over the run, for the PM to mark by hand against their pages.

| Configuration | Sentence | Judge | PM |
|---|---|---|---|
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | What is the Korean word for "slowly"? | — | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | hungry의 뜻은 배고픈이다. | — | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 「泣く」の韓国語は何ですか？ | — | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | Surplus occurs when quantity supplied exceeds quantity demanded, above the equilibrium price. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | ㄹ 탈락의 예로 살+는 -> 사는, 놀+ㅂ니다 -> 놉니다가 있다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 주체 높임은 선어말 어미 '-시-'로 실현된다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 부여의 경제는? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 2단계 TCA 회로는 미토콘드리아 기질에서 진행된다. | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | What are the firms like in a monopoly? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | What is the product in a monopoly? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | 의문문의 예는? | supported | |
| B: Claude Haiku 5.5, then Claude Haiku 5.5 | What is the mitochondrion's function? | supported | |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | 安い의 한국어 뜻은 싸다. | — | |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | 전제 지시어에는 왜냐하면, ~이므로, ~때문에 등이 있다. | supported | |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | When income rises, there are fewer bus rides, since bus rides are an inferior good. | supported | |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | 본용언의 쓰임은? | supported | |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | 양수사의 한자어는 일, 이, 삼, 사이다. | supported | |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | 상대 높임의 실현 방법은? | supported | |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | 상대 높임은 종결 어미 (-습니다, -어요)로 실현한다. | supported | |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | 고구려의 중대사는 제가 회의에서 결정되었다. | supported | |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | 삼한에서 천군이 소도를 관리했다. | supported | |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | 부여의 특산물은 말, 주옥, 모피이다. | supported | |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | 고구려는 약탈 경제에 부경 창고를 두었다. | supported | |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | TCA 회로는 미토콘드리아 기질에서 진행된다. | supported | |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | 광합성의 장소는? | supported | |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | What is the price like in perfect competition? | supported | |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | In perfect competition, there are many small firms. | supported | |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | Oligopolies face significant barriers. | supported | |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | What is the Membrane of the Nucleus? | supported | |
| C: Claude Sonnet 5.5, then Claude Haiku 5.5 | What does the nucleus do? | supported | |

## Spend

- This run: $4.9604.
- All runs: $11.1476 of the $110.0000 budget, recorded in `tools/eval/spend.json`.

## PM note (2026-10-27)

- Configuration A's spend and cost per photo read $0.0000 because `run.ts` priced its BYOK replies by `usage.cost` alone before #419. Its 87 calls cost $0.191271 by `upstream_inference_cost`, about $0.0022 per photo. The ledger entry includes it.
- The run spent $5.151632 in total. Owner budget for #412: $100, of which $5.35 is spent with this run and the preflight and first run.
