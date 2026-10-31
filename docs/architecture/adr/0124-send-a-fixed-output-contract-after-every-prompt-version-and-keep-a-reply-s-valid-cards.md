# ADR 0124: Send a fixed output contract after every prompt version, and keep a reply's valid cards

> Status: accepted
> Date: 2026-10-29

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #493**, with the owner's direction of 2026-10-28/29 and the PM's comment of 2026-10-29:
  - The owner saved a general prompt in the admin area as store version 3 and made it active on 2026-10-28. It assumes no subject, format or card type, and says how to study the material, not the form of the output.
  - The PM's eval of version 3 on 2026-10-28 (`docs/eval/extract-cards.md`, Claude Haiku 5.5 over the 87 samples, $0.3099) returned `invalid_output` for 63 of 87 images, the simplest vocabulary pages included, with vocabulary F1 10.3.
  - The owner then allowed the prompt to be tuned, within the direction: general, version 3 as the base with its principles kept, a vocabulary card's word on the front and its meaning on the back, and a page too complex for one call sent to the external-AI route (#496) rather than to more prompt rules.
- **The cause.** `parseCard` enforces rules beyond the JSON schema: a vocabulary card's answer is null and its senses non-empty, a table or cloze card's answer is null, a cloze front holds one `___` per answer, a note carries no senses. Prompt v9 stated them; version 3 states none. One card breaking one rule voided the whole reply, so the photo saved no card.
- **[ADR 0073](0073-keep-the-extraction-prompt-as-append-only-versions-in-the-database-served-by-an-active-and-an-admin-only-test-label-and-record-what-served-each-call.md)** made the editable text the model's instructions only, kept the schema and the parser in the function, and decided that "a text that makes the model break the schema fails as invalid output, `502`, and saves no card".
- **Alternatives considered:**
  - **Relax the parser** to accept what version 3 returns. The rules describe the app's contract, which does not change, so a card that breaks one cannot be saved as it is.
  - **Ask the prompt's author to state the rules** in every version. That is what failed: a general prompt has no reason to state them, and nothing checks a saved version for them.
  - **A check at save time** that refuses a version missing the rules. It cannot tell whether a text states a rule well enough for a model to keep it; only a run can.
  - **The contract inside the JSON schema's descriptions.** The schema cannot express the cross-field rules, and the structured-output grammar Anthropic compiles has refused large schemas before (#414).
  - **Retrying a reply that broke a rule.** ADR 0071 makes one call per photo, and a retry doubles the cost of the replies that fail.

## Decision

- **The output contract is fixed in the function**, in `cards.ts` beside the schema it describes: the meaning of each of the schema's fields, and each rule `parseCard` and the table, cloze, sense and label parsers check, one sentence a rule, with the card limit and the shape of the reply.
  - Each refusal of the parser names its rule, and the rules are the contract's own keys, so a check the contract does not state cannot be written: the type check fails. A test gives every rule a card that breaks it alone and asserts the contract holds the rule's sentence.
  - It speaks of the material, never of a photo or a page, so a later source, a file or pasted text, sends it unchanged.
- **The model's instructions** are the served version's text, unchanged, then a blank line, then the contract. Every version is served with it; no editable text can leave a rule unstated. The user turn with the language hints is unchanged.
- **A reply is read card by card.** A card that breaks a rule is dropped and the others are kept. A reply that is not the schema's envelope, JSON of exactly `{cards}` with at most 100 cards, is invalid output, and so is a reply whose every card was dropped: the photo saves nothing either way, and answering `no_cards` would tell the user the page held nothing. This supersedes ADR 0073's "a text that makes the model break the schema fails as invalid output, `502`, and saves no card" for a reply in which some cards keep every rule.
- **The log line** carries `dropped_cards`, the number of the reply's cards dropped, or null when no reply was read as the schema's. The eval keeps each dropped card's rule in its kept reply and reports, per configuration, the invalid outputs, the model errors and the dropped cards by rule.
- **Prompt v10** (`prompt_v10.ts`) is version 3 tuned under the owner's direction: a vocabulary card's word on the front and its meaning on the back, a question form beyond the supported card types expressed as the nearest one rather than designed anew, and the output's form, its limits and its check left to the contract. It is the eval's default. Prompt v9 is unchanged; the eval runs both in one run with `--prompts v9,v10`.
- **Shipping** waits on the PM's eval of v9 and v10 under the contract: v10 ships only with no more invalid outputs and no lower vocabulary F1 than v9's, with notes coverage and unsupported cards reported beside v9's. Reaching users is still an admin's activation of a saved version (ADR 0073).
- **A model call times out at 60 s** (`MODEL_TIMEOUT_MS`), its reply's body included, and ends as `model_error`, which the app treats as retryable. The PM's paid run of `--prompts v9,v10` on 2026-10-29 hung over an hour on one call (v10, sample 39), since nothing bounded the OpenRouter fetch; in production such a call ran until the Edge Function's limit, past the web's 90 s Server Action (#506). 60 s is about four times the p90 of 15.6 s that the 2026-10-28 report measured on Claude Haiku 5.5, and under the Edge Function's request idle timeout of 150 s and its wall clock of 150 s on the free plan and 400 s on paid plans (`supabase.com/docs/guides/functions/limits`, read 2026-10-30). The eval shares the call, so a timed-out call is a model error there too, kept and printed as timed out, and the run goes on under the two-errors stop.
- The response JSON schema and the app's contract do not change.

## Consequences

- An admin may write the prompt in any form and language; the form of the output no longer depends on it.
- A photo whose reply holds one malformed card among valid ones now saves the valid ones. The user is not told a card was dropped; the log line and the eval are where the count shows.
- The system prompt grows by the contract, 5,880 characters, on every call. Prompt v10 and the contract come to 8,252 characters, against prompt v9's 11,838 alone, so a call under v10 sends fewer prompt tokens than one under v9 did; one under v9 with the contract sends more.
- A contract sentence is in English while the served prompt may be Korean. Whether a model keeps the rules as well under a Korean prompt is what the PM's eval measures.
- Changing a rule is a pull request that changes the parser and the contract together.

## Signs the decision was wrong

- Dropped cards stay frequent under a prompt that keeps the contract: the contract is not read, or its rules are not the ones the model breaks.
- Users notice cards missing from a page, the dropped cards being ones they wanted, so a dropped card should be repaired or reported rather than left out.
- A future source needs a rule the contract states only for one kind of material.

## Measured result

The PM's paid run of `--prompts v9,v10` on 2026-10-31 (UTC), at `12ac92309378817bd3ed9d9b1881419ab8d4edf7`: Claude Haiku 5.5 over the 89 samples, $0.7930 (`docs/eval/extract-cards.md`, `tools/eval/spend.json`).

- **The contract works.** Prompt v9 and prompt v10 each had 0 invalid outputs, 0 model errors and 0 dropped cards.
- **The ship rule's two gates hold for v10.** Vocabulary F1 is 99.7 for both. Numbered fronts are 0 for both ([ADR 0128](0128-read-clear-material-in-photo-import-and-send-complex-material-to-the-external-ai-integration.md)).
- **v10 is less faithful than v9.** Each pair below is v10 against v9:

  | Measure | v10 | v9 |
  |---|---|---|
  | Invented | 7.8 | 0.0 |
  | Unprinted labels | 6.3 | 0.0 |
  | Senses P and R | 95.5 | 99.8 |
  | Labels P | 88.9 | 100.0 |
  | Notes table blanks | 70.8 | 95.8 |
  | Notes cloze blanks | 0.0 | 100.0 |

- **Notes coverage and unsupported cards both rise under v10.** Coverage is 94.1 against 92.3, and unsupported cards 11.3 against 9.7.
- **The PM's decision: v10 is not activated.**
  - The report recommends v10, since it is the cheaper per image within the F1 and coverage bounds. The PM decided against it on faithfulness.
  - The served version stays store version 4, whose text is prompt v9's.
  - The output contract, partial acceptance and the 60 s timeout apply to it once this change deploys.
  - A follow-up issue retunes v10's faithfulness before any activation.
