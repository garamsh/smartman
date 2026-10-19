# ADR 0072: Store a vocabulary card's senses as a typed block, and show each label in brackets before its meaning

> Status: accepted
> Date: 2026-10-19

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **The owner's decision**, recorded on issue #228 on 2026-10-19:
  - a vocabulary sense shows the same way whatever the book prints: the model records what a label is, and the app decides how it looks;
  - a label is transcribed, never inferred.
- **The contract, as the PM revised it on #228:**
  - a sense is `{labels, meaning, examples}`;
  - `labels` holds every label the page prints for that sense, in order, each `{kind, category, text}`:
    - a part of speech has `kind: 'part_of_speech'` and a `category` from a closed list;
    - any other label has `kind: 'other'` and `category: null`: a semantic class such as 사물, a register, a field, a gender, or a part of speech the list does not hold;
  - `meaning` is a translation or a definition, as printed;
  - `examples` are the sentences the page prints under that sense.
- **The display, as the PM recorded it on #228:**
  - a part of speech shows as its fixed short form, as `[명] 사과`;
  - another label shows as printed, in the same brackets;
  - several labels show in order;
  - a sense with no label shows its meaning alone;
  - each sense is one line;
  - the label is its own span, with a gap narrower than a word space, one design spacing step, before the meaning;
  - the text fallback has one ordinary space;
  - the import list's "품사 표시" hides part-of-speech labels only.
- **Storage** follows [ADR 0068](0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md)'s typed content: a side is a `jsonb` array of blocks, so a new block type needs no migration.
- **Today** the app writes a vocabulary back as text with each label baked in as the book printed it (`app/lib/photo_import/src/import_list.dart` on `main` at `42d9132b4e9c15135844afc57771f6709f6f050e`). How a label looks is therefore fixed at import.
- **#250**, the owner on 2026-10-19: nothing is released, so until the first store release no compatibility with older app builds is kept. #228's PR 1 (the function) and PR 2 (this app and web change) may merge in either order.
- **Out of scope:** migrating existing stored cards is #228's PR 3. It starts with a read-only dry run and stops for the PM.
- Alternatives considered:
  - **Labels baked into the back's text**, as today: a card shows each book's own form, and the toggle can act only before saving.
  - **One `category` per sense**, #228's first contract: it cannot hold a semantic class beside a part of speech, as in '기차 [사물] 철도 위를 다니는 긴 차'.
  - **A space between label and meaning on screen**: the owner asked for a narrower gap there.

## Decision

- **A `senses` block** (`SensesContent` in `app/lib/deck/src/content.dart`, `kind: "senses"` in `web/src/features/decks/card-content.ts`) holds one or more senses: `{"type": "senses", "payload": {"senses": [{"labels": [...], "meaning": "...", "examples": [...]}]}}`.
  - Each label is `{"kind": "part_of_speech", "category": "<name>", "text": "..."}` or `{"kind": "other", "category": null, "text": "..."}`.
  - `text` is the label as printed, without the brackets or parentheses the page encloses it in.
  - A sense needs non-empty `meaning`, a `labels` list and an `examples` list of text. A label needs non-empty `text` and a known `category` for a part of speech, or `null` for another label. A block that breaks this shape fails decoding, on the phone and on the web, as ADR 0068's blocks do.
- **The parts of speech and their short forms:**

  | `category` | Shown as |
  |---|---|
  | `noun` | 명 |
  | `verb` | 동 |
  | `adjective` | 형 |
  | `adverb` | 부 |
  | `pronoun` | 대 |
  | `preposition` (or postposition) | 전 |
  | `conjunction` | 접 |
  | `interjection` | 감 |
  | `determiner` (articles included) | 관 |
  | `numeral` | 수 |
  | `particle` | 조 |
  | `auxiliary` | 조동 |
  | `classifier` | 양 |
  | `phrase` (idiom or set phrase) | 구 |

- **The function's JSON**, for #228's PR 1: each vocabulary card's `senses` item is the sense above, keys `labels`, `meaning` and `examples`, `examples` present even when empty. The app reads it through `deck`'s `decodeSense` and refuses any other sense shape, the old `{pos, meaning}` included, as `ServiceFailed`. A card from a function before senses keeps its one sense, its `partOfSpeech` without brackets as a part of speech where it is a short form above, or else another label.
- **What a vocabulary card stores:**
  - its meaning side is a `senses` block of the kept senses, then, when the extras are shown, a text block of them;
  - "뜻 → 단어" puts that block on the front, so its key is the senses' text fallback;
  - the examples are stored and not drawn.
- **The text fallback.** A senses block's text is one line per sense, each label in brackets and one space before the meaning: `[명] [사물] 기차`. Search, a screen reader, a merged back and the card key read it.
- **Drawing:**
  - each label is its own span, `[명]`, with a gap of one design spacing step after it, before the next label or the meaning;
  - on the phone the gap is the closing bracket's letter spacing, `AppSpace.s4`, so the line stays one paragraph that fits and wraps as text (`sensesSpan`); on the web it is `mr-1` on the label's span (`SensesText`);
  - the study cards, the whole-card sheet and dialog, the card preview, the deck's rows on the phone and the web, and photo import's list all draw a side through these;
  - on the web the study page's server draws such a card's sides, as `structure.md` asks of a client module.
- **"품사 표시"** off saves the block without its part-of-speech labels, keeping every other label.
- **The card editor** keeps a senses side while its text is left as it was. An edited side becomes a text block, its labels as typed, as a note under the answer says: "답을 고치면 [명] 같은 표시도 글자로 저장돼요."
- **A merged back** is appended as a text block of the imported lines, drawn under the senses.
- **Merge order** with PR 1 is either (#250).

## Consequences

- One sense looks the same from every book, and the next display change is the app's alone.
- Until PR 1 deploys, the deployed function's `{pos, meaning}` senses are refused, so an extraction that holds a vocabulary card fails with `ServiceFailed`; the owner's development build takes both, as #250 accepts.
- A label's own text is kept, so a later display can use it.
- Editing a vocabulary answer by hand loses its structure, by the note's warning.
- Existing cards keep their text backs until #228's PR 3 migrates them.

## Signs the decision was wrong

- Users read the narrow gap as a missing space, or as the label and meaning run together.
- A book's label maps poorly to the closed list, and its `other` labels crowd the line.
- Users edit vocabulary answers often enough that losing the structure on edit matters.
