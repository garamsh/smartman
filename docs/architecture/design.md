# Design

The app's design language: the principles every screen follows for usability and visual design together, where each is applied today, and the theme, tokens and components that carry them.

## Current decisions

### Principles

Every screen is designed to be simple, intuitive and easy to use. A new screen or a change to one follows these, and copies the idiom named under each.

1. **One primary action per screen.** It is the most prominent element and sits in thumb reach, at the bottom. Secondary actions are quieter or live in a menu.
   - Study: the current card is the only action, low on the screen; closing is a small icon at the top.
   - Card editor: "저장하고 다음 카드" is the filled button in the bottom bar, "저장" outlined beside it; editing an existing card offers "저장" alone.
   - Deck list and card list: the bottom bar holds the screen's add action; rename and delete sit in the card list's menu.
   - Every sheet: `AppSheet` pins its actions at the bottom, full width, with the primary one last; "새 덱" and "이름 바꾸기" have one field and one primary, "만들기" or "저장".
   - Every screen: `AppButton`'s variants rank the actions, one primary fill per screen or sheet.
2. **Content over chrome.** No label, hint or heading restates what the screen already shows. Remove before adding.
   - Study: no deck name, no answer button and no hint text.
   - Card list: the rows show front and back with no column headings; the deck name is the only title.
   - Every sheet: `AppSheet` has a title and at most one or two sentences of body; `AppTextField` shows its label once, above the field.
3. **Direct manipulation where it is natural.** Swipe to answer, tap to toggle. Every gesture has an accessible alternative: a semantics action or a visible control.
   - Study: a swipe answers, with the custom actions "안다" and "모른다"; a tap toggles a previous answer, with a tap hint.
   - Deck list: a long-press selects decks; the rows expose their selected state, and selection mode has visible controls.
   - Every sheet: a drag or a tap outside dismisses it, and Android's back does the same.
4. **Never wait.** Act at once and sync in the background. Show progress only for work the user asked for and must wait on, such as photo extraction.
   - Study: the next card is on screen before the answer's write finishes.
   - Photo import: extraction shows the photo, a progress bar and skeleton rows, and can be cancelled.
   - Account: a theme choice applies at once and is stored after.
   - Account and photo review: `AppButton`'s loading state shows progress in the button the user pressed, and the button cannot be pressed twice.
5. **Correct, don't confirm.** Prefer undo or a toggle to a confirmation sheet. Confirm only what cannot be undone: deleting a deck, a card with its study history, or the account.
   - Study: any answer of the session is corrected by a tap, with no confirmation.
   - Card editor: a duplicate front opens a sheet that offers to add anyway or open the existing card; nothing is overwritten.
   - Card list, card editor and account: deleting a deck, deleting a card, and signing out with unsynced changes are confirmed through `showAppConfirm`, which states the consequence in one sentence beside a red final button.
6. **One visual language.** Theme tokens only; the split card, question left and answer right, wherever a card appears; rounded surfaces on the ground colour; 44 pt minimum targets.
   - Study, card editor and duplicate sheet: the same split card.
   - Deck list and card list: rows on rounded surfaces over the ground.
   - Every screen and sheet: the tokens below and the components that use them.
7. **Meaningful motion** that shows where things go. Reduce motion is respected.
   - Study: an answered card flies off and rises into the stack while the next emerges from below; under reduce motion they cross-fade.
   - Every sheet: `showAppSheet` slides it up with the platform's sheet motion, and shows it at once under reduce motion. Every `AppButton` shows pressed feedback, and a filled one gives a light haptic on iOS.
8. **Plain-language states.** Empty, offline and error states say what happened and what to do next, in one or two short sentences.
   - Deck list and card list: an empty list says how to start, and a search with no match says to try other words.
   - Every screen: a storage failure says what failed and to try again.

### Theme

- `app/lib/shared/theme.dart` holds every colour token as `AppColors`, a light and a dark set, and the light and dark `ThemeData` built from them ([ADR 0011](adr/0011-shared-app-theme-bundled-font-and-today-builder.md)). No other file under `app/lib/` writes a colour; `app/test/shared/theme_test.dart` fails when one does.
- Light: ground `#EEF1F5`, surface `#FFFFFF`, ink `#16191F`, muted `#5A6170`; "Know" green `#1B7F45` with its dot `#1E9E4A`; "Don't know" red `#E0352B` for dots and tints, `#B71C1C` for text.
- Dark: ground `#0F1115`, surface `#1A1D23`, ink `#ECEEF2`, muted `#A3A9B4`; green `#4CC27A` with its dot `#5BD08A`; red `#FF6B60` for dots and tints, `#FF8A80` for text; a previous card's depth steps darker toward the ground.
- Every text pair the screens draw meets WCAG AA (4.5:1) and every answer dot 3:1, in both themes; `app/test/shared/theme_test.dart` checks the ratios.
- The font is IBM Plex Sans KR, bundled under `app/assets/fonts/` with its OFL licence; nothing is downloaded at run time.
- The user picks 시스템 (the default), 라이트 or 다크 in the account screen's "화면" section. The choice is stored on the device with `shared_preferences`, read before the first frame, and applied at once.

### Tokens

`app/lib/shared/theme.dart` holds every token beside the colours ([ADR 0021](adr/0021-type-and-spacing-scales-and-a-shared-component-layer.md)). No other file under `app/lib/`, except the components in `app/lib/shared/ui/`, writes a spacing or font-size number; the study screen's computed geometry in `app/lib/study/src/study_style.dart` is the one exception, listed in `app/test/shared/theme_test.dart`.

- **Type**, `AppType`, all IBM Plex Sans KR, and the theme's `TextTheme` built from it:

  | Role | Size / line / weight | Use |
  |---|---|---|
  | display | 28 / 36 / 700, −0.5 | a home screen's title: the deck list, sign-in |
  | title | 22 / 30 / 700, −0.3 | a pushed screen's title, the deck name, a card's question, the summary |
  | headline | 20 / 28 / 700 | a sheet's title |
  | body | 16 / 24 / 400 | running text, field text, card rows |
  | bodyStrong | 16 / 24 / 600 | a row's title |
  | label | 15 / 20 / 600 | a button |
  | secondary | 14 / 20 / 400 | a sheet's body, a line under a title |
  | caption | 13 / 18 / 400 | a row's second line, a note, an error |
  | section | 13 / 18 / 600 | a section label, a field's label |
  | micro | 12 / 16 / 400 | a chip, a hint |

- **Spacing**, `AppSpace`: 4, 8, 12, 16, 20, 24, 32, 40. The screen gutter is 20 and the gap between rows is 8.
- **Radii**, `AppRadius`: sheet 28, card 24, row 18, button and field 16; a chip is fully rounded.
- **Heights**, `AppSize`: a call to action 56, a button 52, a field 48, a tap target at least 44.
- **Shadows**, `AppShadow`: card, for a surface resting on the ground, and raised, for the current study card and the summary.

### Components

`app/lib/shared/ui/` holds the shared, domain-free components every screen builds from ([ADR 0021](adr/0021-type-and-spacing-scales-and-a-shared-component-layer.md)). A screen uses them rather than building the same pattern from Material widgets.

- **`AppButton`** — every button in content and in bars. Variants: primary (ink fill, the one primary action), study (green fill, starts a session), secondary (outlined), destructive (red text), destructiveFinal (red fill, the last step of a destructive action), and text (a quiet action, such as one in a top bar). Size cta (56) for the actions at the bottom of a screen or sheet, regular (52) elsewhere. States: pressed, disabled, and loading.
- **`AppTextField`** — every text field: a label above, a hint inside, an error below, and a counter where a limit exists. The label, field and error are read as one.
- **`AppSheet`** with **`showAppSheet`** — every modal: a drag handle, a title, an optional body, content, and actions pinned at the bottom above the keyboard, the primary last.
- **`showAppConfirm`** — every irreversible action: a sheet that states the consequence in one sentence, with a cancel and a red final button.
- **`AppListRow`** — a row with a title, an optional second line and optional leading and trailing widgets, read as one node: the deck rows and the photo import deck chooser. **`AppRowSurface`** is its rounded surface alone, for rows with their own layout: the card rows, the photo review rows and the skeleton rows. On a sheet a row takes the ground colour.
- **`AppSectionLabel`** — a label over a group of rows, read as a heading: "내 덱 n", "이미 있는 카드 n개", "화면", and the answer in the whole-card sheet.
- **`AppChip`** — a fully rounded label, or a button when it has an action: the "오늘 n" chip, the camera's deck chip, and the duplicate option chip.

Material widgets a screen still uses directly — `IconButton`, `PopupMenuButton`, `SegmentedButton`, `Checkbox`, `LinearProgressIndicator` — are themed in `app/lib/shared/theme.dart`.

### Checks

- Each screen and each sheet is checked against Flutter's `labeledTapTargetGuideline`, `androidTapTargetGuideline` and `textContrastGuideline` in both themes, in `app/test/widget_test.dart`, `app/test/account/account_screen_test.dart`, `app/test/study/study_screen_test.dart`, `app/test/photo_import/photo_import_screen_test.dart` and, for each component, `app/test/shared/ui/`.
- `app/test/shared/theme_test.dart` fails on a spacing or font-size literal outside the theme and the components, and on a dialog, or a sheet opened other than through `showAppSheet`.
- `app/test/screenshots/screenshots_test.dart` draws every screen and sheet in both themes, in Korean at a phone's size, when run with `--update-goldens --dart-define=SCREENSHOTS=true`; it writes them to `app/build/screenshots/` and is skipped otherwise.

## Rationale

- [ADR 0007](adr/0007-study-swipe-screen-and-session-toggle.md) records the study screen these principles generalize.
- [ADR 0011](adr/0011-shared-app-theme-bundled-font-and-today-builder.md) records why the theme is one file with a token extension, why the font is bundled, and why the choice is stored in `shared_preferences`.
- [ADR 0021](adr/0021-type-and-spacing-scales-and-a-shared-component-layer.md) records why the scales sit in the theme file, why the components are a shared layer of their own, and why every modal is a sheet.
- Issue #58 records the scales and the component set as the PM decided them on 2026-10-15.
- Issue #22 records the principles, the tokens and the screens as the owner approved them on 2026-10-15.

## Open questions

- Whether deleting a card should become undoable, so it needs no confirmation. Its study history is deleted with it today, which an undo would have to restore.
