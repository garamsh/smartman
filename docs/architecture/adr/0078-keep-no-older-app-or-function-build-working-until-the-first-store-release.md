# ADR 0078: Keep no older app or function build working until the first store release

> Status: accepted
> Date: 2026-10-19

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Each change to the `extract-cards` contract so far kept an app that had not updated working:
  - `back`, `meaning` and `partOfSpeech` for apps that read only those ([ADR 0028](0028-extract-each-card-in-fields-and-compose-its-answer-at-a-detail-level-in-the-app.md), [ADR 0051](0051-extract-each-card-with-a-question-a-fullest-and-a-short-answer-and-a-detail-step-and-eval-notes-pages-by-terms.md), [ADR 0063](0063-ask-prompt-v6-for-atomic-typed-cards-and-a-vocabulary-entry-s-senses-and-eval-long-answers-and-senses.md), [ADR 0069](0069-ask-prompt-v7-for-whole-table-and-cloze-cards-as-structured-fields-exception-cards-that-state-what-they-do-and-examples-only-from-the-page.md));
  - `short` and `step` for an app with the step slider ([ADR 0057](0057-group-a-photo-s-cards-by-topic-on-review-with-a-switch-per-topic-and-swipes-per-card.md), [ADR 0058](0058-stop-asking-the-model-for-a-short-form-and-a-step-with-prompt-v5-and-add-a-notes-sample-with-the-writer-s-additions.md)).
- Each change to the app's parser kept reading a function that had not been redeployed: cards before kinds, senses or topics, and a `429` without `daily_limit`.
- The server kept the count's older entry points beside `begin_extraction`, so a function deployed before plans or the prompt store still counted each photo once: `consume_extraction` and `start_extraction` ([ADR 0071](0071-give-each-user-a-plan-whose-model-and-daily-limit-an-admin-sets-in-the-database-and-make-one-model-call-per-photo.md), [ADR 0073](0073-keep-the-extraction-prompt-as-append-only-versions-in-the-database-served-by-an-active-and-an-admin-only-test-label-and-record-what-served-each-call.md)).
- The owner decided on 2026-10-19 (issue #250) that the app is not released. The only clients are the owner's development installs and the web, which deploys from `main`. So until the first store release, no compatibility with older app builds is kept.

## Decision

- **The rule.** Until the first store release, a change need not keep an older app or function build working. From the first store release on, it must. The release checklist names the switch when it exists.
- **Applied now** (#250):
  - The function's response loses `short`, `step`, `meaning`, `partOfSpeech` and `back`.
  - The app's parser requires each card's `front`, `answer`, `topic` and `kind`, a vocabulary card's `senses`, a cloze card's `cloze` and a table card's `table`. A `429` without `daily_limit` is a service failure, not a daily limit.
  - `public.consume_extraction` and `public.start_extraction` are dropped. The function calls `begin_extraction` alone.
- **Kept**, because it serves a current reader:
  - each card's `answer`;
  - the reading of a card `type` this version does not know as a concept, which serves a newer function;
  - the back's text form on stored cards, which search, the card key, screen readers and the web read;
  - every card already stored, which stays readable.

## Consequences

- One version of the contract and of the parser exists. A reader no longer has to tell which fields serve which build.
- A change to the contract deploys the function and needs the app built from the same `main`. An app built before it refuses the function's cards until it is rebuilt.
- Once a build is in a store, every contract change returns to keeping older builds working. That is the cost this rule only defers.

## Signs the decision was wrong

- An install outside the owner's control, such as a tester's build, stops importing photos after a function deploy.
- The switch at the first store release is missed, and a released build breaks on a contract change.
