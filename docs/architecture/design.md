# Design

The app's design language: the principles every screen follows for usability and visual design together, where each is applied today, and the theme, tokens and components that carry them.

## Current decisions

### Principles

Every screen is designed to be simple, intuitive and easy to use. A new screen or a change to one follows these, and copies the idiom named under each.

1. **One primary action per screen.** It is the most prominent element and sits in thumb reach, at the bottom. Secondary actions are quieter or live in a menu.
   - Study: the current card, low on the screen, with its two answer buttons under it; closing is a small icon at the top. On the completion card, "계속 학습" is the one primary fill, with "그만하기" a quiet text button below it.
   - Card editor: "저장하고 다음 카드" is the filled button in the bottom bar, "저장" outlined beside it; editing an existing card offers "저장" alone.
   - Deck list and card list: the bottom bar holds the screen's add action; rename and delete sit in the card list's menu.
   - Every sheet: `AppSheet` pins its actions at the bottom, full width, with the primary one last; "새 덱" and "이름 바꾸기" have one field and one primary, "만들기" or "저장".
   - Sign-in: the stacked logo and its two lines sit on the ground's panel in the upper part, and Google's button, with the quieter Apple slot and the terms below it, at the bottom.
   - Every screen: `AppButton`'s variants rank the actions, one primary fill per screen or sheet.
2. **Content over chrome.** No label, hint or heading restates what the screen already shows. Remove before adding.
   - Study: no deck name and no hint text, but for the first session's guide of three lines; the completion card carries no sentence beyond its heading and one line of counts, and practice is not marked apart from studying.
   - Card list: the rows show front and back with no column headings; the deck name is the only title.
   - Every sheet: `AppSheet` has a title and at most one or two sentences of body; `AppTextField` shows its label once, above the field.
3. **Direct manipulation where it is natural.** Swipe to answer, tap to toggle. Every gesture has an accessible alternative: a semantics action or a visible control.
   - Study: a horizontal swipe answers, with the answer buttons and the custom actions "안다" and "모른다"; a vertical drag scrolls the stack and the current card together; a horizontal drag on the centred previous card changes its answer, with the custom action "안다로 바꾸기" or "모른다로 바꾸기".
   - Deck list: a long-press selects decks; the rows expose their selected state, and selection mode has visible controls.
   - Every sheet: a drag or a tap outside dismisses it, and Android's back does the same.
4. **Never wait.** Act at once and sync in the background. Show progress only for work the user asked for and must wait on, such as photo extraction.
   - Study: the next card is on screen before the answer's write finishes.
   - Photo import: extraction shows the photo, a progress bar and skeleton rows, and can be cancelled.
   - Account: a theme choice applies at once and is stored after.
   - Photo import: a detail level switch recomposes every answer at once and is stored after.
   - Account and photo review: `AppButton`'s loading state shows progress in the button the user pressed, and the button cannot be pressed twice.
5. **Correct, don't confirm.** Prefer undo or a toggle to a confirmation sheet. Confirm only what cannot be undone: deleting a deck, a card with its study history, or the account.
   - Study: any answer of the session is corrected by a drag on the centred card, or its action, with no confirmation.
   - Card editor: a duplicate front opens a sheet that offers to add anyway or open the existing card, and is dismissed to do neither; nothing is overwritten.
   - Card list, card editor, account and preview: deleting a deck, deleting a card, signing out with unsynced changes, deleting the account, and blocking a user are confirmed through `showAppConfirm`, which states the consequence in one sentence above a cancel and, last, a red final button.
6. **One visual language.** Theme tokens only; the split card, question left and answer right, each half's content centred across and down and shrunk toward a floor until its widest word fits, so a word never breaks inside itself while the floor fits, wherever a card appears; rounded surfaces on the ground colour; 44 pt minimum targets.
   - Study, card editor, duplicate sheet and photo review: the same split card, each half centred; `deck`'s `SplitCard` lays out the halves for the study cards, the card preview and the card rows ([`deck.md`](deck.md)).
   - Deck list and card list: rows on rounded surfaces over the ground.
   - Every screen and sheet: the tokens below and the components that use them.
7. **Meaningful motion** that shows where things go. Reduce motion is respected.
   - Study: an answered card flies off and rises into the stack while the next emerges from below; under reduce motion they cross-fade. The current card moves with the stack as it scrolls, the card at the centre grows as the others shrink and dim, and an answer given while scrolled back returns the view to its end; a re-decided card springs back into place, at once under reduce motion.
   - Every sheet: `showAppSheet` slides it up with the platform's sheet motion, and shows it at once under reduce motion. Every `AppButton` shows pressed feedback, and a filled one gives a light haptic on iOS.
8. **Plain-language states.** Empty, offline and error states say what happened and what to do next, in one or two short sentences, in the voice below.
   - Deck list and card list: an empty list says how to start, and a search with no match says to try other words.
   - Deck list and card list: in a backlog, one sentence says new cards wait until the reviews are caught up ([`study.md`](study.md)).
   - Study: with no card left and none answered today, one sentence says there is nothing to study today.
   - Every screen: a storage failure says what failed and to try again.
   - Browse: offline, it says the public decks appear once connected; the deck menu says why publishing is disabled.

### Voice

Every string is written as one writer would write it ([ADR 0024](adr/0024-one-voice-and-a-sheet-action-rule.md)).

- Korean, in `app/lib/shared/l10n/app_ko.arb`, is 해요체 throughout: plain, short, and consistent in its sentence endings ("아직 덱이 없어요.", "카드 3개를 찾았어요"). No sentence ends in 합쇼체 ("…ㅂ니다", "…ㅂ니까"). A label or a button names its action ("로그아웃", "그래도 추가").
- English, in `app_en.arb`, matches it in tone: plain, second person, no exclamation marks.

### Where it lives

- The theme, its tokens, the user's theme choice and the shared components are the app's foundation `app/lib/design/` ([`structure.md`](structure.md), [ADR 0039](adr/0039-name-every-top-level-folder-by-its-responsibility-compose-across-domains-in-a-home-shell-and-keep-seams-off-screens.md)): `design/theme.dart` the tokens and the themes, `design/theme_choice.dart` the choice, and one file per component beside them, with their tests under `app/test/design/`. It imports no domain and holds nothing one domain alone uses.
- `GoogleButtonStyle` is Google's, not the design system's, and only `account` draws it, so it belongs in `account/src/google_button.dart`; the colour check lists that file as its one exception beside the theme and the components.
- On the web, the brand's marks, the skeleton and the theme choice with its store are the foundation `web/src/design/` ([`web.md`](web.md)).
- Not yet moved ([`structure.md`](structure.md) §Not yet moved): they are still in `app/lib/shared/theme.dart`, the choice and `GoogleButtonStyle` included, and `app/lib/shared/ui/`, with their tests under `app/test/shared/`. The paths below name where each file is now.

### Theme

- `app/lib/shared/theme.dart` holds every colour token as `AppColors`, a light and a dark set, and the light and dark `ThemeData` built from them ([ADR 0011](adr/0011-shared-app-theme-bundled-font-and-today-builder.md)). No other file under `app/lib/` writes a colour; `app/test/shared/theme_test.dart` fails when one does.
- The colours are the brand's ([ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)):
  - Light: ground `#F4F6FA`, surface and raised `#FFFFFF`, ink (the brand navy) `#1F2A44`, ink-2 `#4A5470`, muted `#687187`, line `#E3E7EF`, outline `#D5DBE7`, brand tint `#E8ECF5`; "Know" `#1D8054`; "Don't know" `#C2402F` for text, the grade's chip and the destructive fill, `#E2574A` for the tint over a dragged card.
  - Dark: ground `#0E1424`, surface `#18203A`, raised `#232D4D`, ink `#EEF1F7`, ink-2 `#B5BED3`, muted `#9AA3BA`, line `#2A3352`, outline `#2E3858`, brand tint `#2A3560`; "Know" `#5ED39A`; "Don't know" `#FF8577`.
  - The grades of a previous card ([ADR 0035](adr/0035-show-the-previous-and-current-study-card-reach-earlier-cards-three-at-a-time-re-decide-the-centred-card-and-grade-each-card-by-its-colour-and-a-chip.md)): "Know" on `knowCard` inside `knowLine`, light `#EAF6EF` and `#9ED3B6`, dark `#17302A` and `#2E6B50`; "Don't know" on `dontKnowCard` inside `dontKnowLine`, light `#FCEEEC` and `#EBB3AA`, dark `#3A1F24` and `#7A3A36`. The answer buttons' words on the green and red tints are `onKnowTint`, light `#1D6B47`, dark `#5ED39A`, and `onDontKnowTint`, light `#B03A2B`, dark `#FF8577`. The completion card's flame is `streak`, light `#C26A0A`, dark `#F5A623`.
  - One primary colour: a primary action is the navy fill, inverted in the dark theme (`#EEF1F7` under `#1F2A44`). Green and red mean "안다" and "모른다" alone: answers, grades, the answer buttons and the completion card's counts.
  - The today card is the navy (dark: raised) with white text; the deck tiles take one of four tints, light `#E8ECF5`, `#FFF1D6`, `#E3F4EC`, `#FCE8E6`, dark `#2A3560`, `#4A3B1E`, `#1E3F33`, `#4A2624`.
- Every text pair the screens draw meets WCAG AA (4.5:1), and each grade's chip 3:1 on its card and on the ground and the streak's flame 3:1 on the surface, in both themes; `app/test/shared/theme_test.dart` checks the ratios, and `web/src/styles/__tests__/contrast.test.ts` the web's.
- The font is Pretendard 1.3.9, Regular to ExtraBold, bundled under `app/assets/fonts/` with its OFL licence, and read by the web app from there; nothing is downloaded at run time. The files are `public/static/*.otf` of `Pretendard-1.3.9.zip` from the v1.3.9 release of github.com/orioncactus/pretendard (SHA-256 `04be351a74d6bf7d60c480a3087e51d185485d35a52023142af1df19eb8c428a`), each byte-identical to the npm package `pretendard@1.3.9`, whose tarball matches the registry's sha512 integrity. The release page publishes no checksum, so that cross-check stands in for one. The mover is the PM, by the same verification.
- Google sign-in is Google's own button, drawn to its Sign in with Google branding guidelines (developers.google.com/identity/branding-guidelines, read 2026-10-15) rather than to the tokens: `GoogleButtonStyle` in `app/lib/shared/theme.dart` holds its light and dark fill, stroke and label colours, its 14/20 medium label, its 20 px mark, and its spacing per platform ([ADR 0024](adr/0024-one-voice-and-a-sheet-action-rule.md)).
  - The "G" mark under `app/assets/google/` is cropped, unscaled and unrecoloured, from the icon-only "Square" Android and Web PNGs of the light and dark themes, at 1x to 4x, in Google's asset bundle `https://developers.google.com/static/identity/images/signin-assets.zip` (SHA-256 `ba884069e12093b06bcfd776915081254a7c95094b80d50be2c5dc6bac1c1da1`, downloaded 2026-10-15).
  - The bundle carries no licence file. Its use is governed by the branding guidelines, which require the standard-colour mark and forbid its modification, and by Google's Guidelines for Third Party Use of Google Brand Features, which the guidelines name for any use they do not cover; the guidelines page's own text is under CC BY 4.0.
- The user picks 시스템 (the default), 라이트 or 다크 in the account screen's "화면" section. The choice is stored on the device with `shared_preferences`, read before the first frame, and applied at once.

### Brand

- The marks are the owner's ([ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)): the symbol (the mascot, a rounded-stroke drawing), the horizontal lockup and the stacked lockup, each navy for a light ground and white for a dark one. `app/assets/brand/` holds them as PNGs at 1x to 3x, scaled from the owner's 4x files, and `AppBrand` in `app/lib/shared/theme.dart` names each theme's file; `web/public/brand/` holds the owner's SVGs.
- Where they appear: the horizontal lockup, 30 high, heading the home screen; the stacked lockup, 200 wide, on the sign-in screen; the symbol at 12% opacity in the today card's corner; and the mascot, through the component `Mascot`, in a 128 px white circle on the first-run home, an 84 px brand-tint circle on the study completion card, alone at 64 px above the first study session's guide, and alone at 28 px and half opacity at the foot of the account screen.
- Icons are Lucide's, a 2 px stroke with rounded caps and joins: `lucide_icons_flutter` in the app, with the theme's back and close buttons drawn from it, and `lucide-react` on the web.
- The launcher icons are generated from `app/assets/brand/icon/app-icon-light-1024.png` by `flutter_launcher_icons`, with `app-icon-dark-1024.png` as iOS 18's dark icon; the native splash, from `app/assets/brand/splash/`, by `flutter_native_splash`: the navy symbol on `#F4F6FA`, the white one on `#0E1424` in dark mode, Android 12's splash icon included. Both are pinned exactly in `app/pubspec.yaml`, which holds their configuration. To regenerate, run `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create` in `app/`, then revert the two edits they make beyond their output: `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` in `ios/Runner.xcodeproj/project.pbxproj` and the rewrite of `ios/Runner/Info.plist`.

### Tokens

`app/lib/shared/theme.dart` holds every token beside the colours ([ADR 0021](adr/0021-type-and-spacing-scales-and-a-shared-component-layer.md)). No other file under `app/lib/`, except the components in `app/lib/shared/ui/`, writes a spacing or font-size number.

- **Type**, `AppType`, all Pretendard, and the theme's `TextTheme` built from it ([ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)):

  | Role | Size / line / weight | Use |
  |---|---|---|
  | display | 28 / 36 / 800, −0.8 | Material's display styles; no screen draws it since the lockup heads the home screen |
  | title | 22 / 30 / 800, −0.4 | a pushed screen's title, the first-run heading, the completion card's heading |
  | deckTitle | 26 / 34 / 800, −0.6 | the deck name over its cards |
  | figure | 36 / 44 / 800, −0.8 | the today card's count |
  | headline | 18 / 26 / 700 | a sheet's title, a deck tile's letter |
  | body | 16 / 24 / 500 | running text, field text |
  | bodyStrong | 16 / 24 / 700 | a row's title |
  | label | 15 / 20 / 700 | a button, a card row's front |
  | secondary | 14 / 20 / 400 | a sheet's body, a line under a title, a card row's back, the study count at 700 |
  | caption | 13 / 18 / 400 | a row's second line, a note, an error |
  | section | 13 / 18 / 600 | a section label, a field's label, a stat pill |
  | micro | 12 / 16 / 400 | a chip |
  | question | 30 / 38 / 800, −0.6 | a study card's question |
  | answer | 20 / 28 / 600 | a study card's answer |

- **Spacing**, `AppSpace`: 4, 8, 12, 16, 20, 24, 28, 32, 40. The screen gutter is 20, the gap between rows 8, and the gap between sections 28.
- **Radii**, `AppRadius`: panel 40, sheet 28, card 24, previous card 20, row 18, button 16, field 14; a chip is fully rounded.
- **Heights**, `AppSize`: a call to action 56, a button 52, a field 52, a search field 48, a tap target at least 44; and the brand's sizes: the lockup 30 high, the stacked lockup 200 wide, the mascot's circles 128 and 84 and the guide's mascot 64, the avatars 56 and 32, a deck tile 44.
- **Shadows**, `AppShadow`: card, for a surface resting on the ground, and raised, a close layer under a wide soft one, for the current study card and the completion card.

### Components

`app/lib/shared/ui/` holds the shared, domain-free components every screen builds from ([ADR 0021](adr/0021-type-and-spacing-scales-and-a-shared-component-layer.md)). A screen uses them rather than building the same pattern from Material widgets.

- **`AppButton`** — every button in content and in bars. Variants: primary (the navy fill, inverted in the dark theme, the one primary action), onHero (a white fill with a navy label, on the today card), secondary (outlined), destructive (red text), destructiveFinal (red fill, the last step of a destructive action), and text (a quiet action, such as one in a top bar). An optional icon leads the label. Size cta (56) for the actions at the bottom of a screen or sheet, regular (52) elsewhere. States: pressed, disabled, and loading.
- **`AppTextField`** — every text field: a label above, a hint inside, an error below, and a counter where a limit exists, 52 high, or 48 for a search, with a 2 px ink ring while focused. The label, field and error are read as one.
- **`AppSheet`** with **`showAppSheet`** — every modal: a drag handle, a title, an optional body, content, and actions pinned at the bottom above the keyboard. Its actions follow one rule ([ADR 0024](adr/0024-one-voice-and-a-sheet-action-rule.md)):
  - every sheet is dismissed by a drag and by the scrim, so a sheet's actions hold no cancel;
  - a confirmation of an action that cannot be undone keeps an explicit cancel, and puts its destructive button last, at the bottom;
  - actions are always full width, with the primary one last.
- **`showAppConfirm`** — every irreversible action: a sheet that states the consequence in one sentence, with a cancel and, last, a red final button. It is the one sheet with a cancel.
- **`AppListRow`** — a row with a title, an optional second line and optional leading and trailing widgets, read as one node: the deck rows, the browse rows, the photo import deck chooser and the account screen's sign-out and deletion. A destructive row, the deletion, draws its title and leading icon in the red text colour ([ADR 0026](adr/0026-delete-the-account-through-an-edge-function.md)). **`AppRowSurface`** is its rounded surface alone, for rows with their own layout: the card rows, the photo review rows, the skeleton rows and the account screen's theme control. On a sheet a row takes the ground colour.
- **`AppSectionLabel`** — a label over a group of rows, read as a heading: "내 덱 n", "이미 있는 카드 n개", "화면", "계정", the import sheet's duplicate options, and the answer in the whole-card sheet.
- **`AppChip`** — a fully rounded label, or a button when it has an action: the brand-tint "오늘 n" chip, the "공개" chip, the camera's deck chip, and the duplicate option chip.
- **`Mascot`** — the brand's symbol in its theme's colour, alone or centred in a circle, hidden from screen readers.
- **`CardText`** — a card side's text, centred, scaled down from its style's size to a floor (question 30 to 18, answer 20 to 15, a previous card's front 18 and back 16 to 12) until its widest word fits the half, so lines break only between words; only a word wider than the half at the floor breaks inside itself. The current card, the previous cards and the card preview draw their text through it ([ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)).

Material widgets a screen still uses directly — `IconButton`, `PopupMenuButton`, `SegmentedButton`, `Checkbox`, `LinearProgressIndicator` — are themed in `app/lib/shared/theme.dart`.

### Checks

- Each screen and each sheet is checked against Flutter's `labeledTapTargetGuideline`, `androidTapTargetGuideline` and `textContrastGuideline` in both themes, in `app/test/widget_test.dart`, `app/test/account/account_screen_test.dart`, `app/test/account/sign_in_screen_test.dart`, `app/test/study/study_screen_test.dart`, `app/test/photo_import/photo_import_screen_test.dart`, the sharing screens' tests under `app/test/sharing/` and, for each component, `app/test/shared/ui/`.
- `app/test/shared/theme_test.dart` fails on a spacing or font-size literal outside the theme and the components, and on a dialog, or a sheet opened other than through `showAppSheet`.
- `app/test/shared/l10n/voice_test.dart` fails on a Korean string ending a sentence in 합쇼체 and on an English string with an exclamation mark, with controls that the check finds each ending and passes 해요체.
- The sheet rule is checked where each sheet is tested: the duplicate sheet in `app/test/deck/card_editor_screen_test.dart` and the report sheet in `app/test/sharing/public_deck_screen_test.dart` have no cancel; the card delete confirmation in the former, the account deletion confirmation in `app/test/account/account_screen_test.dart`, and `showAppConfirm` in `app/test/shared/ui/app_sheet_test.dart`, put cancel above delete.
- `app/test/launcher_assets_test.dart` fails when a launcher icon or a splash image is missing, is not the size its catalogue names, or does not draw its source scaled to that size, and when a splash ground is not its colour; a control tells the light icon from the dark one.
- `app/test/screenshots/screenshots_test.dart` draws every screen and sheet in both themes, in Korean at a phone's size, when run with `--update-goldens --dart-define=SCREENSHOTS=true`; it writes them to `app/build/screenshots/` and is skipped otherwise.

## Rationale

- [ADR 0007](adr/0007-study-swipe-screen-and-session-toggle.md) records the study screen these principles generalize.
- [ADR 0023](adr/0023-scroll-the-current-study-card-with-the-stack-and-centre-each-half.md) records why the current card scrolls with the stack and why each half of a split card centres its content.
- [ADR 0035](adr/0035-show-the-previous-and-current-study-card-reach-earlier-cards-three-at-a-time-re-decide-the-centred-card-and-grade-each-card-by-its-colour-and-a-chip.md) records the study screen's grades by colour and chip, its answer buttons and first-run guide, the change of an answer by a drag on the centred card, the completion card's streak colour, mascot and "그만하기", and the split card drawn once in `deck`.
- [ADR 0011](adr/0011-shared-app-theme-bundled-font-and-today-builder.md) records why the theme is one file with a token extension, why the font is bundled, and why the choice is stored in `shared_preferences`.
- [ADR 0021](adr/0021-type-and-spacing-scales-and-a-shared-component-layer.md) records why the scales sit in the theme file, why the components are a shared layer of their own, and why every modal is a sheet.
- [ADR 0024](adr/0024-one-voice-and-a-sheet-action-rule.md) records why the strings are 해요체, why a sheet has a cancel only when it confirms an irreversible action, and why Google sign-in is Google's button with the bundle's PNG mark.
- Issue #58 records the scales and the component set as the PM decided them on 2026-10-15, and issue #64 the voice, the sheet rule, the Google button and the sign-in and account screens.
- Issue #22 records the principles, the tokens and the screens as the owner approved them on 2026-10-15.
- [ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md) records the brand, Pretendard, the token values with the three adjusted for contrast, the icons and the generated launcher icons and splash; issue #72 records them as the PM decided them on 2026-10-15.

## Open questions

- Whether deleting a card should become undoable, so it needs no confirmation. Its study history is deleted with it today, which an undo would have to restore.
