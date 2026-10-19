# ADR 0059: Keep one Sonnet call per photo after measuring an outline-then-fill pipeline and the newest models

> Status: accepted; its Haiku-with-a-Sonnet-retry candidate superseded by ADR-0071
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #189 aims to cut the cost of a photo on Claude Sonnet 5.5, the owner's choice of 2026-10-18, without losing what Sonnet alone catches on real notes pages. [ADR 0058](0058-stop-asking-the-model-for-a-short-form-and-a-step-with-prompt-v5-and-add-a-notes-sample-with-the-writer-s-additions.md) slimmed the card output with prompt v5. #189 also asked the eval to try two calls in place of one:
  - an outline call, on a strong model, listing the page's items to memorise, each a topic, a name and a gist;
  - a fill call, on a small model, making the cards from the image and that outline.
- #192 built that configuration in the eval only, at `d6216310c1419f8b33a2ad428154638ac79930df`:
  - the outline call ran under its own prompt and schema;
  - the fill was the function's own extraction, prompt v5 with its schema, parser and retry, with the outline added to its user turn before the image.
- **Measurements.** The PM ran both on 2026-10-18 over samples 27, 33, 35 and 37 to 40, with prompt v5 (`docs/eval/extract-cards.md`, "2026-10-18 notes runs on prompt v5"):
  - **Sonnet alone:** coverage 78.2, unsupported 22.7, invented examples 0.0, at $0.0229 per image with a p50 latency of 9.2 s.
  - **Sonnet outline, Claude Haiku 5.5 fill:** coverage 72.3, unsupported 27.8, invented examples 1.2, at $0.0179 per image with a p50 latency of 16.9 s.
    - Of that $0.0179, the outline call cost $0.0158 and the fill $0.0021. Sonnet's reading of the image alone costs most of what its whole reply did.
  - **The newest models**, same samples and prompt:
    - OpenAI GPT 6.1 Sol covered 75.5 at $0.0227, p50 29.3 s, with 7.5 invented examples;
    - OpenAI GPT 6 Luna covered 67.3 at $0.0016, p50 24.9 s;
    - Google Gemini 4 Argon stopped after two model errors, Google's `400 INVALID_ARGUMENT` again, unbilled.
- Alternatives considered:
  - **Outline then fill**: 22% cheaper than Sonnet alone, but 6 points less coverage, more unsupported cards, and nearly twice the wait.
  - **GPT 6.1 Sol**: about Sonnet's cost, with less coverage, invented examples, and three times the wait.
  - **GPT 6 Luna**: a fourteenth of Sonnet's cost, with 11 points less coverage.
  - **Keeping the outline code in the eval** for a later model pair. The ADR names no pair that would change the result. A cheaper outline model must still read the image, and the image read is most of the cost. The configuration is at the commit above if a reason appears.

## Decision

- **One Sonnet call per photo stays.** The PM decided on 2026-10-18 to keep a single call on Claude Sonnet 5.5 with prompt v5. The function is unchanged.
- **The outline code goes.** `tools/eval/outline.ts`, its tests, the `outline` field of a candidate, and the report's "Outline then fill" section are removed from #192 before it merges. The measurements stay in `docs/eval/extract-cards.md` and `ai-extraction.md`.
- **Candidates.** `tools/eval/candidates.json` names the models OpenRouter lists on 2026-10-18:
  - **GPT:** the "newest" OpenAI patterns match its new names, `gpt-<version>-sol` and `gpt-<version>-luna`, today `openai/gpt-6.1-sol` and `openai/gpt-6-luna`. `-mini` matches only `gpt-5.4-mini` now.
  - **Gemini:** one pattern, `gemini-<version>-argon`, the newest Gemini, today `google/gemini-4-argon`, replaces the Flash and Pro patterns. The 3.x Pro is listed only as a preview, so the Pro pattern resolved to nothing and stopped a full run.
  - **Ceilings:** Claude Opus 5.5 stays and Claude Fable 5.1 joins, to show the most any model reaches on the samples.
  - **Left out:** `openai/gpt-6-astra`, at Fable's price, adds no ceiling the two Claude models do not.

## Consequences

- A photo costs one call and one wait, at about $0.023 on the samples.
- The eval loses the two-call configuration. Measuring one again means restoring it from the commit above.
- A full run of the candidates now resolves every pattern, and its two ceilings, Fable at $10/M prompt and $50/M completion, raise the dry estimate.

## Signs the decision was wrong

- A model reads images at a fraction of Sonnet's price while matching its coverage of the writer's additions. An outline on it would then cost little, and the two-call result could turn.
- Real photos of the owner's notes show Sonnet's single call missing items an outline would have named.
- Google accepts the request, and a Gemini model matches Sonnet's coverage for less.
