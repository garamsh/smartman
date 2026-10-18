# Extract-cards model eval

Results of `tools/eval/run.ts`: how each candidate configuration extracts cards from the sample set.

- Run on 2026-10-18 with prompt v4, over 12 images in `tools/eval/samples/`.
- The samples are synthetic: printed and handwritten-style pages rendered and distorted by `tools/eval/generate.py`, not phone photos.
- Vocabulary pages: precision, recall and F1 are means of the per-image values, in percent; a card matches when its front and meaning (its answer, when it has no meaning) equal the ground truth after card key normalization.
- Over the matched cards of every image, in percent: part of speech and examples are the share equal to the page's after the same normalization; invented is the share of present parts of speech and example lists on an entry whose page prints none. A dash means the configuration returned no such field.
- Notes pages, in percent: coverage at step s is the share of the page's facts of step s or below that a card of step s or below covers, its front, answer and examples holding each of the fact's terms after the same normalization, averaged over the images; unsupported is the share of returned cards covering no fact, which also counts a fact the model paraphrased past its terms; invented examples is the share of returned examples the page does not print; step order is the share of pairs of covered facts with different steps that the returned steps order alike, a tie counting half.
- Latency is per image, retry included; cost per image is the mean of OpenRouter's reported cost, over every image.

## Models

- Claude Haiku 5.5: `anthropic/claude-haiku-5.5` ($0.1000/M prompt, $0.5000/M completion)
- Claude Sonnet 5.5: `anthropic/claude-sonnet-5.5` ($2.0000/M prompt, $10.0000/M completion)
- Google Gemini Flash, newest: `google/gemini-3.8-flash` ($0.8250/M prompt, $4.1250/M completion)
- OpenAI GPT mini, newest: `openai/gpt-5.4-mini` ($0.7500/M prompt, $4.5000/M completion)

## Vocabulary pages

| Configuration | Precision | Recall | F1 | Part of speech | Examples | Invented | p50 latency | p90 latency | Cost per image | Total spend |
|---|---|---|---|---|---|---|---|---|---|---|
| Claude Haiku 5.5 | 0.0 | 0.0 | 0.0 | — | — | — | 10.7 s | 23.4 s | $0.0021 | $0.0248 |
| Claude Sonnet 5.5 | 0.0 | 0.0 | 0.0 | — | — | — | 8.6 s | 14.9 s | $0.0247 | $0.2963 |
| Google Gemini Flash, newest | 0.0 | 0.0 | 0.0 | — | — | — | 4.3 s | 4.9 s | $0.0725 | $0.8704 |
| OpenAI GPT mini, newest | 0.0 | 0.0 | 0.0 | — | — | — | 5.0 s | 8.7 s | $0.0065 | $0.0776 |

## Notes pages

| Configuration | Coverage at 1 | 2 | 3 | 4 | 5 | Unsupported | Invented examples | Step order |
|---|---|---|---|---|---|---|---|---|
| Claude Haiku 5.5 | 85.4 | 91.7 | 93.3 | 95.2 | 94.6 | 3.7 | 61.9 | 57.1 |
| Claude Sonnet 5.5 | 91.7 | 100.0 | 98.3 | 100.0 | 99.7 | 0.0 | 61.1 | 59.0 |
| Google Gemini Flash, newest | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | — | — | — |
| OpenAI GPT mini, newest | 91.7 | 84.4 | 85.0 | 81.7 | 81.0 | 12.4 | 82.8 | 67.6 |

## Coverage at step 5 per notes page

Each cell is the page's coverage at step 5 in percent, then the completion tokens of its calls, retry included, against the function's `max_tokens` of 16384 per call.

| Page | Claude Haiku 5.5 | Claude Sonnet 5.5 | Google Gemini Flash, newest | OpenAI GPT mini, newest |
|---|---|---|---|---|
| 25-notes-ko-print-mild | 100.0 · 1820 tokens | 100.0 · 1058 tokens | 0.0 · 0 tokens | 100.0 · 654 tokens |
| 26-notes-ko-print-harsh | 100.0 · 2263 tokens | 100.0 · 1049 tokens | 0.0 · 0 tokens | 100.0 · 657 tokens |
| 27-notes-ko-handwriting-mild | 100.0 · 2860 tokens | 100.0 · 1291 tokens | 0.0 · 0 tokens | 91.7 · 624 tokens |
| 28-notes-ko-handwriting-harsh | 100.0 · 2274 tokens | 100.0 · 1011 tokens | 0.0 · 0 tokens | 100.0 · 792 tokens |
| 29-notes-en-print-mild | 100.0 · 1529 tokens | 100.0 · 1066 tokens | 0.0 · 0 tokens | 100.0 · 598 tokens |
| 30-notes-en-print-harsh | 100.0 · 1837 tokens | 100.0 · 1037 tokens | 0.0 · 0 tokens | 100.0 · 588 tokens |
| 31-notes-en-handwriting-mild | 100.0 · 1659 tokens | 100.0 · 1072 tokens | 0.0 · 0 tokens | 100.0 · 596 tokens |
| 32-notes-en-handwriting-harsh | 100.0 · 1517 tokens | 100.0 · 874 tokens | 0.0 · 0 tokens | 100.0 · 546 tokens |
| 33-notes-ko-grammar-print-mild | 92.3 · 5416 tokens | 100.0 · 2671 tokens | 0.0 · 0 tokens | 61.5 · 2023 tokens |
| 34-notes-ko-grammar-print-harsh | 80.8 · 4446 tokens | 96.2 · 2560 tokens | 0.0 · 0 tokens | 42.3 · 708 tokens |
| 35-notes-ko-grammar-handwriting-mild | 76.9 · 5683 tokens | 100.0 · 2630 tokens | 0.0 · 0 tokens | 50.0 · 1292 tokens |
| 36-notes-ko-grammar-handwriting-harsh | 84.6 · 7691 tokens | 100.0 · 2649 tokens | 0.0 · 0 tokens | 26.9 · 1068 tokens |

## 2026-10-18 vocabulary run

A later run on 2026-10-18, by the PM, of Claude Haiku 5.5 and Claude Sonnet 5.5 over the 24 vocabulary pages, with the prompt v4 tree. Its figures are as the PM reported them in the review of #185; its spend is in `tools/eval/spend.json`.

| Configuration | Precision | Recall | F1 | Part of speech | Examples | Invented | p50 | p90 | Cost per image |
|---|---|---|---|---|---|---|---|---|---|
| Claude Haiku 5.5 | 99.0 | 99.0 | 99.0 | 100.0 | 100.0 | 0.0 | 5.1 s | 6.2 s | $0.0009 |
| Claude Sonnet 5.5 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 0.0 | 5.7 s | 7.2 s | $0.0161 |

## 2026-10-18 notes runs on prompt v5

Later runs on 2026-10-18, by the PM, over samples 27, 33, 35 and 37 to 40, with prompt v5 (#191). Their figures are as the PM reported them for #192; their spend is in `tools/eval/spend.json`.

| Configuration | Coverage | Unsupported | Invented examples | Cost per image | p50 latency |
|---|---|---|---|---|---|
| Claude Sonnet 5.5 | 78.2 | 22.7 | 0.0 | $0.0229 | 9.2 s |
| Claude Sonnet 5.5 outline, Claude Haiku 5.5 fill | 72.3 | 27.8 | 1.2 | $0.0179 | 16.9 s |
| OpenAI GPT 6.1 Sol | 75.5 | 22.0 | 7.5 | $0.0227 | 29.3 s |
| OpenAI GPT 6 Luna | 67.3 | 20.7 | — | $0.0016 | 24.9 s |
| Google Gemini 4 Argon | — | — | — | — | — |

- The outline-then-fill configuration's cost is $0.0158 for the outline call and $0.0021 for the fill, per image.
- Google Gemini 4 Argon stopped after two model errors, Google's `400 INVALID_ARGUMENT`; neither call was billed.

## Recommendation

- Claude Sonnet 5.5: the cheapest configuration whose vocabulary F1 is within 2 points of the best and whose notes coverage at step 5 is within 5 points of the best.

## Spend

- This run: $1.2692.
- All runs: $1.9944 of the $10.0000 budget, recorded in `tools/eval/spend.json`.
- Corrected on 2026-10-18 (issue #184): OpenRouter's key usage shows this run cost $0.3988. The $0.8704 shown for Google Gemini Flash was the eval's worst-case price for 12 failed calls that reported no usage and were not billed. `tools/eval/spend.json` records the charges.
