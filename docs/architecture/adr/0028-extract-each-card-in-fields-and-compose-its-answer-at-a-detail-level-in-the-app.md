# ADR 0028: Extract each photo card's fields in one call, and compose its answer at a detail level the app chooses

> Status: accepted; its model reply, response, prompt v2 and the eval's matching on `meaning` alone superseded by ADR-0051
> Date: 2026-10-15

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #73 records the owner's feedback of 2026-10-15: a photographed page marked parts of speech with notations such as "[동]", and the cards' answers left them out. Prompt v1 told the model to drop part-of-speech labels and example sentences, and `extract-cards` returned `{front, back}` with no control over what `back` holds ([ADR 0013](0013-extract-cards-function-and-eval.md)).
- The PM decided there:
  - one extraction returning each card's parts separately — `front`, `meaning`, an optional `partOfSpeech` kept verbatim, optional `examples` — beside a composed `back` for apps that read only `back`;
  - nothing invented: every field comes from the page, and an absent one stays absent;
  - three levels composed in the app: 간단 (the meaning), 기본 (the part of speech, a space, then the meaning; the default) and 자세히 (기본, then each example on its own line);
  - a selector on the capture and review screens, remembered per device; a switch on review recomposes every answer but one the user typed;
  - a new prompt file, and a schema enforcing the fields' types, 500 code points per field, 100 cards and 5 examples per card.
- Strict structured outputs require every property to be listed as required, so an optional field cannot simply be left out of the model's reply.
- Alternatives the owner raised: choosing the level before the extraction, or generating a version per level. Either makes a switch on review cost another call against the daily limit of 30.

## Decision

- **Model reply.** The schema asks for `front`, `meaning`, `partOfSpeech` and `examples` on every card, with `partOfSpeech` a string or `null` and `examples` a list of at most 5. The parser maps `null` and an empty list to an absent field; a field empty after trimming, or over 500 code points, is invalid output and takes the one retry.
- **Response.** Each card is `{front, back, meaning, partOfSpeech?, examples?}`. The function composes `back` at the 기본 level, so it holds at most 1001 code points: a part of speech, a space and a meaning of 500 each.
- **Prompt.** `prompt_v2.ts` replaces `prompt_v1.ts`, which nothing imports once the schema changed; git keeps it. It asks for each field verbatim and forbids supplying a part of speech, meaning or example the page does not print.
- **App.** `CandidateCard` holds the fields and composes its answer at a `DetailLevel`. A card without `meaning`, from a function deployed before this one, takes `back` as its meaning, so every level shows that `back`. A review row keeps the candidates of its key and composes their merged answer at the current level, unless the user typed one.
- **Storage.** The level is stored with `shared_preferences` under its own key, in the one cached store the composition site opens for the theme and the level, and the screen receives that store as it receives its client and photo source.
- **Eval.** A sample's ground truth holds `front`, `meaning`, and the `partOfSpeech` and `examples` its page prints. A candidate matches on front and meaning; over the matched cards the eval adds the precision of parts of speech and of examples, and the share of fields present where the page prints none.

## Consequences

- Switching the level is instant, free, and never counts against the daily limit; the saved cards are plain text as before.
- A deployed app keeps working against the new function, which still sends `back`, and the new app works against the old function at a single level until the PM deploys.
- `back` may now exceed 500 code points, which the previous contract table stated as its limit.
- The model writes more per card, so a call costs more completion tokens than under v1.
- The three Japanese dictionary samples were regenerated to print bracket notations such as "[동]"; the other 21 images are unchanged.
- The eval's results stay unmeasured until the owner provides `supabase/functions/.env`.

## Signs the decision was wrong

- The eval's invented rate is high for every candidate model: the model supplies parts of speech or examples the page does not print, whatever the prompt says.
- Users switch the level after nearly every extraction, so the default is the wrong one.
- Real pages print a part of speech the composed answer misplaces, such as one printed after the meaning, often enough that 기본 reads wrong.
- A level is wanted that the stored fields cannot compose, such as one needing a field the page prints but the schema does not ask for.
