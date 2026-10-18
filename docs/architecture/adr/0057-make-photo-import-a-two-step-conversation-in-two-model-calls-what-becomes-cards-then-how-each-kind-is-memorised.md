# ADR 0057: Make photo import a two-step conversation in two model calls: what becomes cards, then how each kind is memorised

> Status: accepted
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #182 records the owner's request of 2026-10-18. After a photo, the AI says what it sees on the page, and the user decides what becomes cards, then how each kind of item is memorised, front and back. Only then are the cards made.
- The PM's proposal in the issue:
  - three calls: a survey of the page's topics, card shapes for the chosen topics, then the cards;
  - free text at either step, passed to the model;
  - a conversation counting once against the daily 30, with the function keeping one photo per conversation;
  - a "바로 만들기" fallback that keeps today's single call.
- Today one call returns every card with a step from 1 to 5, and the user filters the cards with the slider and checkboxes ([ADR 0051](0051-extract-each-card-with-a-question-a-fullest-and-a-short-answer-and-a-detail-step-and-eval-notes-pages-by-terms.md), [ADR 0052](0052-choose-a-photo-s-cards-and-how-full-their-answers-are-on-a-five-step-slider-in-the-app.md)). ADR 0055, in #179 and not yet merged, asks prompt v4 for every point of a notes page at step 5. The photo comes from the system camera or the library ([ADR 0054](0054-take-the-photo-with-the-system-camera-or-from-the-library-and-remove-the-in-app-camera-view.md)).
- `extract-cards` is stateless and stores no image (`ai-extraction.md` §Privacy), so it cannot keep a photo between requests. The app already holds the photo for the whole screen, and a retry resends it.
- The PM drew the screens on a private design canvas, `https://claude.ai/artifact/9GxVB2RjZ36BtgcyBr6UmD`, titled "smartman 사진 대화 시안". Its flow, "사진 → 고르기 → 검토", has two screens: "1. 무엇을 외울까요" and "2. 검토 · 고치고 빼기".
- **The owner's decisions on 2026-10-18**, on a first version of this ADR:
  - the survey runs on a fast, cheap model with a light reply;
  - the card shape is chosen per topic;
  - Review has no checkboxes and no edit button, and a swipe left removes a card.
- **The owner approved this ADR on 2026-10-18**, and decided two more points:
  - "바로 만들기" is not offered on the choice screen: every topic worth memorising starts on, so "카드 만들기" already makes those cards;
  - the make call picks its model by the page: a vocabulary page runs on a cheap model, and notes on `CARD_MODEL`.
- Merging a function change deploys it. A change to the cost of a call, or one needing a secret the production project lacks, waits for the owner's approval (`server.md` §Edge Function deploys).
- The eval's token model (`tools/eval/budget.ts`): a call's prompt, with its photo, is 2,500 tokens; its reply is 1,000 tokens of reasoning plus 120 per note card or 45 per vocabulary card. No run has measured latency yet.
- Alternatives considered:
  - **The PM's three calls.** The middle call only proposes card shapes for the chosen topics. Each topic's shapes are drawn from one example of it: its question and answer, a term and a short form. The app shows them with no further call, so a third call would add a photo's prompt and a round trip for nothing it alone can give.
  - **A survey returning every card form of each example, with a proposed shape.** That was this ADR's first version. The owner chose a light survey on a fast model: a question and an answer per example, with the app or the make call supplying the rest.
  - **Two screens of choices, as in the issue.** Both choices draw from the same survey reply, so the canvas puts them on one screen and a second screen would add only a tap.
  - **A field for free instructions, or a chat with the AI.** The owner dropped both. A typed topic through "추가" is the one free text.
  - **Keeping the photo on the server between calls.** That would break the rule that no image is stored. The app resends it, and a token binds the conversation to the photo's hash instead.
  - **A table of open conversations for the daily limit.** It needs a migration and a row per photo, to do what a signed token does with none.
  - **Checkboxes or an edit mode on Review.** The owner chose swipes, as in studying, with a tap to edit.
  - **Starting the make call speculatively with the defaults.** It saves the wait when the user changes nothing, and doubles the cost when they do.

## Decision

- **Flow.** The steps follow the canvas. Its wording and visual details stay the owner's to change.
  1. **Reading.** The photo, a line saying the page is being read, a progress bar, the privacy note, and "취소", while the survey call runs. The canvas does not draw this screen yet.
  2. **무엇을 외울까요.** The survey's description of the page as the title, then "무엇을 외울까요?":
     - The page's groups of items, as the survey names them, are pills. Each is on unless the survey marks it as nothing to memorise, such as a course's date and title. "추가" takes a topic the user types, which joins the pills switched on.
     - Below the pills, a scrolling list holds one sample card per topic that is on, front and back.
     - Tapping a topic's front opens that topic's front options: "질문으로" (its question), the term ("용어만", "식만" or "예시만", as the topic reads), or "답을 앞에" (its answer first). Tapping its back opens "짧게" or "이유까지".
     - The question and the answer come from the survey. The app derives the term and the short form where it can, from the question and the answer. Where it cannot, the preview says the AI fills it in from the photo, as the canvas shows for a typed topic, and the make call writes it.
     - The button reads "카드 만들기", with no count. There is no instruction field and no chat.
  3. **Making, then Review.** Today's Extracting, then Review, "카드 n장을 만들었어요", then "덱에 n장 추가":
     - There are no checkboxes and no edit button.
     - A swipe left removes a card and a swipe right puts it back, the same directions as studying's "모른다" and "안다" (`study.md`). Under the moving card, "빼기" shows on the red tint and "다시 넣기" on the green.
     - A removed card stays in the list, struck through inside a dashed outline. The count in the title and on the add button follows.
     - A tap edits the card in place. The edit view holds "이 카드 빼기", or "다시 넣기" for a removed card, as the one-pointer alternative to the swipes, and "완료".
     - On first use, a three-step coach shows a finger on the first card, with a caption, "다음" and "건너뛰기": "왼쪽으로 밀면 빼요", then "오른쪽으로 밀면 다시 넣어요", then "눌러서 바로 고쳐요". It shows once per device, and not at all under reduce motion.
     - Today's duplicate grouping and options and the deck chip carry over. The canvas does not draw them, so their place is the owner's to set.
  - Back from Review to the choices is free: the survey's reply is still on the screen, and the same photo makes cards again without counting within the token's life (below).
- **Two calls.** A survey call, then a make call. No third, shape-only call is made, for the reason above.
- **Contract.** The same endpoint, `POST extract-cards`, keeps today's authentication, `image`, `languages`, size and type limits, and refusal codes:
  - **Survey request** `{image, languages?, survey: true}`. A `200` is `{conversation, summary, groups}`:
    - `summary` is a description of the page, 1 to 200 characters.
    - `groups` holds 1 to 12 groups, each with:
      - `id`, 1 to 40 characters;
      - `kind`, `vocabulary` or `note`;
      - `title`, 1 to 60 characters;
      - `count`, an integer from 1 to 100;
      - `memorise`, false for a group that is nothing to memorise, which the screen shows off;
      - `sample`, one item as the page writes it, at most 100 characters;
      - `example`, one item as a card: its `question` and its `answer`, with a card's limits.
    - No group is `422 no_cards`, as no card is today.
  - **Make request** `{image, languages?, conversation?, plan?}`. `plan` is `{groups, added?}`:
    - `groups` holds the chosen groups, each `{id, title, shape}`, where `shape` is `{front, back}`, `front` being `question`, `term` or `answer` and `back` being `short` or `answer`;
    - `added` holds up to 5 topics the user typed, each at most 60 characters, made in the default shape, `question` and `short`.
  - A `200` is today's `{cards}`, so Review reads it unchanged. The prompt is ADR 0055's, told to make only the plan's groups and added topics in their shapes, writing each card's term and short form itself. The rules against inventing anything stand.
  - **Without `survey` or `plan`** the request is today's single call, so every app that has not updated keeps working.
- **Models.** Two new function secrets, each falling back to `CARD_MODEL` when unset:
  - The survey runs on `SURVEY_MODEL`, a fast, cheap OpenRouter model.
  - The make call runs on `VOCAB_MODEL` when every group of the survey is of kind `vocabulary`, and on `CARD_MODEL` otherwise, typed topics included. A vocabulary entry is copied as printed, which a cheap model does as well as a dear one, while notes need a model that phrases questions and covers the page.
  - The retry runs on `CARD_RETRY_MODEL` as today.
  - The eval already reports vocabulary pages per configuration, which checks the rule: a cheap model whose vocabulary F1 is within the recommendation's 2 points of the best qualifies for `VOCAB_MODEL`.
  - Setting `SURVEY_MODEL` and `VOCAB_MODEL` is the owner's action in the Supabase console, so the implementation pull request merges only after the owner approves and sets them (`server.md` §Edge Function deploys).
- **Daily limit.** A conversation counts once:
  - The survey consumes one extraction before its model call, as a request does today, so a failed survey counts.
  - Its reply carries `conversation`, a token holding the user's id, the SHA-256 of the image bytes and an expiry 30 minutes ahead. It is signed with HMAC-SHA-256 under a key derived from `SUPABASE_SERVICE_ROLE_KEY` with the label "extract-cards conversation", so it needs no secret of its own.
  - A make request whose token verifies for the same user and the same image before it expires consumes nothing. Any other request consumes one, as today.
- **Slider.** The make call still returns each card's `step`. Review after a conversation shows no slider: the user has chosen what to card, and the shape sets how full each answer is.
- **No "바로 만들기".** The choice screen offers no way to make cards without choosing: every topic worth memorising starts on, so "카드 만들기" makes them all. A failed survey shows its failure with a retry and a retake, as a failed extraction does today. The contract keeps a request without `survey` or `plan` as today's single call, for apps that have not updated, and Review after it keeps the slider, as ADR 0052 has it.
- **Cost per conversation**, from the eval's token model:
  - Each group's survey output is about 60 tokens (an id, a kind, a title, a count, the flag, a sample, a question and an answer) after a 30-token summary. The eval's 1,000 tokens of reasoning are kept for every call, though a fast model without reasoning writes fewer.
  - The plan adds about 50 prompt tokens a group, and every topic switched on is made, which is the worst case.
  - Each call is priced at the model's prompt and completion prices, excluding any per-image fee or retry, both of which add per call. Prices are OpenRouter's on 2026-10-18, as the eval's dry run read them.

| Page | `CARD_MODEL` | Today, 1 call | Survey on Claude Haiku 5.5 | Survey on Gemini 3.8 Flash |
|---|---|---|---|---|
| Logic notes, 12 facts, 4 groups | Claude Haiku 5.5 | $0.0015 | $0.0024 (×1.62) | $0.0088 (×5.98) |
| | Claude Sonnet 5.5 | $0.0294 | $0.0308 (×1.05) | $0.0372 (×1.27) |
| | Gemini 3.8 Flash | $0.0121 | $0.0132 (×1.09) | $0.0196 (×1.62) |
| Dense grammar, 26 facts, 6 groups | Claude Haiku 5.5 | $0.0023 | $0.0033 (×1.42) | $0.0101 (×4.39) |
| | Claude Sonnet 5.5 | $0.0462 | $0.0478 (×1.04) | $0.0547 (×1.18) |
| | Gemini 3.8 Flash | $0.0191 | $0.0203 (×1.06) | $0.0271 (×1.42) |
| Vocabulary, 15 entries, 1 group | Claude Haiku 5.5 | $0.0011 | $0.0019 (×1.74) | $0.0077 (×7.04) |
| | Claude Sonnet 5.5 | $0.0217 | $0.0227 (×1.05) | $0.0285 (×1.31) |
| | Gemini 3.8 Flash | $0.0090 | $0.0098 (×1.10) | $0.0156 (×1.74) |

- The tokens behind the table:
  - today's call: 2,500 in, and 2,440 out (logic), 4,120 out (dense) or 1,675 out (vocabulary);
  - the survey: 2,500 in, and 1,270, 1,390 or 1,090 out;
  - the make call: about 2,600 to 2,850 in, and the same out as today's call.
  - GPT 5.4 mini as the survey model prices within 4% of Gemini 3.8 Flash.
  - The dense grammar page is the eval sample #179 adds.
- On a vocabulary page with `VOCAB_MODEL` set to Claude Haiku 5.5 and `CARD_MODEL` to a dearer model, the make call costs what a Haiku call does: with the survey on Haiku too, the 15-entry page costs $0.0019 against today's $0.0217 on Sonnet 5.5 or $0.0090 on Gemini 3.8 Flash.
- So a conversation costs 1.04 to 1.10 times today's call when the survey runs on Claude Haiku 5.5 and the cards on a dearer model. When both run on the cheapest model, it costs 1.42 to 1.74 times. The heavier survey of this ADR's first version cost 1.5 to 1.8 times on every model.
- **Wait per conversation.**
  - The make call waits as long as today's call.
  - The survey adds one call before the choices, of 1,090 to 1,390 completion tokens under the eval's token model, most of them its reasoning allowance, on the survey model.
  - How long that takes is unmeasured until the eval runs the survey on the candidate models.
- **Before implementation merges.** The cost per photo changes, and the calls need `SURVEY_MODEL` and `VOCAB_MODEL` set, so the implementation pull request waits for the owner's approval (`server.md` §Edge Function deploys).

## Consequences

- The user gets the cards they chose, in the shape they chose for each topic, for one extraction against the daily limit.
- A conversation costs 1.04 to 1.74 times today's call when the survey model is no dearer than the cards' model, and the user waits once more before the choices.
- The survey can be tuned for speed, and vocabulary pages for cost, separately from notes: `SURVEY_MODEL` and `VOCAB_MODEL` switch them with no code change.
- The app keeps the photo and resends it with the make call. The server stores nothing, and a conversation lives only in its signed token.
- Within 30 minutes, the same photo can be made into cards again without counting, for example after going back to change a choice. Any other photo counts.
- An app that has not updated keeps today's single call, slider and all.
- Review's swipes match studying's directions, so a user's habit carries over, and every swipe has a button in the edit view.
- A preview whose term or short form the app cannot derive shows a placeholder until Review.

## Signs the decision was wrong

- Users go back from Review to the choices because a shape came out unlike its preview, so the survey should return the term and short form after all.
- The light survey's groups miss items the make call would have found, so the plan narrows the cards below what one call gives today.
- Most conversations keep every default, so the choice screen costs a call and a wait for nothing.
- The eval shows the cheap model's vocabulary F1 well below the best, so vocabulary pages should run on `CARD_MODEL` after all.
- Users remove cards by accident with a swipe, or never find the swipe despite the coach.
- Repeated make calls within one token's 30 minutes show up in the usage logs, so a conversation needs a count of its own.
- The survey's wait drives users away before the choices.
