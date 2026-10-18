# ADR 0059: Eval an outline-then-fill configuration, a strong model listing the page's items and a small model making the cards

> Status: accepted
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #189 aims to cut the cost of a photo on Claude Sonnet 5.5 without losing what Sonnet alone catches on real notes pages, such as the writer's handwritten additions.
- The PM's 2026-10-18 measurements of prompt v4, recorded in #189:
  - **Sonnet:** coverage 88.8, at $0.0367 per image.
  - **Claude Haiku 5.5:** coverage 82.1, at $0.0042 per image.
  - On the owner's page, Sonnet's output cost about $0.020 and its input about $0.014.
- #189 asks the eval to try two calls:
  - an outline call, on a strong model, returning only the page's items to memorise, each a topic, a name and a short gist;
  - a fill call, on a small model, turning the image and the outline into cards.
  The outline is far shorter than the cards, so the strong model writes little, and the small model writes the cards. #189 asks for no function change until the PM reads the numbers.
- [ADR 0058](0058-stop-asking-the-model-for-a-short-form-and-a-step-with-prompt-v5-and-add-a-notes-sample-with-the-writer-s-additions.md) slims the card output with prompt v5, which this configuration's fill call uses.
- Alternatives considered:
  - **A second function, or a mode of `extract-cards`.** Merging deploys the function. A pipeline nobody has measured would reach production before its numbers exist.
  - **A fill prompt of the eval's own.** The numbers would then measure a prompt the function does not send. The fill call here is the function's own extraction, prompt v5, schema, parser and retry, with only the outline added to its user turn.
  - **Giving the fill only the outline, with no image.** The small model could not take a card's text from the page, so every card would rest on the outline's gist.

## Decision

- **Configuration.** A candidate in `tools/eval/candidates.json` may name an `outline` model pattern beside `primary` and `retry`. The eval runs such a candidate as outline then fill:
  - **Outline.** `tools/eval/outline.ts` sends the image to the outline model under its own prompt and strict schema, "outline v1". The schema allows at most 100 items, each with a `topic` of up to 60 characters, a `name` up to 200 and a `gist` up to 300, and `max_tokens` is 4096. The prompt asks for every definition, rule, exception and marked line, the writer's additions included, a taught list as one item, no worked example, and nothing invented.
  - **Fill.** The function's `extractCards` runs on `primary`, with `retry`, through a fetch that adds the outline to its user turn as one text part before the image. The part asks for a card per item and for anything the outline missed, every card's text taken from the photo.
  - **A failed outline**, an error or a reply that is not an outline, fails the image as a model error with no fill call. So two in a row stop the candidate.
- **What it reports.**
  - The configuration's row, coverage and invented examples are scored as any other's.
  - A section, "Outline then fill", gives each call's cost per image and p50 latency, the total cost, and the notes coverage.
  - Its kept replies hold the outline call's items and answer beside the fill's calls.
  - The dry estimate adds a typical outline call, at 40 tokens an item, and counts those tokens again as the fill's prompt.
  - The guard before each image adds the outline model's worst call.
- **The candidate.** "Sonnet 5.5 outline, Haiku 5.5 fill" outlines on Claude Sonnet 5.5 and fills on Claude Haiku 5.5, with Sonnet as the retry, the retry production uses.
- **No function change.** `supabase/functions/extract-cards/` is unchanged. A pipeline in the function waits for the PM's reading of the numbers and a decision of its own.
- **Measuring it.**
  - The PM runs this candidate and Sonnet alone on prompt v5 over the same notes pages: samples 27, 33 and 35, 37 to 40, and the owner's photo kept locally.
  - The PM compares coverage and cost per image, and checks the kept replies of samples 37 to 40 for the writer's additions.

## Consequences

- The eval can measure a two-call pipeline with the function's own prompt, so a result carries over to the function if one is built.
- Each outline-then-fill image costs two calls, and its latency is their sum. The section shows how much each call adds.
- The outline prompt is the eval's, versioned in `outline.ts`. A function built on it later would move it into `supabase/functions/` as a versioned file, as the card prompt is.

## Signs the decision was wrong

- Outline then fill costs as much as Sonnet alone, because Sonnet's outline costs most of what its cards did, or Haiku's fill reads a long outline.
- Its coverage falls below Sonnet alone on the writer's additions, so the small model drops what the outline named, or the outline misses what Sonnet's cards caught.
- Its latency, the two calls in turn, is longer than users accept for one photo.
