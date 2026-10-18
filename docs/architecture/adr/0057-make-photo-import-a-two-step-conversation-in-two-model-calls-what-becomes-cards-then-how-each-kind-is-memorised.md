# ADR 0057: Make photo import a two-step conversation in two model calls: what becomes cards, then how each kind is memorised

> Status: proposed
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #182 records the owner's request of 2026-10-18. After a photo, the AI says what it sees on the page, and the user decides in two steps: what becomes cards, then how each kind of item is memorised, front and back. Only then are the cards made.
- The PM's proposal in the issue:
  - three calls: a survey of the page's topics, card shapes for the chosen topics, then the cards;
  - free text at either step, passed to the model;
  - a conversation counting once against the daily 30, with the function keeping one photo per conversation;
  - a "바로 만들기" fallback that keeps today's single call.
- Today one call returns every card with a step from 1 to 5, and the user filters the cards with the slider and checkboxes ([ADR 0051](0051-extract-each-card-with-a-question-a-fullest-and-a-short-answer-and-a-detail-step-and-eval-notes-pages-by-terms.md), [ADR 0052](0052-choose-a-photo-s-cards-and-how-full-their-answers-are-on-a-five-step-slider-in-the-app.md)). ADR 0055, in #179 and not yet merged, asks prompt v4 for every point of a notes page at step 5. The photo comes from the system camera or the library ([ADR 0054](0054-take-the-photo-with-the-system-camera-or-from-the-library-and-remove-the-in-app-camera-view.md)).
- `extract-cards` is stateless and stores no image (`ai-extraction.md` §Privacy), so it cannot keep a photo between requests. The app holds the photo for the whole screen already: a retry resends it.
- The PM drew the screens on a private design canvas, `https://claude.ai/artifact/9GxVB2RjZ36BtgcyBr6UmD`, titled "smartman 사진 대화 시안", for the owner's review. Its current flow, "사진 → 고르기 → 검토", has two screens:
  - "1. 무엇을 외울까요": the page's topics as pills, all but one on, an "추가" pill that takes a topic the user types, and one card preview whose front and back each open their alternatives, then "카드 만들기";
  - "2. 검토 · 고치고 지우기": the cards made, an edit mode to change or delete a card with an undo, and "덱에 n장 추가".
  - Below them, under "처음 시안 (복잡함)", is an earlier draft in four screens: what to card, how to memorise each kind, making, and review, with a "고르지 않고 바로 만들기" link.
- Merging a function change deploys it, and a change to the cost of a call waits for the owner's approval (`server.md` §Edge Function deploys).
- The eval's token model (`tools/eval/budget.ts`): a call's prompt, with its photo, is 2,500 tokens; its reply is 1,000 tokens of reasoning plus 120 per note card or 45 per vocabulary card. No run has measured latency yet.
- Alternatives considered:
  - **Two screens of choices, as in the issue and the canvas's earlier draft.** The canvas's current flow puts both choices on one screen, which this ADR follows: the second step's choices draw from the same survey reply, so a second screen adds a tap, not information.
  - **The PM's three calls.** The middle call only proposes card shapes for the chosen topics. Every shape the issue names can be drawn from one sample item per topic: reversing it, a question or a term, a short or a full answer. So the first call can return a sample item with those forms and its proposed shape. The app then draws every alternative with no model call, and a third call adds a photo's prompt and a round trip for nothing it alone can give. The table below prices both.
  - **Keeping the photo on the server between calls.** That would break the rule that no image is stored. The app resends it, and a token binds the conversation to the photo's hash instead.
  - **A table of open conversations for the daily limit.** It needs a migration, and a row per photo, to do what a signed token does with none.
  - **Re-asking the model after each typed line, to show its effect.** That is a call per line, each with the photo. Typed lines are collected and applied once, when the cards are made.
  - **Starting the final call speculatively with the defaults.** It saves the wait when the user changes nothing, and doubles the cost when they do.

## Decision

- **Flow.** The steps follow the canvas's current flow. The screens' details stay open for the owner's review: whether the shape is chosen once or per topic, whether Review keeps its checkboxes or takes the canvas's edit mode, and the wording.
  1. **Reading.** The photo, a line saying the page is being read, a progress bar, the privacy note, and "취소", while the survey call runs. The canvas does not draw this screen yet. No "바로 만들기" is offered here: the survey has already counted, and cancelling it to make cards at once would count a second extraction.
  2. **무엇을 외울까요.** The AI's one-line description of the page, as the title.
     - The page's groups of items, as the survey names them, are pills, each on unless the survey marks it as nothing to memorise, such as a course's date and title.
     - "추가" takes a topic the user types.
     - The card preview shows one item of the page, front and back. Tapping the front offers the question, the term ("식만") or the answer first ("결과를 앞에"); tapping the back offers the short or the full answer ("짧게", "이유까지"). The survey's example carries every form, so the app draws them all without a call.
     - "카드 만들기" sends the make call. A way to make cards without choosing ("바로 만들기") stays on this screen, as the earlier draft placed it; where exactly is open.
  3. **Making, then Review.** Today's Extracting, then Review: today's editing, duplicates, deck chip, and nothing written before the add button. The canvas's edit mode with delete and undo is an option for the owner, not decided here.
  - Back from Review to the choices is free: the survey's reply is still on the screen, and the same photo makes cards again without counting within the token's life (below).
  - Free text reaches the model two ways: a typed topic from "추가", and, if the owner keeps the earlier draft's field, a typed request. Both are sent with the make call; their effect shows on Review.
- **Two calls.** A survey call, then a make call. A third, shape-only call is not made, for the reason above.
- **Contract.** The same endpoint, `POST extract-cards`, with today's authentication, `image`, `languages`, size and type limits, and refusal codes:
  - **Survey request** `{image, languages?, survey: true}`. A `200` is `{conversation, summary, groups}`:
    - `summary` is a description of the page, 1 to 200 characters;
    - `groups` holds 1 to 12 groups, each with:
      - `id`, 1 to 40 characters;
      - `kind`, `vocabulary` or `note`;
      - `title`, 1 to 60 characters;
      - `count`, an integer from 1 to 100;
      - `samples`, 1 to 3 strings of at most 100 characters;
      - `list`, true when the group's items form a list the page teaches as one item;
      - `memorise`, false for a group that is nothing to memorise, such as a date or a course title, which the screen shows off;
      - `example`, one item of the page with its `term`, its `question`, its `answer` and its `short`, the same limits as a card's fields;
      - `shape`, the proposed `{front, back}`, with `front` one of `question`, `term` or `answer` and `back` one of `answer`, `short` or `term`, plus `split` on a list group.
    - No group is `422 no_cards`, as no card is today.
  - **Make request** `{image, languages?, conversation?, plan?}`. `plan` is `{groups, added?, instruction?}`:
    - `groups` holds the chosen groups as `{id, title, shape}`, the same shape on each when the screen offers one shape;
    - `added` holds up to 5 topics the user typed, each at most 60 characters;
    - `instruction` holds a typed request, at most 1,000 characters. A `200` is today's `{cards}`, so Review reads it unchanged.
    - The prompt is ADR 0055's, told to make only the plan's groups in their shapes and to follow the instruction.
    - The rules against inventing anything stand.
  - **Without `survey` or `plan`** the request is today's single call. That is "바로 만들기", sent with the conversation's token, and every app that has not updated keeps working.
- **Daily limit.** A conversation counts once:
  - The survey consumes one extraction before its model call, as a request does today, so a failed survey counts.
  - Its reply carries `conversation`: a token holding the user's id, the SHA-256 of the image bytes and an expiry 30 minutes ahead. It is signed with HMAC-SHA-256 under a key derived from `SUPABASE_SERVICE_ROLE_KEY` with the label "extract-cards conversation", so no new secret is needed.
  - A make request, or "바로 만들기", whose token verifies for the same user and the same image before it expires consumes nothing. Any other request consumes one, as today.
- **Slider.** The make call still returns each card's `step`.
  - On the conversation path, Review offers every returned card and shows no slider, as the canvas draws it: the user has chosen what to card, and how full each answer is was set by the shape.
  - After "바로 만들기", Review keeps the slider, as ADR 0052 has it.
- **Model.** Both calls use `CARD_MODEL`, with the retry as today. A cheaper model for the survey is an open question for the eval.
- **Cost per conversation**, from the eval's token model. Each group's survey output is about 150 tokens: a name, a count, three samples, an example in four forms, and a shape. The plan adds about 50 prompt tokens a group. Every checked group is made, which is the worst case. Each call is priced at the model's prompt and completion prices and excludes any per-image fee or retry, both of which add per call. Prices are OpenRouter's on 2026-10-18, as the eval's dry run read them.

| Page | Model | Today, 1 call | 2 calls (this ADR) | 3 calls (the issue) |
|---|---|---|---|---|
| Logic notes, 12 facts, 4 groups | Claude Haiku 5.5 | $0.0015 | $0.0026 (×1.74) | $0.0036 (×2.46) |
| | Claude Sonnet 5.5 | $0.0294 | $0.0512 (×1.74) | $0.0724 (×2.46) |
| | Gemini 3.8 Flash | $0.0121 | $0.0211 (×1.74) | $0.0299 (×2.46) |
| Dense grammar, 26 facts, 6 groups | Claude Haiku 5.5 | $0.0023 | $0.0036 (×1.54) | $0.0048 (×2.06) |
| | Claude Sonnet 5.5 | $0.0462 | $0.0712 (×1.54) | $0.0954 (×2.06) |
| | Gemini 3.8 Flash | $0.0191 | $0.0294 (×1.54) | $0.0394 (×2.06) |
| Vocabulary, 15 entries, 1 group | Claude Haiku 5.5 | $0.0011 | $0.0019 (×1.78) | $0.0028 (×2.55) |
| | Claude Sonnet 5.5 | $0.0217 | $0.0387 (×1.78) | $0.0554 (×2.55) |
| | Gemini 3.8 Flash | $0.0090 | $0.0160 (×1.78) | $0.0229 (×2.55) |

- The tokens behind the table:
  - today's call: 2,500 in, and 2,440 out (logic), 4,120 out (dense) or 1,675 out (vocabulary);
  - the survey: 2,500 in, and 1,630, 1,930 or 1,180 out;
  - the make call: about 2,600 to 2,850 in, and the same out as today's call;
  - the issue's shape call: about 2,600 in, and 1,150 to 1,900 out.
  - Opus 5.5, Gemini 2.5 Pro and GPT 5.4 mini, not shown, give the same ratios to today within 0.03.
  - The dense grammar page is the eval sample #179 adds.
- **Latency per conversation.**
  - The make call waits as long as today's call.
  - The survey adds one call before the choices, 1,180 to 1,930 completion tokens long. At an assumed 50 to 150 tokens a second, that is 8 to 39 seconds, plus the first token's delay with a photo.
  - The issue's shape call would add 1,150 to 1,900 more tokens between its two steps.
  - None of these rates is measured. The eval's p50 latency replaces them once it runs.
- **Before implementation.** The cost per photo rises by 1.5 to 1.8 times on every model. So the implementation pull request waits for the owner's approval, after the comparison run (`server.md` §Edge Function deploys).

## Consequences

- The user gets the cards they chose, in the shapes they chose, for one extraction against the daily limit.
- A conversation costs 1.5 to 1.8 times today's call, and the user waits once more before the choices.
- The app keeps the photo and resends it with the make call. The server stores nothing and keeps a conversation only in its signed token.
- Within 30 minutes, the same photo can be made into cards again without counting, for example after going back to change a choice. Any other photo counts.
- An app that has not updated, and "바로 만들기", keep today's single call, slider and all.
- A typed topic or request takes effect only on Review, not as an updated preview on the choice screen.

## Signs the decision was wrong

- Users go back from Review to the choices to see a typed topic's or request's effect, so the preview should have been redrawn by the model after all.
- Most conversations end in "바로 만들기", or accept every default at both steps, so the steps cost a call and a wait for nothing.
- The survey's groups miss items the make call would have found, so the plan narrows the cards below what one call gives today.
- Repeated make calls within one token's 30 minutes show up in the usage logs, so a conversation needs a count of its own.
- The survey's wait drives users away before the choices.
