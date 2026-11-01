# ADR 0135: Keep the cards a reply cut at the output cap completed, say the photo was read in part, and measure three ways to read a dense page whole

> Status: accepted; its answer read in part when a reply is cut, its `truncated` as the last reply's cut and its eval's `continue` way superseded by ADR-0138
> Date: 2026-11-01

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #519.** The owner's photo of a clear French–Korean word list, entries 101 to 200 in three columns (번호, 앞면 (프랑스어), 뒷면 (한국어 뜻)), failed to import.
- **The PM's probe of 2026-11-01** at `0fe6453`, recorded in the issue, on Claude Haiku 5.5 through the function's own `extractCards`:
  - prompt v9 and v10 each ended `invalid_output` after about 51 s;
  - OpenRouter answered `200` with `finish_reason: "length"`, 16,384 completion tokens, the cap `MAX_OUTPUT_TOKENS`, 12,719 prompt tokens and $0.0095;
  - the reply was JSON cut off mid-card, so `parseReply` refused the whole envelope and no card was saved;
  - a vocabulary card's fields cost about 160 output tokens, so 100 cards do not fit in 16,384, and the reply ran at about 320 tokens a second.
- **The limits that bind any longer reply**: the model call's 60 s timeout ([ADR 0124](0124-send-a-fixed-output-contract-after-every-prompt-version-and-keep-a-reply-s-valid-cards.md)), the retry that starts only before 75 s of the request ([ADR 0130](0130-retry-a-failed-photo-once-within-one-usage-and-record-each-extraction-s-outcome.md)), and the Edge Function's 150 s wall clock and idle timeout.
- **Alternatives for reading the page whole**, which issue #519 asks to be measured before one is chosen:
  - **(a) a leaner reply shape** for vocabulary cards, a card leaving out every field at its default, with the schema and the output contract changed and the app's contract not;
  - **(b) a higher cap** within the 60 s timeout;
  - **(c) one continuation call** that asks for the entries after the last one read, as the photo's one retry.
- **Alternatives for the cut reply itself:**
  - **Retry it whole.** The same page is cut again at the same cap, and the retry doubles its cost.
  - **Answer `502` as before.** The user loses every card the model read.

## Decision

- **A cut reply keeps what it finished.** When OpenRouter reports `finish_reason: "length"` and the reply is not whole JSON, the function closes it after the last card its JSON completed (`closeCutReply` in `cards.ts`) and reads those cards by the same rules (`parseReply`). A reply cut before any card is whole is invalid output, and retried as ADR 0130 decides; a reply with kept cards is not retried.
- **The answer says so.** A `200` carries `partial`, `true` when the cards came from a cut reply and `false` otherwise. The field is additive: an app built before it ignores it.
- **The record says so.** Migration `20261101075233_extraction_truncated.sql` adds `truncated`, nullable, to `private.extraction_calls`, and `finish_extraction` takes it as an eighth argument defaulting to null, so a function deployed before the migration records as before. A check allows `true` only on `ok` or `invalid_output`. No existing row changes.
- **The web says so** under the photo's cards in the review list: one sentence, "사진의 일부만 읽었어요", in the style of the other photo import messages. It is an interim state: #535 reads the whole page and replaces it. The app gets no sentence of its own, since #535 replaces the state on both clients.
- **The eval measures the three ways**, none deployed: `tools/eval/dense.ts` implements them, `extractCards` takes the reply form and a follow-up text as a seam (`CallOptions`), and `run.ts --alternatives today,lean,cap,continue` runs each as rows of its own.
  - **(a) `lean`**: the card schema with only `kind`, `front` and `topic` required on a card and `meaning` on a sense, and the output contract with its fields rule replaced by one asking to leave out every field at its default; a left-out field is filled with its default and the card read by `parseReply`.
  - **(b) `cap`**: 18,000 tokens. At the measured 320 tokens a second, 19,200 tokens end at the 60 s timeout; 18,000 leaves about 4 s to read the prompt. A higher cap with a longer timeout leaves no time for ADR 0130's retry.
  - **(c) `continue`**: when the first reply is cut and ended before the 75 s retry limit, one more call with the same photo and instructions and a text naming the last entry read and asking for the entries after it. Cards whose front a first card has are left out, and the list is cut at 100.
- **The eval adds a dense sample**, `90-dense-list-fr-ko-print`: 100 French words numbered 101 to 200 in two ruled tables of the owner's three columns, 15 of them with two numbered senses, in print under the mild distortion. Its words have no accent, which the Nanum faces lack. Samples 01 to 89 are byte-identical.
- **The report** gives, per configuration, the cards kept and the cut replies beside the invalid outputs, and each image's latency as the sum of its calls. `--samples` runs only the samples named, so the dense page can be measured alone.
- **Shipping one way** is a later change that the PM decides on this eval's numbers: (a) changes the schema and contract the function sends, (b) the cap, and (c) the handler's retry and the record's `attempts` and `failures` rule, which counts a second call only as a failure's retry today.

## Consequences

- A dense page no longer fails whole: the user gets the cards the model finished and is told the photo was read in part.
- The app shows the cut reply's cards without saying they are a part until #535 lands.
- `admin_extraction_calls` does not return `truncated` yet; the column is read in SQL until the admin area shows it.
- The deployed folder holds the seam the eval uses, `CallOptions`, which the function's own call leaves at its defaults.

## Signs the decision was wrong

- Cut replies are frequent on pages users do not consider dense: the cap or the shape is wrong for ordinary pages, not only for 100 entries.
- Users often edit or leave out the last cards kept from a cut reply: the cards just before the cut are less reliable than the rest.
- Users retake the same page after "사진의 일부만 읽었어요" and get the same part: the sentence asks for something the import cannot do, so the rest must be read another way.

## Measured result

The PM's paid runs of 2026-11-01 at `e3a8e337997a2a3c1e2fd7e7b446f6e80d31ce59`, Claude Haiku 5.5, prompt v9 (`docs/eval/extract-cards.md`, `tools/eval/spend.json`).

- **On the owner's photo of 100 entries**, kept only in the PM's scratchpad (#535):

  | Way | Cards read | Cut at the cap | Cost |
  |---|---|---|---|
  | `today`, with the cut reply's cards kept | 85 | yes | $0.0095 |
  | `lean` | 100 | no | $0.0078 |
  | `cap` 18,000 | 98 | yes | $0.0103 |
  | `continue` | 100 | no | $0.0123 |

- **On the 90 samples**, `today` against `lean`, $0.4115:
  - vocabulary F1 is 99.4 for `today` and 92.9 for `lean`;
  - `lean` had 3 invalid outputs and dropped 6 cards by `vocabulary_senses`; `today` had 1 model error and dropped 1 card by `cloze_blanks`;
  - neither had a cut reply: both read sample 90 whole, at F1 100.0.
- **The PM's decision:**
  - `lean` is not adopted: it read the owner's page whole but lost 6.5 points of vocabulary F1 on the samples.
  - The cap stays at 16,384: 18,000 still cut the owner's page.
  - Keeping a cut reply's cards ships as decided above.
  - Reading the whole page is #535, by continuation.
