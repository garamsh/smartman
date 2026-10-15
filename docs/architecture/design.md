# Design

The app's design language: the principles every screen follows for usability and visual design together, where each is applied today, and the theme that carries them.

## Current decisions

### Principles

Every screen is designed to be simple, intuitive and easy to use. A new screen or a change to one follows these, and copies the idiom named under each.

1. **One primary action per screen.** It is the most prominent element and sits in thumb reach, at the bottom. Secondary actions are quieter or live in a menu.
   - Study: the current card is the only action, low on the screen; closing is a small icon at the top.
   - Card editor: "저장하고 다음 카드" is the filled button in the bottom bar, "저장" outlined beside it; editing an existing card offers "저장" alone.
   - Deck list and card list: the bottom bar holds the screen's add action; rename and delete sit in the card list's menu.
2. **Content over chrome.** No label, hint or heading restates what the screen already shows. Remove before adding.
   - Study: no deck name, no answer button and no hint text.
   - Card list: the rows show front and back with no column headings; the deck name is the only title.
3. **Direct manipulation where it is natural.** Swipe to answer, tap to toggle. Every gesture has an accessible alternative: a semantics action or a visible control.
   - Study: a swipe answers, with the custom actions "안다" and "모른다"; a tap toggles a previous answer, with a tap hint.
   - Deck list: a long-press selects decks; the rows expose their selected state, and selection mode has visible controls.
4. **Never wait.** Act at once and sync in the background. Show progress only for work the user asked for and must wait on, such as photo extraction.
   - Study: the next card is on screen before the answer's write finishes.
   - Photo import: extraction shows the photo, a progress bar and skeleton rows, and can be cancelled.
   - Account: a theme choice applies at once and is stored after.
5. **Correct, don't confirm.** Prefer undo or a toggle to a confirmation dialog. Confirm only what cannot be undone: deleting a deck, a card with its study history, or the account.
   - Study: any answer of the session is corrected by a tap, with no dialog.
   - Card editor: a duplicate front opens a sheet that offers to add anyway or open the existing card; nothing is overwritten.
6. **One visual language.** Theme tokens only; the split card, question left and answer right, wherever a card appears; rounded surfaces on the ground colour; 44 pt minimum targets.
   - Study, card editor and duplicate sheet: the same split card.
   - Deck list and card list: rows on rounded surfaces over the ground.
7. **Meaningful motion** that shows where things go. Reduce motion is respected.
   - Study: an answered card flies off and rises into the stack while the next emerges from below; under reduce motion they cross-fade.
8. **Plain-language states.** Empty, offline and error states say what happened and what to do next, in one or two short sentences.
   - Deck list and card list: an empty list says how to start, and a search with no match says to try other words.
   - Every screen: a storage failure says what failed and to try again.
   - Browse: offline, it says the public decks appear once connected; the deck menu says why publishing is disabled.

### Theme

- `app/lib/shared/theme.dart` holds every colour token as `AppColors`, a light and a dark set, and the light and dark `ThemeData` built from them ([ADR 0011](adr/0011-shared-app-theme-bundled-font-and-today-builder.md)). No other file under `app/lib/` writes a colour; `app/test/shared/theme_test.dart` fails when one does.
- Light: ground `#EEF1F5`, surface `#FFFFFF`, ink `#16191F`, muted `#5A6170`; "Know" green `#1B7F45` with its dot `#1E9E4A`; "Don't know" red `#E0352B` for dots and tints, `#B71C1C` for text.
- Dark: ground `#0F1115`, surface `#1A1D23`, ink `#ECEEF2`, muted `#A3A9B4`; green `#4CC27A` with its dot `#5BD08A`; red `#FF6B60` for dots and tints, `#FF8A80` for text; a previous card's depth steps darker toward the ground.
- Every text pair the screens draw meets WCAG AA (4.5:1) and every answer dot 3:1, in both themes; `app/test/shared/theme_test.dart` checks the ratios.
- A card has radius 24; a row, field or button 16. Buttons are at least 52 high.
- The font is IBM Plex Sans KR, bundled under `app/assets/fonts/` with its OFL licence; nothing is downloaded at run time.
- The user picks 시스템 (the default), 라이트 or 다크 in the account screen's "화면" section. The choice is stored on the device with `shared_preferences`, read before the first frame, and applied at once.

### Checks

- Each changed screen is checked against Flutter's `labeledTapTargetGuideline`, `androidTapTargetGuideline` and `textContrastGuideline` in both themes, in `app/test/widget_test.dart`, `app/test/study/study_screen_test.dart`, `app/test/photo_import/photo_import_screen_test.dart` and the sharing screens' tests under `app/test/sharing/`.

## Rationale

- [ADR 0007](adr/0007-study-swipe-screen-and-session-toggle.md) records the study screen these principles generalize.
- [ADR 0011](adr/0011-shared-app-theme-bundled-font-and-today-builder.md) records why the theme is one file with a token extension, why the font is bundled, and why the choice is stored in `shared_preferences`.
- Issue #22 records the principles, the tokens and the screens as the owner approved them on 2026-10-15.

## Open questions

- Whether deleting a card should become undoable, so it needs no confirmation. Its study history is deleted with it today, which an undo would have to restore.
