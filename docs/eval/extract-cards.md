# Extract-cards model eval

Results of `tools/eval/run.ts`: how each candidate configuration extracts cards from the sample set.

- Run on 2026-11-01 with prompt v9, over 90 images in `tools/eval/samples/`.
- The samples are synthetic: printed and handwritten-style pages rendered and distorted by `tools/eval/generate.py`, not phone photos.
- Vocabulary pages: precision, recall and F1 are means of the per-image values, in percent; a card matches when its front and meaning (its answer, when it has no meaning) equal the ground truth after card key normalization.
- Senses, in percent, over every card whose front matches an entry's after the same normalization: senses P is the share of returned senses equal to one of the entry's in labels and meaning, and senses R the share of the entry's senses so returned.
- Over the matched cards of every image, whose senses pair with the page's in order, in percent and after the same normalization: labels P is the share of returned labels whose text equals one the page prints for that sense, and labels R the share of printed labels so returned; category is the share of those equal labels whose kind and category are the page's too; unprinted labels is the share of the senses the page prints no label for that were given one, which must be 0; examples is the share of returned examples, on the card or a sense, the page prints for the entry; sense examples is the share of the examples printed under a sense that the returned sense holds; extras is the share of printed extras returned with an equal label and text; invented is the share of returned label lists, example lists and extras where the page prints none. A dash means the configuration returned no such field, or the pages printed none.
- Numbered fronts, in percent, over every returned card of the vocabulary pages: the share whose front holds a list's number: a numeral alone, or one opening the front before "." or ")" or in brackets, such as "1. abandon"; it must be 0 (ADR 0128). A dash means no card was returned.
- Notes pages, in percent: coverage is the share of the page's facts that a card covers, its front and answer holding each of the fact's terms after the same normalization, averaged over the images; the facts are the page's rules and exceptions, and its worked examples are not facts. It equals coverage at step 5 in reports before prompt v5, whose cards carry no step. Unsupported is the share of returned cards covering no fact, which also counts a fact the model paraphrased past its terms; invented examples is the share of returned examples the page does not print, a worked example printed inside its rule's line counting as printed. Long answers is the share of returned cards whose answer lists more than 5 items, its parts between commas, middle dots, slashes, semicolons and line breaks, which prompt v6 splits into several cards; a table card's answer, its whole table, is not counted. Bare exceptions is the share of returned cards whose answer names an exception ("예외" or "exception") yet covers no fact, which prompt v7 asks every exception card to avoid by stating what the exception does. Table blanks is the share of the pages' cells to memorise that a table card asks as a blank, one blank holding each of the cell's terms, and cloze blanks the same for the words a cloze card should ask, pooled over the pages that hold any; a dash means no page held any.
- Replies: each call is instructed with the prompt and then the output contract, as the function instructs it. Invalid outputs are the images whose reply was not the schema's or kept no card, so the photo saves none; model errors are the images whose call failed; dropped cards are the cards a reply returned that broke a rule of the output contract (`CARD_RULES` in `supabase/functions/extract-cards/cards.ts`) and were left out, by the rule each broke. Cards are the cards kept over every image, and cut replies the images whose cards came from a reply cut at the output cap, the cards its JSON completed (ADR 0135).
- Latency is per image, the sum of its calls; cost per image is the mean of OpenRouter's reported cost, over every image.
- Every reply, its parsed cards or its error body, is kept in `tools/eval/replies/2026-11-01T13-02-15Z/`, which git ignores.

## Models

- Claude Haiku 5.5: `anthropic/claude-haiku-5.5` ($0.1000/M prompt, $0.5000/M completion)

## Replies

| Configuration | Images | Cards | Cut replies | Invalid outputs | Model errors | Dropped cards | Dropped by rule |
|---|---|---|---|---|---|---|---|
| Claude Haiku 5.5, today | 90 | 859 | 0 | 0 | 1 | 1 | `cloze_blanks` 1 |
| Claude Haiku 5.5, lean | 90 | 851 | 0 | 3 | 0 | 6 | `vocabulary_senses` 6 |

## Vocabulary pages

| Configuration | Precision | Recall | F1 | Senses P | Senses R | Labels P | Labels R | Category | Unprinted labels | Examples | Sense examples | Extras | Invented | Numbered fronts | p50 latency | p90 latency | Cost per image | Total spend |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Claude Haiku 5.5, today | 99.4 | 99.4 | 99.4 | 99.7 | 99.7 | 100.0 | 100.0 | 100.0 | 0.0 | 100.0 | 100.0 | 100.0 | 0.0 | 0.0 | 8.3 s | 21.5 s | $0.0024 | $0.2123 |
| Claude Haiku 5.5, lean | 92.9 | 92.9 | 92.9 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 0.0 | 100.0 | 100.0 | 100.0 | 0.0 | 0.0 | 7.5 s | 15.5 s | $0.0022 | $0.1992 |

## Vocabulary per page

| Page | Configuration | F1 | Senses P | Senses R | Labels P | Labels R | Category | Unprinted labels | Examples | Sense examples | Extras | Numbered fronts |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 01-two-column-en-ko-print | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 02-two-column-en-ko-handwriting | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 03-two-column-en-ko-harsh | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 04-two-column-ja-ko-print | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 05-two-column-ja-ko-handwriting | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 06-two-column-ja-ko-harsh | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 07-bilingual-table-en-ko-print | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 08-bilingual-table-en-ko-handwriting | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 09-bilingual-table-en-ko-harsh | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 10-bilingual-table-ja-ko-print | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 11-bilingual-table-ja-ko-handwriting | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 12-bilingual-table-ja-ko-harsh | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 13-dictionary-en-ko-print | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | — | — | 0.0 |
| 14-dictionary-en-ko-handwriting | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | — | — | 0.0 |
| 15-dictionary-en-ko-harsh | Claude Haiku 5.5, today | 75.0 | 75.0 | 75.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | — | — | 0.0 |
| 16-dictionary-ja-ko-print | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 17-dictionary-ja-ko-handwriting | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 18-dictionary-ja-ko-harsh | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 19-glossary-en-ko-print | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 20-glossary-en-ko-handwriting | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 21-glossary-en-ko-harsh | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 22-glossary-ja-ko-print | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 23-glossary-ja-ko-handwriting | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 24-glossary-ja-ko-harsh | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 45-word-book-en-ko-print | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 46-word-book-en-ko-handwriting | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 47-word-book-en-ko-harsh | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 56-word-book-unlabelled-en-ko-print | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | 100.0 | 0.0 |
| 57-word-book-unlabelled-en-ko-handwriting | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | 100.0 | 0.0 |
| 58-word-book-unlabelled-en-ko-harsh | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | 100.0 | 0.0 |
| 59-word-book-examples-en-ko-print | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | 100.0 | — | 0.0 |
| 60-word-book-examples-en-ko-handwriting | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | 100.0 | — | 0.0 |
| 61-word-book-examples-en-ko-harsh | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | 100.0 | — | 0.0 |
| 62-dictionary-ko-print | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 63-dictionary-ko-handwriting | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 64-dictionary-ko-harsh | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 65-word-book-de-ko-print | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 66-word-book-de-ko-handwriting | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 67-word-book-de-ko-harsh | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 88-numbered-list-en-ko-print | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 89-numbered-list-en-ko-harsh | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 90-dense-list-fr-ko-print | Claude Haiku 5.5, today | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 01-two-column-en-ko-print | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 02-two-column-en-ko-handwriting | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 03-two-column-en-ko-harsh | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 04-two-column-ja-ko-print | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 05-two-column-ja-ko-handwriting | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 06-two-column-ja-ko-harsh | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 07-bilingual-table-en-ko-print | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 08-bilingual-table-en-ko-handwriting | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 09-bilingual-table-en-ko-harsh | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 10-bilingual-table-ja-ko-print | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 11-bilingual-table-ja-ko-handwriting | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 12-bilingual-table-ja-ko-harsh | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 13-dictionary-en-ko-print | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | — | — | 0.0 |
| 14-dictionary-en-ko-handwriting | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | — | — | 0.0 |
| 15-dictionary-en-ko-harsh | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | — | — | 0.0 |
| 16-dictionary-ja-ko-print | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 17-dictionary-ja-ko-handwriting | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 18-dictionary-ja-ko-harsh | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 19-glossary-en-ko-print | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 20-glossary-en-ko-handwriting | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 21-glossary-en-ko-harsh | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 22-glossary-ja-ko-print | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 23-glossary-ja-ko-handwriting | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 24-glossary-ja-ko-harsh | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 45-word-book-en-ko-print | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 46-word-book-en-ko-handwriting | Claude Haiku 5.5, lean | 0.0 | — | — | — | — | — | — | — | — | — | — |
| 47-word-book-en-ko-harsh | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 56-word-book-unlabelled-en-ko-print | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | 100.0 | 0.0 |
| 57-word-book-unlabelled-en-ko-handwriting | Claude Haiku 5.5, lean | 0.0 | — | — | — | — | — | — | — | — | — | — |
| 58-word-book-unlabelled-en-ko-harsh | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | 100.0 | 0.0 |
| 59-word-book-examples-en-ko-print | Claude Haiku 5.5, lean | 0.0 | — | — | — | — | — | — | — | — | — | — |
| 60-word-book-examples-en-ko-handwriting | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | 100.0 | — | 0.0 |
| 61-word-book-examples-en-ko-harsh | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | 100.0 | — | 0.0 |
| 62-dictionary-ko-print | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 63-dictionary-ko-handwriting | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 64-dictionary-ko-harsh | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 65-word-book-de-ko-print | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 66-word-book-de-ko-handwriting | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 67-word-book-de-ko-harsh | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 88-numbered-list-en-ko-print | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 89-numbered-list-en-ko-harsh | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 90-dense-list-fr-ko-print | Claude Haiku 5.5, lean | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |

## Notes pages

| Configuration | Coverage | Unsupported | Invented examples | Long answers | Bare exceptions | Table blanks | Cloze blanks |
|---|---|---|---|---|---|---|---|
| Claude Haiku 5.5, today | 92.3 | 9.3 | 2.6 | 0.3 | 0.0 | 95.8 | 100.0 |
| Claude Haiku 5.5, lean | 94.7 | 8.8 | 3.5 | 0.0 | 0.0 | 100.0 | 100.0 |

## Coverage per notes page

Each cell is the page's coverage in percent, then the completion tokens of its call, against the function's `max_tokens` of 16384 per call.

| Page | Claude Haiku 5.5, today | Claude Haiku 5.5, lean |
|---|---|---|
| 25-notes-ko-print-mild | 100.0 · 2247 tokens | 100.0 · 2061 tokens |
| 26-notes-ko-print-harsh | 100.0 · 3138 tokens | 100.0 · 2968 tokens |
| 27-notes-ko-handwriting-mild | 100.0 · 2976 tokens | 100.0 · 2528 tokens |
| 28-notes-ko-handwriting-harsh | 100.0 · 2778 tokens | 100.0 · 2605 tokens |
| 29-notes-en-print-mild | 100.0 · 1974 tokens | 100.0 · 1675 tokens |
| 30-notes-en-print-harsh | 100.0 · 1700 tokens | 100.0 · 1575 tokens |
| 31-notes-en-handwriting-mild | 100.0 · 2157 tokens | 100.0 · 1550 tokens |
| 32-notes-en-handwriting-harsh | 100.0 · 1760 tokens | 100.0 · 1713 tokens |
| 33-notes-ko-grammar-print-mild | 95.2 · 5977 tokens | 95.2 · 7000 tokens |
| 34-notes-ko-grammar-print-harsh | 90.5 · 8804 tokens | 85.7 · 7244 tokens |
| 35-notes-ko-grammar-handwriting-mild | 95.2 · 8243 tokens | 100.0 · 9487 tokens |
| 36-notes-ko-grammar-handwriting-harsh | 85.7 · 10033 tokens | 90.5 · 11684 tokens |
| 37-notes-ko-auxiliary-print-mild | 66.7 · 2695 tokens | 77.8 · 2908 tokens |
| 38-notes-ko-auxiliary-print-harsh | 77.8 · 6511 tokens | 88.9 · 3618 tokens |
| 39-notes-ko-auxiliary-handwriting-mild | 88.9 · 3563 tokens | 77.8 · 2971 tokens |
| 40-notes-ko-auxiliary-handwriting-harsh | 77.8 · 5095 tokens | 77.8 · 5672 tokens |
| 41-notes-ko-numerals-print-mild | 0.0 · 0 tokens | 100.0 · 4068 tokens |
| 42-notes-ko-numerals-print-harsh | 90.9 · 4578 tokens | 90.9 · 3689 tokens |
| 43-notes-ko-numerals-handwriting-mild | 90.9 · 4863 tokens | 90.9 · 2539 tokens |
| 44-notes-ko-numerals-handwriting-harsh | 100.0 · 3688 tokens | 90.9 · 3145 tokens |
| 48-notes-ko-honorifics-print-mild | 100.0 · 2393 tokens | 100.0 · 1898 tokens |
| 49-notes-ko-honorifics-print-harsh | 100.0 · 2979 tokens | 100.0 · 2593 tokens |
| 50-notes-ko-honorifics-handwriting-mild | 100.0 · 4136 tokens | 100.0 · 3413 tokens |
| 51-notes-ko-honorifics-handwriting-harsh | 90.0 · 3018 tokens | 100.0 · 3476 tokens |
| 52-notes-ko-components-print-mild | 100.0 · 2241 tokens | 83.3 · 1760 tokens |
| 53-notes-ko-components-print-harsh | 66.7 · 2087 tokens | 83.3 · 1773 tokens |
| 54-notes-ko-components-handwriting-mild | 83.3 · 2023 tokens | 83.3 · 1748 tokens |
| 55-notes-ko-components-handwriting-harsh | 100.0 · 2502 tokens | 100.0 · 2576 tokens |
| 68-structure-ko-states-print-mild | 95.2 · 2950 tokens | 95.2 · 2619 tokens |
| 69-structure-ko-states-print-harsh | 85.7 · 2496 tokens | 85.7 · 2271 tokens |
| 70-structure-ko-states-handwriting-mild | 90.5 · 3012 tokens | 90.5 · 3022 tokens |
| 71-structure-ko-states-handwriting-harsh | 85.7 · 4708 tokens | 85.7 · 3276 tokens |
| 72-structure-ko-respiration-print-mild | 92.3 · 4137 tokens | 100.0 · 2757 tokens |
| 73-structure-ko-respiration-print-harsh | 100.0 · 1992 tokens | 92.3 · 2178 tokens |
| 74-structure-ko-respiration-handwriting-mild | 92.3 · 2786 tokens | 100.0 · 2339 tokens |
| 75-structure-ko-respiration-handwriting-harsh | 100.0 · 2681 tokens | 100.0 · 2722 tokens |
| 76-structure-en-markets-print-mild | 100.0 · 2071 tokens | 100.0 · 2289 tokens |
| 77-structure-en-markets-print-harsh | 100.0 · 1600 tokens | 100.0 · 2171 tokens |
| 78-structure-en-markets-handwriting-mild | 100.0 · 1749 tokens | 100.0 · 1724 tokens |
| 79-structure-en-markets-handwriting-harsh | 100.0 · 1817 tokens | 100.0 · 1720 tokens |
| 80-structure-ko-sentences-print-mild | 100.0 · 1722 tokens | 100.0 · 2220 tokens |
| 81-structure-ko-sentences-print-harsh | 100.0 · 1746 tokens | 100.0 · 1606 tokens |
| 82-structure-ko-sentences-handwriting-mild | 100.0 · 1721 tokens | 100.0 · 1861 tokens |
| 83-structure-ko-sentences-handwriting-harsh | 90.0 · 2211 tokens | 80.0 · 2376 tokens |
| 84-structure-en-organelles-print-mild | 100.0 · 1928 tokens | 100.0 · 1676 tokens |
| 85-structure-en-organelles-print-harsh | 100.0 · 2662 tokens | 100.0 · 2278 tokens |
| 86-structure-en-organelles-handwriting-mild | 100.0 · 1703 tokens | 100.0 · 1652 tokens |
| 87-structure-en-organelles-handwriting-harsh | 100.0 · 1518 tokens | 100.0 · 1524 tokens |

## Recommendation

- Claude Haiku 5.5, today: the cheapest configuration whose vocabulary F1 is within 2 points of the best and whose notes coverage is within 5 points of the best.

## Spend

- This run: $0.4115.
- All runs: $15.2935 of the $110.0000 budget, recorded in `tools/eval/spend.json`.
