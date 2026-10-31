# Extract-cards model eval

Results of `tools/eval/run.ts`: how each candidate configuration extracts cards from the sample set.

- Run on 2026-10-31 with prompt v9 and v10, over 89 images in `tools/eval/samples/`.
- The samples are synthetic: printed and handwritten-style pages rendered and distorted by `tools/eval/generate.py`, not phone photos.
- Vocabulary pages: precision, recall and F1 are means of the per-image values, in percent; a card matches when its front and meaning (its answer, when it has no meaning) equal the ground truth after card key normalization.
- Senses, in percent, over every card whose front matches an entry's after the same normalization: senses P is the share of returned senses equal to one of the entry's in labels and meaning, and senses R the share of the entry's senses so returned.
- Over the matched cards of every image, whose senses pair with the page's in order, in percent and after the same normalization: labels P is the share of returned labels whose text equals one the page prints for that sense, and labels R the share of printed labels so returned; category is the share of those equal labels whose kind and category are the page's too; unprinted labels is the share of the senses the page prints no label for that were given one, which must be 0; examples is the share of returned examples, on the card or a sense, the page prints for the entry; sense examples is the share of the examples printed under a sense that the returned sense holds; extras is the share of printed extras returned with an equal label and text; invented is the share of returned label lists, example lists and extras where the page prints none. A dash means the configuration returned no such field, or the pages printed none.
- Numbered fronts, in percent, over every returned card of the vocabulary pages: the share whose front holds a list's number: a numeral alone, or one opening the front before "." or ")" or in brackets, such as "1. abandon"; it must be 0 (ADR 0128). A dash means no card was returned.
- Notes pages, in percent: coverage is the share of the page's facts that a card covers, its front and answer holding each of the fact's terms after the same normalization, averaged over the images; the facts are the page's rules and exceptions, and its worked examples are not facts. It equals coverage at step 5 in reports before prompt v5, whose cards carry no step. Unsupported is the share of returned cards covering no fact, which also counts a fact the model paraphrased past its terms; invented examples is the share of returned examples the page does not print, a worked example printed inside its rule's line counting as printed. Long answers is the share of returned cards whose answer lists more than 5 items, its parts between commas, middle dots, slashes, semicolons and line breaks, which prompt v6 splits into several cards; a table card's answer, its whole table, is not counted. Bare exceptions is the share of returned cards whose answer names an exception ("예외" or "exception") yet covers no fact, which prompt v7 asks every exception card to avoid by stating what the exception does. Table blanks is the share of the pages' cells to memorise that a table card asks as a blank, one blank holding each of the cell's terms, and cloze blanks the same for the words a cloze card should ask, pooled over the pages that hold any; a dash means no page held any.
- Replies: each call is instructed with the prompt and then the output contract, as the function instructs it. Invalid outputs are the images whose reply was not the schema's or kept no card, so the photo saves none; model errors are the images whose call failed; dropped cards are the cards a reply returned that broke a rule of the output contract (`CARD_RULES` in `supabase/functions/extract-cards/cards.ts`) and were left out, by the rule each broke.
- Latency is per image, one call each; cost per image is the mean of OpenRouter's reported cost, over every image.
- Every reply, its parsed cards or its error body, is kept in `tools/eval/replies/2026-10-31T17-25-14Z/`, which git ignores.

## Models

- Claude Haiku 5.5: `anthropic/claude-haiku-5.5` ($0.1000/M prompt, $0.5000/M completion)

## Replies

| Configuration | Images | Invalid outputs | Model errors | Dropped cards | Dropped by rule |
|---|---|---|---|---|---|
| Claude Haiku 5.5, prompt v9 | 89 | 0 | 0 | 0 | — |
| Claude Haiku 5.5, prompt v10 | 89 | 0 | 0 | 0 | — |

## Vocabulary pages

| Configuration | Precision | Recall | F1 | Senses P | Senses R | Labels P | Labels R | Category | Unprinted labels | Examples | Sense examples | Extras | Invented | Numbered fronts | p50 latency | p90 latency | Cost per image | Total spend |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Claude Haiku 5.5, prompt v9 | 99.7 | 99.7 | 99.7 | 99.8 | 99.8 | 100.0 | 100.0 | 100.0 | 0.0 | 100.0 | 100.0 | 100.0 | 0.0 | 0.0 | 9.9 s | 17.7 s | $0.0047 | $0.4161 |
| Claude Haiku 5.5, prompt v10 | 99.7 | 99.7 | 99.7 | 95.5 | 95.5 | 88.9 | 100.0 | 100.0 | 6.3 | 100.0 | 100.0 | 100.0 | 7.8 | 0.0 | 10.3 s | 17.6 s | $0.0042 | $0.3768 |

## Vocabulary per page

| Page | Configuration | F1 | Senses P | Senses R | Labels P | Labels R | Category | Unprinted labels | Examples | Sense examples | Extras | Numbered fronts |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 01-two-column-en-ko-print | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 02-two-column-en-ko-handwriting | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 03-two-column-en-ko-harsh | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 04-two-column-ja-ko-print | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 05-two-column-ja-ko-handwriting | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 06-two-column-ja-ko-harsh | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 07-bilingual-table-en-ko-print | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 08-bilingual-table-en-ko-handwriting | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 09-bilingual-table-en-ko-harsh | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 10-bilingual-table-ja-ko-print | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 11-bilingual-table-ja-ko-handwriting | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 12-bilingual-table-ja-ko-harsh | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 13-dictionary-en-ko-print | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | — | — | 0.0 |
| 14-dictionary-en-ko-handwriting | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | — | — | 0.0 |
| 15-dictionary-en-ko-harsh | Claude Haiku 5.5, prompt v9 | 87.5 | 87.5 | 87.5 | 100.0 | 100.0 | 100.0 | — | 100.0 | — | — | 0.0 |
| 16-dictionary-ja-ko-print | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 17-dictionary-ja-ko-handwriting | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 18-dictionary-ja-ko-harsh | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 19-glossary-en-ko-print | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 20-glossary-en-ko-handwriting | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 21-glossary-en-ko-harsh | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 22-glossary-ja-ko-print | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 23-glossary-ja-ko-handwriting | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 24-glossary-ja-ko-harsh | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 45-word-book-en-ko-print | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 46-word-book-en-ko-handwriting | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 47-word-book-en-ko-harsh | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 56-word-book-unlabelled-en-ko-print | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | 100.0 | 0.0 |
| 57-word-book-unlabelled-en-ko-handwriting | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | 100.0 | 0.0 |
| 58-word-book-unlabelled-en-ko-harsh | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | 100.0 | 0.0 |
| 59-word-book-examples-en-ko-print | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | 100.0 | — | 0.0 |
| 60-word-book-examples-en-ko-handwriting | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | 100.0 | — | 0.0 |
| 61-word-book-examples-en-ko-harsh | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | 100.0 | — | 0.0 |
| 62-dictionary-ko-print | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 63-dictionary-ko-handwriting | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 64-dictionary-ko-harsh | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 65-word-book-de-ko-print | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 66-word-book-de-ko-handwriting | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 67-word-book-de-ko-harsh | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 88-numbered-list-en-ko-print | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 89-numbered-list-en-ko-harsh | Claude Haiku 5.5, prompt v9 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 01-two-column-en-ko-print | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 02-two-column-en-ko-handwriting | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 03-two-column-en-ko-harsh | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 04-two-column-ja-ko-print | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 05-two-column-ja-ko-handwriting | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 06-two-column-ja-ko-harsh | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 07-bilingual-table-en-ko-print | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 08-bilingual-table-en-ko-handwriting | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 09-bilingual-table-en-ko-harsh | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 10-bilingual-table-ja-ko-print | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 11-bilingual-table-ja-ko-handwriting | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 12-bilingual-table-ja-ko-harsh | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 13-dictionary-en-ko-print | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | — | — | 0.0 |
| 14-dictionary-en-ko-handwriting | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | — | — | 0.0 |
| 15-dictionary-en-ko-harsh | Claude Haiku 5.5, prompt v10 | 87.5 | 87.5 | 87.5 | 100.0 | 100.0 | 100.0 | — | 100.0 | — | — | 0.0 |
| 16-dictionary-ja-ko-print | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 17-dictionary-ja-ko-handwriting | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 18-dictionary-ja-ko-harsh | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 19-glossary-en-ko-print | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 20-glossary-en-ko-handwriting | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 21-glossary-en-ko-harsh | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 22-glossary-ja-ko-print | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 23-glossary-ja-ko-handwriting | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 24-glossary-ja-ko-harsh | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 45-word-book-en-ko-print | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 46-word-book-en-ko-handwriting | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 47-word-book-en-ko-harsh | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 56-word-book-unlabelled-en-ko-print | Claude Haiku 5.5, prompt v10 | 100.0 | 46.2 | 46.2 | 0.0 | — | — | 53.8 | — | — | 100.0 | 0.0 |
| 57-word-book-unlabelled-en-ko-handwriting | Claude Haiku 5.5, prompt v10 | 100.0 | 46.2 | 46.2 | 0.0 | — | — | 53.8 | — | — | 100.0 | 0.0 |
| 58-word-book-unlabelled-en-ko-harsh | Claude Haiku 5.5, prompt v10 | 100.0 | 46.2 | 46.2 | 0.0 | — | — | 53.8 | — | — | 100.0 | 0.0 |
| 59-word-book-examples-en-ko-print | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | 100.0 | — | 0.0 |
| 60-word-book-examples-en-ko-handwriting | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | 100.0 | — | 0.0 |
| 61-word-book-examples-en-ko-harsh | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | 100.0 | 100.0 | — | 0.0 |
| 62-dictionary-ko-print | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 63-dictionary-ko-handwriting | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 64-dictionary-ko-harsh | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | — | 0.0 |
| 65-word-book-de-ko-print | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 66-word-book-de-ko-handwriting | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 67-word-book-de-ko-harsh | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | — | — | — | 100.0 | 0.0 |
| 88-numbered-list-en-ko-print | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |
| 89-numbered-list-en-ko-harsh | Claude Haiku 5.5, prompt v10 | 100.0 | 100.0 | 100.0 | — | — | — | 0.0 | — | — | — | 0.0 |

## Notes pages

| Configuration | Coverage | Unsupported | Invented examples | Long answers | Bare exceptions | Table blanks | Cloze blanks |
|---|---|---|---|---|---|---|---|
| Claude Haiku 5.5, prompt v9 | 92.3 | 9.7 | 4.2 | 0.0 | 0.0 | 95.8 | 100.0 |
| Claude Haiku 5.5, prompt v10 | 94.1 | 11.3 | 5.6 | 0.9 | 0.0 | 70.8 | 0.0 |

## Coverage per notes page

Each cell is the page's coverage in percent, then the completion tokens of its call, against the function's `max_tokens` of 16384 per call.

| Page | Claude Haiku 5.5, prompt v9 | Claude Haiku 5.5, prompt v10 |
|---|---|---|
| 25-notes-ko-print-mild | 100.0 · 2606 tokens | 100.0 · 2720 tokens |
| 26-notes-ko-print-harsh | 100.0 · 3650 tokens | 100.0 · 2914 tokens |
| 27-notes-ko-handwriting-mild | 100.0 · 3053 tokens | 100.0 · 3401 tokens |
| 28-notes-ko-handwriting-harsh | 100.0 · 2845 tokens | 100.0 · 2775 tokens |
| 29-notes-en-print-mild | 100.0 · 1932 tokens | 100.0 · 1961 tokens |
| 30-notes-en-print-harsh | 100.0 · 2072 tokens | 100.0 · 1670 tokens |
| 31-notes-en-handwriting-mild | 100.0 · 1921 tokens | 100.0 · 1992 tokens |
| 32-notes-en-handwriting-harsh | 100.0 · 1984 tokens | 100.0 · 2024 tokens |
| 33-notes-ko-grammar-print-mild | 95.2 · 7230 tokens | 95.2 · 5230 tokens |
| 34-notes-ko-grammar-print-harsh | 90.5 · 6527 tokens | 71.4 · 6482 tokens |
| 35-notes-ko-grammar-handwriting-mild | 95.2 · 11156 tokens | 81.0 · 6171 tokens |
| 36-notes-ko-grammar-handwriting-harsh | 85.7 · 9970 tokens | 66.7 · 7668 tokens |
| 37-notes-ko-auxiliary-print-mild | 77.8 · 3126 tokens | 77.8 · 3055 tokens |
| 38-notes-ko-auxiliary-print-harsh | 77.8 · 4564 tokens | 77.8 · 3034 tokens |
| 39-notes-ko-auxiliary-handwriting-mild | 77.8 · 3562 tokens | 88.9 · 2714 tokens |
| 40-notes-ko-auxiliary-handwriting-harsh | 55.6 · 5383 tokens | 77.8 · 5468 tokens |
| 41-notes-ko-numerals-print-mild | 100.0 · 3808 tokens | 100.0 · 4918 tokens |
| 42-notes-ko-numerals-print-harsh | 90.9 · 4753 tokens | 90.9 · 3234 tokens |
| 43-notes-ko-numerals-handwriting-mild | 100.0 · 5953 tokens | 100.0 · 3256 tokens |
| 44-notes-ko-numerals-handwriting-harsh | 100.0 · 4022 tokens | 90.9 · 3798 tokens |
| 48-notes-ko-honorifics-print-mild | 100.0 · 2539 tokens | 100.0 · 2094 tokens |
| 49-notes-ko-honorifics-print-harsh | 100.0 · 3048 tokens | 100.0 · 2531 tokens |
| 50-notes-ko-honorifics-handwriting-mild | 100.0 · 3255 tokens | 100.0 · 4220 tokens |
| 51-notes-ko-honorifics-handwriting-harsh | 90.0 · 3050 tokens | 90.0 · 4493 tokens |
| 52-notes-ko-components-print-mild | 83.3 · 2307 tokens | 100.0 · 1489 tokens |
| 53-notes-ko-components-print-harsh | 83.3 · 2217 tokens | 83.3 · 2000 tokens |
| 54-notes-ko-components-handwriting-mild | 83.3 · 2039 tokens | 83.3 · 1588 tokens |
| 55-notes-ko-components-handwriting-harsh | 83.3 · 2012 tokens | 83.3 · 1904 tokens |
| 68-structure-ko-states-print-mild | 95.2 · 2762 tokens | 95.2 · 2613 tokens |
| 69-structure-ko-states-print-harsh | 85.7 · 3270 tokens | 85.7 · 3729 tokens |
| 70-structure-ko-states-handwriting-mild | 95.2 · 2921 tokens | 95.2 · 3342 tokens |
| 71-structure-ko-states-handwriting-harsh | 14.3 · 2781 tokens | 90.5 · 2867 tokens |
| 72-structure-ko-respiration-print-mild | 92.3 · 3927 tokens | 100.0 · 3050 tokens |
| 73-structure-ko-respiration-print-harsh | 92.3 · 2295 tokens | 100.0 · 2558 tokens |
| 74-structure-ko-respiration-handwriting-mild | 100.0 · 2716 tokens | 100.0 · 2379 tokens |
| 75-structure-ko-respiration-handwriting-harsh | 100.0 · 2560 tokens | 100.0 · 2207 tokens |
| 76-structure-en-markets-print-mild | 100.0 · 1599 tokens | 100.0 · 1778 tokens |
| 77-structure-en-markets-print-harsh | 93.3 · 2184 tokens | 100.0 · 1580 tokens |
| 78-structure-en-markets-handwriting-mild | 100.0 · 1864 tokens | 100.0 · 1703 tokens |
| 79-structure-en-markets-handwriting-harsh | 100.0 · 1868 tokens | 100.0 · 1793 tokens |
| 80-structure-ko-sentences-print-mild | 100.0 · 1818 tokens | 100.0 · 1538 tokens |
| 81-structure-ko-sentences-print-harsh | 100.0 · 1658 tokens | 100.0 · 1580 tokens |
| 82-structure-ko-sentences-handwriting-mild | 100.0 · 1812 tokens | 100.0 · 1812 tokens |
| 83-structure-ko-sentences-handwriting-harsh | 90.0 · 2008 tokens | 90.0 · 1626 tokens |
| 84-structure-en-organelles-print-mild | 100.0 · 1614 tokens | 100.0 · 1752 tokens |
| 85-structure-en-organelles-print-harsh | 100.0 · 1974 tokens | 100.0 · 2697 tokens |
| 86-structure-en-organelles-handwriting-mild | 100.0 · 1838 tokens | 100.0 · 2365 tokens |
| 87-structure-en-organelles-handwriting-harsh | 100.0 · 1731 tokens | 100.0 · 1891 tokens |

## Recommendation

- Claude Haiku 5.5, prompt v10: the cheapest configuration whose vocabulary F1 is within 2 points of the best and whose notes coverage is within 5 points of the best.

## Spend

- This run: $0.7930.
- All runs: $14.8113 of the $110.0000 budget, recorded in `tools/eval/spend.json`.
