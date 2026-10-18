# ADR 0065: Import a photo's cards from one list of sections, each with its form menu, row checks and an edit sheet

> Status: accepted
> Date: 2026-10-19

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- [ADR 0060](0060-choose-which-topics-to-memorise-and-their-card-shape-before-review-from-the-one-call-s-cards.md) put a choice screen, ①, before [ADR 0057](0057-group-a-photo-s-cards-by-topic-on-review-with-a-switch-per-topic-and-swipes-per-card.md)'s Review. On ①, the user chose topics and set each topic's card shape on a sample card.
- [ADR 0063](0063-ask-prompt-v6-for-atomic-typed-cards-and-a-vocabulary-entry-s-senses-and-eval-long-answers-and-senses.md), merged in #202, gives each card a `type`, and gives a vocabulary card its `senses` in page order, with `extras` and a `pronunciation` when the page prints them.
- **Issue #200's owner comment of 2026-10-18.** The model decides each card's form, and the user only toggles items. Identify cards are their own items, off by default. The shape options on ① go.
- **Issue #201** asks for a vocabulary card's senses one per line, and an edit sheet in place of the pencils.
- **#201's comment of 2026-10-18** asks for a card shape remembered per deck. The owner's latest comment on #201 picks the canvas board "후보 D. iOS 기본 목록 + 묶음 메뉴" (`https://claude.ai/artifact/9GxVB2RjZ36BtgcyBr6UmD`): one screen, no ①, and inset grouped sections. Each section has a pull-down form menu; each row has a circular check and opens an edit sheet on a tap.
- **Ten defaults.** The worker put ten defaults to the coordinator on 2026-10-19, and the PM confirmed all ten. They are numbered (1) to (10) below.
- Alternatives considered:
  - **Keeping ① with board D's menu on Review.** It keeps two screens, which the owner's comment removes.
  - **A separate "카드 모양" sheet**, #201's earlier comment and the canvas board "사진 ①' 카드 모양 (단어장)". Board D's section menu sets the same settings where the cards are listed, so a second place to set them would split one choice in two.
  - **Topic switches beside the row checks.** Two controls would decide one row. The checks and the menu's "이 묶음 빼기" replace the switches.
  - **A Cupertino pull-down menu.** Its look comes from iOS alone. Flutter's `MenuAnchor`, styled in the theme, draws board D's menu on both platforms.

## Decision

- **Flow.** The photo goes to Extracting, then to one list. Screen ① and Review are replaced, and there is still one call.
- **The list**, as board D draws it:
  - **Top bar.** "취소" on the left closes the import and writes nothing; "다시 찍기" is on the right.
  - **Title (9).** "단어 n개를 찾았어요" when every row is vocabulary, else "카드 n장을 만들었어요". n counts the rows once candidates of one card key are combined. Under the title: "덱 '<name>'에 추가돼요". The name opens the deck chooser.
  - **Sections.** One inset grouped section per topic and kind, in the order each first appears, with the topic's identify cards in a section of their own. A card with no topic goes under "이 페이지". The header shows the topic and its row count, and on the right the section's form, which opens its menu.
  - **Rows.** A leading circular check includes or leaves out the row. The front sits on the left at 44%, and the back on the right, one line per sense. A tap opens the edit sheet.
  - **(8)** A swipe left leaves a row out, as its check does. Only the check puts it back.
  - **The button** "카드 n장 추가" sits over a fade at the bottom. It counts each card the forms make, and is disabled at 0.
- **The form menu (1, 2, 4).**
  - A vocabulary section offers "단어 → 뜻", "뜻 → 단어" and "양쪽 다 만들기", with a check on the one chosen.
    - (2) "양쪽 다" saves a second, reversed card per row, so the count doubles.
    - A separated group follows: "첫 뜻만" and "품사 표시" (on). (1) Where the section's cards carry them, "발음 표시" puts the pronunciation under the word and "유의어 등 표시" adds the extras as last lines of the back; both are off by default.
  - (4) A note section offers "앞뒤 바꾸기".
  - Every menu ends with "이 묶음 빼기", which leaves out every row, or "이 묶음 넣기" once none is included.
  - (4) An identify section is titled "판별 · <topic>", and its rows start left out.
  - (1) There is no separate card-shape sheet.
- **(3) Memory.** A section's form is stored on the device per deck id and section, the topic's name among its key, in one stored JSON value. It is applied when the list opens into that deck or the user picks it. For a new deck, it is stored under the new deck's id on save.
- **(5) The edit sheet.** A sheet with a "앞면" field.
  - A vocabulary row lists one row per sense: a check to keep or drop it, a text field, and a drag handle to reorder it.
  - A note row has a "뒷면" field.
  - "완료" applies the edits and is disabled while every sense is dropped. A dismissal applies none.
  - An edit whose front the deck holds keeps the row included, marked.
- **(7) Duplicates.** A row whose card the deck already holds starts left out, with "이미 덱에 있어요" under it. Checked, it merges back into the deck's card by `deck`'s merge-back rule.
- **(6) No coach.** The Review coach goes, and so does its stored flag. The check makes including a row visible, so there is no gesture left to teach.
- **(10) The menu's look.** `MenuAnchor`, themed in `theme.dart` after board D:
  - 13 px corners, as the radius token `menu`, and a soft shadow;
  - leading checkmarks, and a heavier separator between groups;
  - 16 px items at least 44 high.
- **Senses.** A vocabulary card's back is its kept senses one per line, each label shown or not by the form, and so it is saved. The deck and sync need no schema change.
- **Components.** `AppChip`'s action kind and choice kind lose their only users, Review's deck chip and ①'s pills, and are removed. `AppCoach`, which study's coach shares since [ADR 0064](0064-teach-study-with-a-first-use-finger-coach-and-show-the-day-s-last-card-and-a-brief-notice-when-a-day-resumes.md), then serves study alone, so it moves into `study` as `StudyCoach`, as `structure.md` asks of a foundation file one domain alone uses.
- **Supersessions.**
  - This replaces ADR 0060.
  - It replaces ADR 0057's Review: its topic switches, its swipes both ways, its struck-through rows, its in-place editing and its coach.

## Consequences

- One screen holds every choice the user makes over a photo's cards, and nothing is chosen on a sample card.
- A word with several senses is studied with every sense on its back, one per line, unless the menu keeps the first.
- A form set once is used again for the same deck and topic, so later photos of the same book need no choices.
- "양쪽 다" doubles a section's cards, and its reversed cards are keyed by the meaning.
- Rows left out stay listed, so a row left out by mistake can be put back from its check.

## Signs the decision was wrong

- Users leave every row checked and never open a menu, so the forms are not found.
- Users open the edit sheet mostly to drop senses, so the menu needs a per-sense choice.
- Forms remembered by topic name apply to the wrong pages, because books reuse section names, such as "단어".
- Users miss the swipe right that put a card back, or the coach.
