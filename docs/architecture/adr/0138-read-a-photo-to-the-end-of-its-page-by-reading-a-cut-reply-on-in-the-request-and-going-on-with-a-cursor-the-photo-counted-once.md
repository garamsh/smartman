# ADR 0138: Read a photo to the end of its page by reading a cut reply on in the request and going on with a cursor, the photo counted once

> Status: accepted
> Date: 2026-11-01

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #535, the owner's direction of 2026-11-01:** a photo of clear material is read to the end, every entry a card. "Read in part" survives only as a progress state, never as the result.
- **[ADR 0135](0135-keep-the-cards-a-reply-cut-at-the-output-cap-completed-say-the-photo-was-read-in-part-and-measure-three-ways-to-read-a-dense-page-whole.md)'s measured result**, on the owner's page of 100 entries: the cut reply's cards alone read 85, a cap of 18,000 read 98, and the lean reply and one continuation each read 100. The PM chose continuation. Lean is not adopted, since it lost 6.5 points of vocabulary F1 over the 90 samples.
- **A denser page cuts even one continuation:** 200 entries need about three replies of 16,384 tokens, at about 51 s each.
- **The limits:** the model call's 60 s timeout, no call starting after 75 s of a request ([ADR 0130](0130-retry-a-failed-photo-once-within-one-usage-and-record-each-extraction-s-outcome.md)), and the Edge Function's 150 s wall clock. So one request holds about two full replies.
- **What the record may hold:** no image, card or prompt text ([`ai-extraction.md`](../ai-extraction.md) §Privacy).
- **Alternatives for going on past one request:**
  - **Keep the read cards on the server.** The record would hold card text.
  - **Sign the cursor with a new secret.** That needs a secret set on the project, and a signature alone cannot refuse a cursor's second use.
  - **Count each request as a photo.** A dense page would cost the user two or three of their plan's photos.

## Decision

- **Read on in the request.** When a reply is cut and keeps cards, the function asks again with the same photo, model and prompt, and a text naming the cards read so far and the last fronts read. It goes on after each cut reply until a reply is whole or adds no card.
  - A call starts only before 75 s of the request, as ADR 0130's retry does.
  - A front already read is left out, compared after the card key normalization.
  - A failed call is asked again once in the request.
  - The follow-up names the last fronts read up to 4,000 characters.
- **Go on with a cursor.** When the request ends before the page does, the `200` carries the cards so far, `partial` `true`, and `cursor`, an opaque string.
  - The client sends it back with the same photo. That request reads on from where the cursor left off, by the model and prompt version of the photo's first read, and answers only the new cards.
  - The cursor's token is a random UUID held in `private.extraction_cursors` with the photo's usage row, for 10 minutes. `public.resume_extraction` takes it only for the user whose photo it is, and deletes it, so it cannot be taken twice.
  - A refused cursor is `410` `cursor_expired`, before any model call.
  - The cursor also carries the last fronts read, which the follow-up names. The server stores none of them.
- **The photo counts once.** A request with a cursor does not call `begin_extraction`.
- **Caps:**
  - a photo produces at most 500 cards, over every call and request;
  - it makes at most 10 calls that read on;
  - a reply still holds at most 100.

  No cursor is offered at either cap, or when a request with a cursor had every call fail. That request is `502` `model_error`.
- **Backward compatible:** a client that ignores `cursor` gets the cards read so far with `partial` `true`, as under ADR 0135.
- **The record:** migration `20261101150000_extraction_continuation.sql` changes the following.
  - It adds `continuations`, the calls that read on, and `resumes`, the requests that went on with a cursor, both nullable.
  - It allows `cards_returned` up to 500.
  - `finish_extraction` takes `continuations` and `cursor` as its ninth and tenth arguments, defaulting to null, so a function deployed before the migration still records.
  - `public.record_resumed_extraction` adds each request with a cursor to the photo's record.
  - `truncated` now records, for a photo answered with cards, whether its page was left unread past them.
- **A cursor the record did not keep is not offered:** the record stays telemetry for everything else.
- **The eval reads each photo as the function and its clients do:** the `today` way reads a cut reply on until the page is done, with no time budget. `continue` is removed.
  - The new sample `91-dense-list-200-fr-ko-print` holds 200 French words numbered 1 to 200, 30 of them with two senses.
  - A run prices an image at the most calls `today` may make: 11.
- **Lean stays unadopted:** ADR 0135's measured result stands.

## Consequences

- The owner's page of 100 entries is read whole in one request, and a page of 200 in two or three.
- The clients still show the cards of the first request and "사진의 일부만 읽었어요" until the clients' change for #535 sends the cursor back and shows one progress state.
- A cursor carries up to 4,000 characters of the user's own fronts. A client that alters them changes only its own follow-up.
- A dense page costs a prompt per call: the image and instructions are sent again with each continuation.
- `admin_extraction_calls` does not return `continuations` or `resumes` yet; they are read in SQL until the admin area shows them.

## Signs the decision was wrong

- Pages of 100 or 200 entries still end with fronts missing: the follow-up does not tell the model where to go on, and the eval's samples 90 and 91 read under 100%.
- Continuations repeat entries under a different front, such as a sense moved to the front: the comparison by front lets duplicates through.
- Many cursors expire unused, or `410` is frequent: 10 minutes is too short for a client that reads several photos at once.
