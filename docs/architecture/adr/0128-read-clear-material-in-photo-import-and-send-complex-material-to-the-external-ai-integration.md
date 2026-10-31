# ADR 0128: Read clear material in photo import, and send complex material to the external-AI integration

> Status: accepted
> Date: 2026-11-01

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **The owner's direction of 2026-11-01** on #493: photo import assumes clear material, such as a printed word list or glossary. Complex handwriting and notes are meant for the external-AI route (#496), not for the prompt. The prompt's job is to analyse the material and find what to learn in it.
- **The reported failure**: a simple, ordered English word list came back with the list's numbers as the cards' fronts.
- **Prompt v10 as ADR 0124 left it** was the owner's store version 3 tuned under the direction of 2026-10-29. It kept version 3's lines for handwriting and mixed pages: an input of "인쇄물, 필기, … 강의 노트, 수식, 다이어그램, 코드", handwritten memos in the analysis, a handwritten addition as a learning item of its own, and an example "인쇄되거나 필기된". The owner's 2026-10-29 answer on handwriting is superseded by this scope.
- **The external-AI integration** (#496, [ADR 0126](0126-connect-claude-and-chatgpt-through-one-remote-mcp-server-acting-as-the-signed-in-user.md), merged in PR #507) lets the user work through a page with Claude or ChatGPT and add the cards through the MCP server. The owner named it for a complex page whose photo import fails: "저런 복잡한 사진의 경우 … ai 에이전트 연동을 이용하여 사용자가 직접 소통하며 진행되어야 해" (#496).
- **#412** researched a two-stage photo import, the page's sections first, then a card shape for each, and #414 measured it (`docs/eval/two-stage.md`). Both aimed at complex pages.
- **Alternatives considered:**
  - **More prompt rules for complex pages**: tables, marks, handwritten additions. The owner ruled it out on 2026-10-29 and again on 2026-11-01, and each such rule is written for one kind of page, which the prompt's first principle forbids.
  - **The two-stage pipeline of #412.** It is two or more calls a photo for the pages this scope leaves to the integration.
  - **A rule for numbered word lists alone.** A number before an entry is one case of a list's marks; a bullet or an ordinal is another, so the rule is stated for every list.

## Decision

- **Photo import is for clear material**: a page whose entries it lists plainly, such as a printed word list, glossary, bilingual table or dictionary page. The prompt analyses the material and finds what it teaches, its words, terms or facts, and makes a card of each.
- **Complex material goes to the external-AI integration** (#496, ADR 0126): handwriting, dense notes and pages marked up in pen. The prompt holds no rule written for it. Such a photo is still sent and read like any other.
- **A list's numbering, ordinals and bullets are never a card's front or part of it.** They place an entry; they are not what it teaches.
- **Prompt v10 is retuned for this scope.** It states that it reads clear material, analyses it and finds what it teaches. It states the list rule as a principle and as a check, and drops version 3's lines for handwriting and complex notes. It stays general, with no rule for one subject or layout, and the output contract (ADR 0124) is unchanged. This refines ADR 0124's prompt v10.
- **The eval holds a numbered English–Korean word list**, "1. abandon 버리다" a line, in print under the mild distortion and under the harsh one, samples 88 and 89. Its report gives, per configuration and per vocabulary page, the share of returned cards whose front holds a list's number, which must be 0.
- **#412 is closed as out of scope.** The two-stage experiment and its report stay as the record; no further run is planned.
- ADR 0124's ship rule stands: the PM's paid run of `--prompts v9,v10` decides whether v10 ships.

## Consequences

- The prompt is shorter, and every line of it applies to the material photo import is for.
- A user's complex page may come back with fewer or worse cards than under version 3. Getting cards from such a page is the integration's job, which ships with #496.
- A card made from a numbered list no longer carries the list's position. Where an order is what is to be learnt, a card asks for it, as a process card does, rather than keeping the list's numbers on its front.
- The eval's notes pages, handwriting among them, stay in the sample set and in the report. They now measure material outside photo import's scope, so a lower coverage there is no reason by itself to hold a prompt back.

## Signs the decision was wrong

- Users keep photographing complex pages and saving few cards, rather than using the integration: the scope does not match how photo import is used.
- The numbered fronts stay above 0 under prompt v10: a general sentence does not keep the model off a list's marks.
- Clear material scores worse under v10 than under v9 in vocabulary F1: dropping the lines for complex material cost the clear material something.
