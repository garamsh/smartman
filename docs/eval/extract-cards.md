# Extract-cards model eval

Results of `tools/eval/run.ts`: how each candidate configuration extracts cards from the sample set.

- Run on 2026-10-28 with prompt version 3, over 87 images in `tools/eval/samples/`.
- The samples are synthetic: printed and handwritten-style pages rendered and distorted by `tools/eval/generate.py`, not phone photos.
- Vocabulary pages: precision, recall and F1 are means of the per-image values, in percent; a card matches when its front and meaning (its answer, when it has no meaning) equal the ground truth after card key normalization.
- Senses, in percent, over every card whose front matches an entry's after the same normalization: senses P is the share of returned senses equal to one of the entry's in labels and meaning, and senses R the share of the entry's senses so returned.
- Over the matched cards of every image, whose senses pair with the page's in order, in percent and after the same normalization: labels P is the share of returned labels whose text equals one the page prints for that sense, and labels R the share of printed labels so returned; category is the share of those equal labels whose kind and category are the page's too; unprinted labels is the share of the senses the page prints no label for that were given one, which must be 0; examples is the share of returned examples, on the card or a sense, the page prints for the entry; sense examples is the share of the examples printed under a sense that the returned sense holds; extras is the share of printed extras returned with an equal label and text; invented is the share of returned label lists, example lists and extras where the page prints none. A dash means the configuration returned no such field, or the pages printed none.
- Notes pages, in percent: coverage is the share of the page's facts that a card covers, its front and answer holding each of the fact's terms after the same normalization, averaged over the images; the facts are the page's rules and exceptions, and its worked examples are not facts. It equals coverage at step 5 in reports before prompt v5, whose cards carry no step. Unsupported is the share of returned cards covering no fact, which also counts a fact the model paraphrased past its terms; invented examples is the share of returned examples the page does not print, a worked example printed inside its rule's line counting as printed. Long answers is the share of returned cards whose answer lists more than 5 items, its parts between commas, middle dots, slashes, semicolons and line breaks, which prompt v6 splits into several cards; a table card's answer, its whole table, is not counted. Bare exceptions is the share of returned cards whose answer names an exception ("예외" or "exception") yet covers no fact, which prompt v7 asks every exception card to avoid by stating what the exception does. Table blanks is the share of the pages' cells to memorise that a table card asks as a blank, one blank holding each of the cell's terms, and cloze blanks the same for the words a cloze card should ask, pooled over the pages that hold any; a dash means no page held any.
- Latency is per image, one call each; cost per image is the mean of OpenRouter's reported cost, over every image.
- Every reply, its parsed cards or its error body, is kept in `tools/eval/replies/2026-10-28T15-26-20Z/`, which git ignores.

## Models

- Claude Haiku 5.5: `anthropic/claude-haiku-5.5` ($0.1000/M prompt, $0.5000/M completion)

## Vocabulary pages

| Configuration | Precision | Recall | F1 | Senses P | Senses R | Labels P | Labels R | Category | Unprinted labels | Examples | Sense examples | Extras | Invented | p50 latency | p90 latency | Cost per image | Total spend |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Claude Haiku 5.5 | 10.3 | 10.3 | 10.3 | 57.9 | 57.9 | 60.0 | 72.7 | 100.0 | 53.8 | 100.0 | 100.0 | 100.0 | 15.6 | 9.9 s | 15.6 s | $0.0036 | $0.3099 |

## Vocabulary per page

| Page | Configuration | F1 | Senses P | Senses R | Labels P | Labels R | Category | Unprinted labels | Examples | Sense examples | Extras |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 01-two-column-en-ko-print | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 02-two-column-en-ko-handwriting | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 03-two-column-en-ko-harsh | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 04-two-column-ja-ko-print | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 05-two-column-ja-ko-handwriting | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 06-two-column-ja-ko-harsh | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 07-bilingual-table-en-ko-print | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 08-bilingual-table-en-ko-handwriting | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 09-bilingual-table-en-ko-harsh | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 10-bilingual-table-ja-ko-print | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 11-bilingual-table-ja-ko-handwriting | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 12-bilingual-table-ja-ko-harsh | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 13-dictionary-en-ko-print | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 14-dictionary-en-ko-handwriting | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 15-dictionary-en-ko-harsh | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 16-dictionary-ja-ko-print | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 17-dictionary-ja-ko-handwriting | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 18-dictionary-ja-ko-harsh | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 19-glossary-en-ko-print | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 20-glossary-en-ko-handwriting | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 21-glossary-en-ko-harsh | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 22-glossary-ja-ko-print | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 23-glossary-ja-ko-handwriting | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 24-glossary-ja-ko-harsh | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 45-word-book-en-ko-print | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 46-word-book-en-ko-handwriting | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 47-word-book-en-ko-harsh | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 56-word-book-unlabelled-en-ko-print | Claude Haiku 5.5 | 100.0 | 46.2 | 46.2 | 0.0 | — | — | 53.8 | — | — | 100.0 |
| 57-word-book-unlabelled-en-ko-handwriting | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 58-word-book-unlabelled-en-ko-harsh | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 59-word-book-examples-en-ko-print | Claude Haiku 5.5 | 100.0 | 0.0 | 0.0 | 0.0 | 0.0 | — | — | 100.0 | 100.0 | — |
| 60-word-book-examples-en-ko-handwriting | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 61-word-book-examples-en-ko-harsh | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 62-dictionary-ko-print | Claude Haiku 5.5 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — |
| 63-dictionary-ko-handwriting | Claude Haiku 5.5 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — |
| 64-dictionary-ko-harsh | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 65-word-book-de-ko-print | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 66-word-book-de-ko-handwriting | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |
| 67-word-book-de-ko-harsh | Claude Haiku 5.5 | 0.0 | — | — | — | — | — | — | — | — | — |

## Notes pages

| Configuration | Coverage | Unsupported | Invented examples | Long answers | Bare exceptions | Table blanks | Cloze blanks |
|---|---|---|---|---|---|---|---|
| Claude Haiku 5.5 | 33.9 | 16.2 | 22.5 | 0.8 | 0.0 | 0.0 | 0.0 |

## Coverage per notes page

Each cell is the page's coverage in percent, then the completion tokens of its call, against the function's `max_tokens` of 16384 per call.

| Page | Claude Haiku 5.5 |
|---|---|
| 25-notes-ko-print-mild | 0.0 · 2338 tokens |
| 26-notes-ko-print-harsh | 100.0 · 2823 tokens |
| 27-notes-ko-handwriting-mild | 100.0 · 2740 tokens |
| 28-notes-ko-handwriting-harsh | 100.0 · 2742 tokens |
| 29-notes-en-print-mild | 100.0 · 1236 tokens |
| 30-notes-en-print-harsh | 0.0 · 1826 tokens |
| 31-notes-en-handwriting-mild | 0.0 · 1972 tokens |
| 32-notes-en-handwriting-harsh | 0.0 · 1923 tokens |
| 33-notes-ko-grammar-print-mild | 71.4 · 5304 tokens |
| 34-notes-ko-grammar-print-harsh | 61.9 · 4173 tokens |
| 35-notes-ko-grammar-handwriting-mild | 76.2 · 5145 tokens |
| 36-notes-ko-grammar-handwriting-harsh | 0.0 · 5539 tokens |
| 37-notes-ko-auxiliary-print-mild | 55.6 · 3320 tokens |
| 38-notes-ko-auxiliary-print-harsh | 55.6 · 2847 tokens |
| 39-notes-ko-auxiliary-handwriting-mild | 66.7 · 2693 tokens |
| 40-notes-ko-auxiliary-handwriting-harsh | 0.0 · 4072 tokens |
| 41-notes-ko-numerals-print-mild | 0.0 · 3120 tokens |
| 42-notes-ko-numerals-print-harsh | 0.0 · 2908 tokens |
| 43-notes-ko-numerals-handwriting-mild | 0.0 · 2559 tokens |
| 44-notes-ko-numerals-handwriting-harsh | 0.0 · 3193 tokens |
| 48-notes-ko-honorifics-print-mild | 0.0 · 3758 tokens |
| 49-notes-ko-honorifics-print-harsh | 0.0 · 2415 tokens |
| 50-notes-ko-honorifics-handwriting-mild | 0.0 · 2777 tokens |
| 51-notes-ko-honorifics-handwriting-harsh | 0.0 · 3305 tokens |
| 52-notes-ko-components-print-mild | 83.3 · 1969 tokens |
| 53-notes-ko-components-print-harsh | 0.0 · 2011 tokens |
| 54-notes-ko-components-handwriting-mild | 83.3 · 1741 tokens |
| 55-notes-ko-components-handwriting-harsh | 0.0 · 935 tokens |
| 68-structure-ko-states-print-mild | 81.0 · 4025 tokens |
| 69-structure-ko-states-print-harsh | 0.0 · 2991 tokens |
| 70-structure-ko-states-handwriting-mild | 0.0 · 2833 tokens |
| 71-structure-ko-states-handwriting-harsh | 81.0 · 4771 tokens |
| 72-structure-ko-respiration-print-mild | 0.0 · 3429 tokens |
| 73-structure-ko-respiration-print-harsh | 0.0 · 2312 tokens |
| 74-structure-ko-respiration-handwriting-mild | 100.0 · 2659 tokens |
| 75-structure-ko-respiration-handwriting-harsh | 100.0 · 2703 tokens |
| 76-structure-en-markets-print-mild | 0.0 · 2156 tokens |
| 77-structure-en-markets-print-harsh | 0.0 · 2866 tokens |
| 78-structure-en-markets-handwriting-mild | 100.0 · 2309 tokens |
| 79-structure-en-markets-handwriting-harsh | 0.0 · 2614 tokens |
| 80-structure-ko-sentences-print-mild | 60.0 · 1255 tokens |
| 81-structure-ko-sentences-print-harsh | 0.0 · 1230 tokens |
| 82-structure-ko-sentences-handwriting-mild | 0.0 · 1335 tokens |
| 83-structure-ko-sentences-handwriting-harsh | 60.0 · 1420 tokens |
| 84-structure-en-organelles-print-mild | 90.9 · 1613 tokens |
| 85-structure-en-organelles-print-harsh | 0.0 · 1649 tokens |
| 86-structure-en-organelles-handwriting-mild | 0.0 · 1688 tokens |
| 87-structure-en-organelles-handwriting-harsh | 0.0 · 493 tokens |

## Recommendation

- Claude Haiku 5.5: the cheapest configuration whose vocabulary F1 is within 2 points of the best and whose notes coverage is within 5 points of the best.

## Spend

- This run: $0.3099.
- All runs: $12.9732 of the $110.0000 budget, recorded in `tools/eval/spend.json`.
