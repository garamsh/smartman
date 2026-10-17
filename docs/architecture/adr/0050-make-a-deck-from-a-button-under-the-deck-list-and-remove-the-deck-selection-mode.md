# ADR 0050: Make a deck from a button under the deck list, and remove the deck selection mode

> Status: accepted
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #164 records the owner's decision of 2026-10-18 on the phone's 덱 tab: remove the "선택" and "새 덱" buttons from its top bar, and make 새 덱 a button at the bottom, in the style of "공개 덱 둘러보기", in the order 새 덱 만들기 then 둘러보기. The selection mode goes with its button.
- On `main` at `547e342679953bfed96f5c233f8d5745d23f7656`, the 덱 tab's top bar holds "내 덱 n", "선택" and "새 덱". "선택", or a long-press on a row, enters a selection mode whose "학습 (n)" studies the selected decks in one session ([ADR 0009](0009-multi-deck-session-and-random-queue-order.md), [ADR 0036](0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md)).
- 오늘's "모두 학습" studies every deck with cards today in one session, and each deck's row on 오늘 and its page study that deck. A session still takes a `DeckSelection`; only the way to pick several decks by hand goes.
- The web has neither button: it creates no deck (issue #91) and never had the selection mode.

## Decision

- **Top bar.** The 덱 tab's top bar holds "내 덱 n" alone.
- **Under the list.** After the deck rows come "새 덱 만들기", with the line "새 덱을 시작할 방법을 골라요", which opens the existing new-deck sheet, then, with sharing, "공개 덱 둘러보기". Both are rows on an outline with an icon, a title, a line and a chevron.
- **No selection.** The selection mode, its bar, its strings and `DeckRow`'s selected state are removed. A tap on a row opens the deck; with no long-press handler, a long-press opens it as a tap does.
- **Supersessions.** This replaces ADR 0009's selection mode on the deck list and ADR 0036's "선택", "새 덱" in the 덱 tab's top bar and its long-press selection.

## Consequences

- Making a deck is one tap further down the tab once the list is long, and always at the list's end.
- Studying several chosen decks together is no longer possible; 오늘's "모두 학습" covers every deck with cards today.
- `DeckRow` draws one state, so the 덱 tab's rows read the same to a screen reader as they look.

## Signs the decision was wrong

- Users with many decks cannot find "새 덱 만들기" at the end of a long list.
- Users ask to study a few chosen decks together, which only every deck or one deck now allows.
