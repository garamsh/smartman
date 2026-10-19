# Design

The app's design language: the principles every screen follows for usability and visual design together, where each is applied today, and the theme, tokens and components that carry them.

## Current decisions

### Principles

Every screen is designed to be simple, intuitive and easy to use. A new screen or a change to one follows these, and copies the idiom named under each.

1. **One primary action per screen.** It is the most prominent element and sits in thumb reach, at the bottom. Secondary actions are quieter or live in a menu.
   - Study: the current card, low on the screen, with its two answer buttons under it; closing is a small icon at the top. On the completion card, "학습하기" is the one primary fill while new cards are left past today's, with "그만하기" a quiet text button below it.
   - Card editor: "저장하고 다음 카드" is the filled button in the bottom bar, "저장" outlined beside it; editing an existing card offers "저장" alone.
   - Card editor: a new card's kind is a segmented switch at the top, quieter than the bottom bar's actions; "뜻 추가" is outlined, and "표시 추가" a text button.
   - 오늘 tab: the navy card's white button, "모두 학습", the backlog card's "n장 학습", or on the done card "학습하기" as the one navy fill.
   - 덱 tab: "새 덱 만들기" under the rows, before "공개 덱 둘러보기", its ways in a sheet that also holds the photo's source; first-run home: "덱 만들기", which opens the same sheet; and nothing in the top bar but the title; deck screen: "학습하기" on the navy card and "카드 추가" in the bottom bar, or, while the deck holds no card, "카드 추가" alone as the primary ([ADR 0066](adr/0066-open-a-deck-made-by-hand-and-lead-an-empty-deck-and-a-cardless-today-tab-to-adding-cards.md)), `BottomActions`; rename and delete sit in the deck screen's menu.
   - Every sheet: `AppSheet` pins its actions at the bottom, full width, with the primary one last; "새 덱" and "이름 바꾸기" have one field and one primary, "만들기" or "저장".
   - Daily study minutes: the sheet's one primary is "저장", with the first-run step's quiet "건너뛰기" above it; the choices are large, 56 high, three to a row, the chosen one in the primary fill ([ADR 0086](adr/0086-show-and-change-the-daily-study-minutes-on-the-today-card-the-completion-card-a-one-time-first-run-step-the-account-screen-and-the-web-s-today-page.md)).
   - Sign-in: the stacked logo and its two lines sit on the ground's panel in the upper part, and Google's button, with the quieter Apple slot and the terms below it, at the bottom.
   - Every screen: `AppButton`'s variants rank the actions, one primary fill per screen or sheet.
2. **Content over chrome.** No label, hint or heading restates what the screen already shows. Remove before adding.
   - Study: no deck name and no hint text, but for the empty previous card's place's one line, "응답한 카드가 여기에 쌓여요", the 3 s notice that a resumed day goes on, and the first-use coach, which teaches on the cards themselves and is replayed only on request ([ADR 0064](adr/0064-teach-study-with-a-first-use-finger-coach-and-show-the-day-s-last-card-and-a-brief-notice-when-a-day-resumes.md)); the completion card carries no sentence beyond its heading and one line of counts, and "더 학습할 카드가 없어요" in place of "학습하기" where no new card is left; studying past today's cards is not marked apart ([ADR 0049](adr/0049-study-in-one-flow-that-goes-on-past-today-s-cards-as-recorded-study-with-the-current-card-showing-its-front-alone.md)).
   - Deck screen: each row shows the front, its back hidden until a tap or the "뜻 보기" switch; the deck name is the only title, and the row above the cards a quiet "카드 n".
   - Tabs: no line explains a long-press or a tab; 기록 has no explanatory paragraph, only each chart's heading, its figures and a line beside the heading.
   - Every sheet: `AppSheet` has a title and at most one or two sentences of body; `AppTextField` shows its label once, above the field.
   - Daily study minutes: the control says only "하루 n분" beside a pencil, and the sheet one sentence, with the preview's two lines saying what the choice means rather than how it is computed.
3. **Direct manipulation where it is natural.** Swipe to answer, tap to toggle. Every gesture has an accessible alternative: a semantics action or a visible control.
   - Study: a horizontal swipe answers, with the answer buttons and the custom actions "안다" and "모른다", and on the web a touch swipe answers the same, with the buttons and the arrow keys ([ADR 0084](adr/0084-answer-the-web-s-current-study-card-by-a-touch-swipe-as-the-phone-does.md)); a horizontal drag on the previous card changes its answer, with the custom action "안다로 바꾸기" or "모른다로 바꾸기", and a tap on it opens the whole card; a drag on either card moves that card alone.
   - Deck screen: a long-press opens a card, and a screen reader reaches the same through the row's "카드 편집" action.
   - Card editor: a word's senses move and are deleted by their own buttons, not a drag, and a label goes by the button on its chip; each button is named for a screen reader ([ADR 0083](adr/0083-write-every-card-kind-by-hand-in-a-form-of-its-own-chosen-by-a-kind-switch-each-deck-remembers.md)).
   - Photo import list: a swipe left leaves a row out, and its check, which a screen reader hears and taps, leaves it out or puts it back; a tap opens the row's edit sheet, and a screen reader taps the same.
   - Every sheet: a drag or a tap outside dismisses it, and Android's back does the same.
4. **Never wait.** Act at once and sync in the background. Show progress only for work the user asked for and must wait on, such as photo extraction.
   - Study: the next card is on screen before the answer's write finishes.
   - Photo import: extraction shows the photo, a progress bar and skeleton rows, and can be cancelled.
   - Account: a theme choice applies at once and is stored after.
   - Daily study minutes: "저장" stores them on the device, sync pushes them after, and the counts behind the sheet are read again as it closes; the preview moves with each choice before anything is stored.
   - Photo import: a swipe removes or puts back a card at once, and a topic's switch drops or keeps its cards at once; nothing is written until the cards are added.
   - Account and photo import: `AppButton`'s loading state shows progress in the button the user pressed, and the button cannot be pressed twice.
5. **Correct, don't confirm.** Prefer undo or a toggle to a confirmation sheet. Confirm only what cannot be undone: deleting a deck, a card with its study history, or the account.
   - Study: any answer of the session is corrected by a drag on the centred card, or its action, with no confirmation.
   - Card editor: a duplicate front opens a sheet that offers to add anyway or open the existing card, and is dismissed to do neither; nothing is overwritten.
   - Deck screen, card editor, account and preview: deleting a deck, deleting a card, signing out with unsynced changes, deleting the account, and blocking a user are confirmed through `showAppConfirm`, which states the consequence in one sentence above a cancel and, last, a red final button.
6. **One visual language.** Theme tokens only; the split card, front left and back right, each half's content centred across and down and shrunk toward a floor until its widest word fits, so a word never breaks inside itself while the floor fits, wherever a card shows both sides, and the study's current card, its front alone, centred and shrunk the same way ([ADR 0049](adr/0049-study-in-one-flow-that-goes-on-past-today-s-cards-as-recorded-study-with-the-current-card-showing-its-front-alone.md)); rounded surfaces on the ground colour; 44 pt minimum targets.
   - Study's previous card, card editor and duplicate sheet: the same split card, each half centred; `deck`'s `SplitCard` lays out the halves for the previous card, the card preview and the card rows ([`deck.md`](deck.md)).
   - A table or cloze card is drawn whole wherever a card is drawn split: its front across the card through `deck`'s `WholeCardView`, drawn from its blocks: a text block as its title, a cloze centred and fitted as a front is, a table in the body size inside `outline` lines with its header row on `ground` and its header row and each row's first cell bold; an empty blank is its answer in `hairline` on `hairline`, keeping its width, and a filled one the answer on `brandTint` ([ADR 0068](adr/0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md)).
   - A vocabulary sense reads the same from every book: each label in brackets, a part of speech by its fixed short form, as `[명]`, another label as printed, then the meaning, one sense per line. The label is its own span with a gap of one spacing step, `AppSpace.s4` (`mr-1` on the web), narrower than a word space, after it; a sense with no label shows its meaning alone ([ADR 0075](adr/0075-store-a-vocabulary-card-s-senses-as-a-typed-block-and-show-each-label-in-brackets-before-its-meaning.md)).
   - 덱 tab, 오늘 tab and deck screen: rows on rounded surfaces over the ground; the navy cards over them.
   - Every screen and sheet: the tokens below and the components that use them.
   - At a larger system text size nothing is cut (issue #295):
     - a box sized for its text grows with it: the tab bar from its 64 and the today card's goal ring, 76 across, by the text scale;
     - a pill's label wraps inside the pill;
     - a figure or label a narrow column holds, the day bars' among them, stays on one line and shrinks to the column only where it is wider, so a word never breaks inside itself.
7. **Meaningful motion** that shows where things go. Reduce motion is respected.
   - Study: an answered card flies off and rises into the previous card's place while the next emerges from below; under reduce motion they cross-fade. A re-decided card springs back into place, at once under reduce motion.
   - Photo import list: a row swiped left follows the finger and springs back into place, left out.
   - Study's coach: the card moves out with an ease, holds and springs back under a finger; under reduce motion each step is a still image, the card held out ([ADR 0064](adr/0064-teach-study-with-a-first-use-finger-coach-and-show-the-day-s-last-card-and-a-brief-notice-when-a-day-resumes.md)). The notice that a day goes on slides in and out, or fades.
   - Every sheet: `showAppSheet` slides it up with the platform's sheet motion, and shows it at once under reduce motion. Every `AppButton` shows pressed feedback, and a filled one gives a light haptic on iOS.
8. **Plain-language states.** Empty, offline and error states say what happened and what to do next, in one or two short sentences, in the voice below.
   - First-run home, a cardless 오늘 tab and deck screen: an empty list says how to start, and leads there with its one primary, and a search with no match, on the 덱 tab or the deck screen, says to try other words.
   - 오늘 tab and deck screen: in a backlog, one sentence says new cards wait until the reviews are caught up ([`study.md`](study.md)).
   - Study: with no card left and none answered today, one sentence says there is nothing to study today.
   - 기록: a chart with nothing to show says so in one sentence: no review in the period, no card reviewed, no card mastered.
   - Every screen: a storage failure says what failed and to try again.
   - Browse: offline, it says the public decks appear once connected; the deck menu says why publishing is disabled.

### Voice

Every string is written as one writer would write it ([ADR 0024](adr/0024-one-voice-and-a-sheet-action-rule.md)).

- Korean, in `app/lib/l10n/app_ko.arb`, is 해요체 throughout: plain, short, and consistent in its sentence endings ("아직 덱이 없어요.", "카드 3개를 찾았어요"). No sentence ends in 합쇼체 ("…ㅂ니다", "…ㅂ니까"). A label or a button names its action ("로그아웃", "그래도 추가").
- English, in `app_en.arb`, matches it in tone: plain, second person, no exclamation marks.
- **Terms** (#243, [ADR 0079](adr/0079-name-a-card-s-sides-front-and-back-and-its-grade-the-response-on-the-phone-the-web-and-in-the-docs.md)). A card's two sides are 앞면 and 뒷면, in English Front and Back, in every string, label and screen-reader text on the phone and the web, and in the docs; 문제 and 답 name no side. The grade a card is given, 안다 or 모른다, is 응답, in English Response, and answering it is 응답하다, to respond: "앞면: … 뒷면: … 응답: 안다". In code, `Answer` stays the grade, and a side is `front` or `back`, the type scale's `front` and `back` among them.

### Where it lives

- The theme, its tokens, the user's theme choice and the shared components are the app's foundation `app/lib/design/` ([`structure.md`](structure.md), [ADR 0039](adr/0039-name-every-top-level-folder-by-its-responsibility-compose-across-domains-in-a-home-shell-and-keep-seams-off-screens.md)): `design/theme.dart` the tokens and the themes, `design/theme_choice.dart` the choice, `design/word_break.dart` the `keepWords` that lets a line break only between words, which the empty previous card's place, the study coach's lines, the today card's status line and both sides of a photo import row use, each read by a screen reader as written, and one file per component beside them, with their tests under `app/test/design/`. It imports no domain and holds nothing one domain alone uses.
- `GoogleButtonStyle` is Google's, not the design system's, and only `account` draws it, so it is in `account/src/google_button.dart`; the colour check lists that file as its one exception beside the theme, and the size check as its one exception beside the theme and the components.
- `CardText` serves `deck` alone, which draws every card, so it is in `deck/src/card_text.dart` ([`deck.md`](deck.md)); the size check lists it beside Google's button, as it sets the fitted size of the `AppType` style it is given.
- On the web, the brand's marks, the skeleton, the theme choice with its store, "다시 시도" and the dialogs' focus trap are the foundation `web/src/design/` ([`web.md`](web.md)).

### Theme

- `app/lib/design/theme.dart` holds every colour token as `AppColors`, a light and a dark set, and the light and dark `ThemeData` built from them ([ADR 0011](adr/0011-shared-app-theme-bundled-font-and-today-builder.md)). No other file under `app/lib/`, but Google's button, writes a colour; `app/test/design/theme_test.dart` fails when one does.
- The colours are the brand's ([ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)):
  - Light: ground `#F4F6FA`, surface and raised `#FFFFFF`, ink (the brand navy) `#1F2A44`, ink-2 `#4A5470`, muted `#687187`, line `#E3E7EF`, outline `#D5DBE7`, brand tint `#E8ECF5`; "Know" `#1D8054`; "Don't know" `#C2402F` for text, the grade's chip and the destructive fill, `#E2574A` for the tint over a dragged card.
  - Dark: ground `#0E1424`, surface `#18203A`, raised `#232D4D`, ink `#EEF1F7`, ink-2 `#B5BED3`, muted `#9AA3BA`, line `#2A3352`, outline `#2E3858`, brand tint `#2A3560`; "Know" `#5ED39A`; "Don't know" `#FF8577`.
  - The grades of a previous card ([ADR 0035](adr/0035-show-the-previous-and-current-study-card-reach-earlier-cards-three-at-a-time-re-decide-the-centred-card-and-grade-each-card-by-its-colour-and-a-chip.md)): "Know" on `knowCard` inside `knowLine`, light `#EAF6EF` and `#9ED3B6`, dark `#17302A` and `#2E6B50`; "Don't know" on `dontKnowCard` inside `dontKnowLine`, light `#FCEEEC` and `#EBB3AA`, dark `#3A1F24` and `#7A3A36`. The answer buttons' words on the green and red tints are `onKnowTint`, light `#1D6B47`, dark `#5ED39A`, and `onDontKnowTint`, light `#B03A2B`, dark `#FF8577`. The completion card's flame is `streak`, light `#C26A0A`, dark `#F5A623`.
  - One primary colour: a primary action is the navy fill, inverted in the dark theme (`#EEF1F7` under `#1F2A44`). Green and red mean "안다" and "모른다" alone: answers, grades, the answer buttons and the completion card's counts.
  - The 기록 tab's charts derive their shades from the tokens, so no token is added for them ([`study.md`](study.md)): the retention line in ink over a brand-tint area, between hairline rules, against a target dashed in "Know" green, since the retention is the share answered 안다, named "목표 90%" in `onKnowTint` in a row of its own above the plot, so no line crosses it; the scale's top, 100%, and its floor, the lower of 80% and the period's lowest share rounded down to a tenth, are labelled in `muted` at the plot's left, so a dip to the floor never reads as 0% (issue #155); the recall bands strong in ink, fair in ink at 75% in the light theme and 40% in the dark, and fading in `streak` amber; this week's mastered bar in ink and the others ink at 55%; and the heatmap's four levels the hairline for a day without a card, then ink at 35%, 65% and 100%. A studied day's level is the third of 1 to the busiest day of the twelve weeks its cards fall in. Each band, and the quiet week, is 3:1 on the surface, and every two bands, and every two adjacent heatmap levels, differ in lightness by at least 1.5:1, so no pair rests on hue alone; `app/test/study/stats_view_test.dart` checks both in both themes. Each chart is read as one label that states its values. The web's `/record` page draws the same shades by the same rules, with `bg-ink/75 dark:bg-ink/40` for the fair band, and `web/src/features/study/__tests__/record-shades.test.ts` checks them ([`web-study.md`](web-study.md)).
  - The navy cards, the 오늘 tab's today and backlog cards and the deck screen's, are the navy (dark: raised) with white text; their quiet text and their tracks are `onHero` at 80% and 16%, a learning share of a progress bar is its ink at 45%, and the last seven days' other bars ink at 55%, so no token is added for them; `app/test/home/hero_test.dart` checks the quiet text at 4.5:1 and the flame, the goal ring and a quiet bar at 3:1 in both themes, and a progress bar's counts are always in text beside it ([ADR 0036](adr/0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md)); the deck tiles take one of four tints, light `#E8ECF5`, `#FFF1D6`, `#E3F4EC`, `#FCE8E6`, dark `#2A3560`, `#4A3B1E`, `#1E3F33`, `#4A2624`.
- Every text pair the screens draw meets WCAG AA (4.5:1), and each grade's chip 3:1 on its card and on the ground and the streak's flame 3:1 on the surface, in both themes; `app/test/design/theme_test.dart` checks the ratios, and `web/src/styles/__tests__/contrast.test.ts` the web's.
- The font is Pretendard 1.3.9, Regular to ExtraBold, bundled under `app/assets/fonts/` with its OFL licence, and read by the web app from there; nothing is downloaded at run time. The files are `public/static/*.otf` of `Pretendard-1.3.9.zip` from the v1.3.9 release of github.com/orioncactus/pretendard (SHA-256 `04be351a74d6bf7d60c480a3087e51d185485d35a52023142af1df19eb8c428a`), each byte-identical to the npm package `pretendard@1.3.9`, whose tarball matches the registry's sha512 integrity. The release page publishes no checksum, so that cross-check stands in for one. The mover is the PM, by the same verification.
- Google sign-in is Google's own button, drawn to its Sign in with Google branding guidelines (developers.google.com/identity/branding-guidelines, read 2026-10-15) rather than to the tokens: `GoogleButtonStyle` in `app/lib/account/src/google_button.dart` holds its light and dark fill, stroke and label colours, its 14/20 medium label, its 20 px mark, and its spacing per platform ([ADR 0024](adr/0024-one-voice-and-a-sheet-action-rule.md)).
  - The "G" mark under `app/assets/google/` is cropped, unscaled and unrecoloured, from the icon-only "Square" Android and Web PNGs of the light and dark themes, at 1x to 4x, in Google's asset bundle `https://developers.google.com/static/identity/images/signin-assets.zip` (SHA-256 `ba884069e12093b06bcfd776915081254a7c95094b80d50be2c5dc6bac1c1da1`, downloaded 2026-10-15).
  - The bundle carries no licence file. Its use is governed by the branding guidelines, which require the standard-colour mark and forbid its modification, and by Google's Guidelines for Third Party Use of Google Brand Features, which the guidelines name for any use they do not cover; the guidelines page's own text is under CC BY 4.0.
- The user picks 시스템 (the default), 라이트 or 다크 in the account screen's "화면" section. The choice is stored on the device with `shared_preferences`, read before the first frame, and applied at once.

### Brand

- The marks are the owner's ([ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)): the symbol (the mascot, a rounded-stroke drawing), the horizontal lockup and the stacked lockup, each navy for a light ground and white for a dark one. `app/assets/brand/` holds them as PNGs at 1x to 3x, scaled from the owner's 4x files, and `AppBrand` in `app/lib/design/theme.dart` names each theme's file; `web/public/brand/` holds the owner's SVGs.
- Where they appear: the horizontal lockup, 30 high, heading the 오늘 tab and the first-run home; the stacked lockup, 200 wide, on the sign-in screen; and the mascot, through the component `Mascot`, in a 128 px white circle on the first-run home, a 96 px white circle resting with three z's on the 오늘 tab's done card, a 64 px white circle with an amber check on its backlog card, an 84 px brand-tint circle on the study completion card, and alone at 28 px and half opacity at the foot of the account screen.
- Icons are Lucide's, a 2 px stroke with rounded caps and joins: `lucide_icons_flutter` in the app, with the theme's back and close buttons drawn from it, and `lucide-react` on the web.
- The launcher icons are generated from `app/assets/brand/icon/app-icon-light-1024.png` by `flutter_launcher_icons`, with `app-icon-dark-1024.png` as iOS 18's dark icon; the native splash, from `app/assets/brand/splash/`, by `flutter_native_splash`: the navy symbol on `#F4F6FA`, the white one on `#0E1424` in dark mode, Android 12's splash icon included. Both are pinned exactly in `app/pubspec.yaml`, which holds their configuration. To regenerate, run `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create` in `app/`, then revert the two edits they make beyond their output: `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` in `ios/Runner.xcodeproj/project.pbxproj` and the rewrite of `ios/Runner/Info.plist`.

### Tokens

`app/lib/design/theme.dart` holds every token beside the colours ([ADR 0021](adr/0021-type-and-spacing-scales-and-a-shared-component-layer.md)). No other file under `app/lib/`, except the components in `app/lib/design/`, Google's button and `CardText`, writes a spacing or font-size number; `CardText` scales the `AppType` style it is given.

- **Type**, `AppType`, all Pretendard, and the theme's `TextTheme` built from it ([ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)):

  | Role | Size / line / weight | Use |
  |---|---|---|
  | display | 28 / 36 / 800, −0.8 | Material's display styles; no screen draws it since the lockup heads the 오늘 tab |
  | title | 22 / 30 / 800, −0.4 | a pushed screen's title, the deck name on its screen, the first-run heading, the completion and done cards' headings |
  | deckTitle | 26 / 34 / 800, −0.6 | the 덱 and 기록 tabs' titles |
  | figure | 36 / 44 / 800, −0.8 | the navy cards' count |
  | headline | 18 / 26 / 700 | a sheet's title, a deck tile's letter |
  | body | 16 / 24 / 500 | running text, field text |
  | bodyStrong | 16 / 24 / 700 | a row's title |
  | label | 15 / 20 / 700 | a button, a card row's front |
  | secondary | 14 / 20 / 400 | a sheet's body, a line under a title, a card row's back, the study count at 700 |
  | caption | 13 / 18 / 400 | a row's second line, a note, an error |
  | section | 13 / 18 / 600 | a section label, a field's label, a stat pill |
  | micro | 12 / 16 / 400 | a chip |
  | front | 30 / 38 / 800, −0.6 | a study card's front |
  | back | 20 / 28 / 600 | a study card's back |

- **Spacing**, `AppSpace`: 4, 8, 12, 16, 20, 24, 28, 32, 40. The screen gutter is 20, the gap between rows 8, and the gap between sections 28.
- **Radii**, `AppRadius`: panel 40, sheet 28, card 24, previous card 20, row 18, button 16, field 14, menu 13; a chip is fully rounded.
- **Heights**, `AppSize`: a call to action 56, a button 52, a field 52, a search field 48, a tap target at least 44; and the brand's sizes: the lockup 30 high, the stacked lockup 200 wide, the mascot's circles 128 and 84 and the backlog card's mascot 64, the avatars 56 and 32, a deck tile 44; a round check's tick 14; a coach's finger 34 with a shadow blurred 6, and its step dots 6, the current one 16 long; and a pull-down menu's elevation 12.
- **Shadows**, `AppShadow`: card, for a surface resting on the ground, and raised, a close layer under a wide soft one, for the current study card and the completion card.

### Components

`app/lib/design/` holds the shared, domain-free components every screen builds from ([ADR 0021](adr/0021-type-and-spacing-scales-and-a-shared-component-layer.md)). A screen uses them rather than building the same pattern from Material widgets.

- **`AppButton`** — every button in content and in bars. Variants: primary (the navy fill, inverted in the dark theme, the one primary action), onHero (a white fill with a navy label, on the navy cards), secondary (outlined), destructive (red text), destructiveFinal (red fill, the last step of a destructive action), text (a quiet action, such as one in a top bar), and onHeroText (a quiet action on the navy hero surface, such as the study coach's "건너뛰기"). An optional icon leads the label. Size cta (56) for the actions at the bottom of a screen or sheet, regular (52) elsewhere. States: pressed, disabled, and loading.
- **`AppTextField`** — every text field: a label above, a hint inside, an error below, and a counter where a limit exists, 52 high, or 48 for a search, with a 2 px ink ring while focused. The label, field and error are read as one.
- **`AppSheet`** with **`showAppSheet`** — every modal: a drag handle, a title, an optional body, content, and actions pinned at the bottom above the keyboard. Its actions follow one rule ([ADR 0024](adr/0024-one-voice-and-a-sheet-action-rule.md)):
  - every sheet is dismissed by a drag and by the scrim, so a sheet's actions hold no cancel;
  - a confirmation of an action that cannot be undone keeps an explicit cancel, and puts its destructive button last, at the bottom;
  - actions are always full width, with the primary one last.
- **`showAppConfirm`** — every irreversible action: a sheet that states the consequence in one sentence, with a cancel and, last, a red final button. It is the one sheet with a cancel.
- **`AppListRow`** — a row with a title, an optional second line and optional leading and trailing widgets, read as one node: the option sheets' rows, the browse rows, the photo import source sheet and deck chooser, and the account screen's sign-out and deletion. A destructive row, the deletion, draws its title and leading icon in the red text colour ([ADR 0026](adr/0026-delete-the-account-through-an-edge-function.md)). **`AppRowSurface`** is its rounded surface alone, for rows with their own layout: the card rows, the skeleton rows and the account screen's theme control. On a sheet a row takes the ground colour.
- **`AppSectionLabel`** — a label over a group of rows, read as a heading: "화면", "계정", the import sheet's duplicate options, and the answer in the whole-card sheet.
- **`BottomActions`** — a screen's bottom bar: a secondary action, and a primary one beside it when the screen offers one: the deck screen and the card editor.
- **`AppChip`** — a fully rounded label in a tone, neutral (the surface inside an outline) or brand (the brand tint): the brand-tint "오늘 n" chip and the "공개" chip. `app/test/design/app_rows_test.dart` checks both tones.
- **`Mascot`** — the brand's symbol in its theme's colour, alone or centred in a circle, hidden from screen readers.
- **`CardText`**, in `deck` since it serves `deck` alone ([`deck.md`](deck.md)) — a card side's text, centred, scaled down from its style's size to a floor (front 30 to 18, back 20 to 15) until its widest word fits the half, so lines break only between words; only a word wider than the half at the floor breaks inside itself. The current card and the card preview draw their text through it ([ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)); the previous card's sides, run together as one paragraph, are scaled the same way and then further, as far as the floor, until they fit their half's height, and cut there ([ADR 0042](adr/0042-show-only-the-previous-and-the-current-study-card-at-one-size-re-decide-the-previous-card-by-a-swipe-and-open-it-on-a-tap.md)). A whole card's sentence is drawn through it as a span, at the size its filled text fits ([ADR 0068](adr/0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md)).

Material widgets a screen still uses directly — `IconButton`, `PopupMenuButton`, `MenuAnchor` (the photo import list's form menus), `SegmentedButton`, `Checkbox` (the publish sheet's `CheckboxListTile` and the photo import edit sheet's senses), `Switch`, `LinearProgressIndicator` — are themed in `app/lib/design/theme.dart`. The public-deck import sheet also uses `DropdownMenu`, for its deck, and `RadioListTile` in a `RadioGroup`, for its duplicate options; they have no theme of their own and take the theme's colour scheme. A `MenuAnchor` menu is drawn as an iOS pull-down menu ([ADR 0065](adr/0065-import-a-photo-s-cards-from-one-list-of-sections-each-with-its-form-menu-row-checks-and-an-edit-sheet.md)): on the raised surface with the `menu` radius and a soft shadow, its items body text at least a tap target high; the screen draws the leading checks and the heavier separator between groups. The switch, on the deck screen, is the ink track under an `onPrimary` thumb when on, and the surface track inside a muted outline under a muted thumb when off; `app/test/design/theme_test.dart` checks its outline on the ground and its thumb on its track at 3:1 in both themes.

### Checks

- Each screen and each sheet is checked against Flutter's `labeledTapTargetGuideline`, `androidTapTargetGuideline` and `textContrastGuideline` in both themes, in `app/test/widget_test.dart`, `app/test/account/account_screen_test.dart`, `app/test/account/sign_in_screen_test.dart`, `app/test/study/study_screen_test.dart`, `app/test/study/stats_view_test.dart`, `app/test/home/home_screen_test.dart` for the daily study minutes' control and sheet, `app/test/photo_import/photo_import_screen_test.dart`, the sharing screens' tests under `app/test/sharing/` and, for each component, `app/test/design/`.
- `app/test/design/theme_test.dart` fails on a colour outside the theme and Google's button, on a spacing or font-size literal outside the theme, the components, Google's button and `CardText`, and on a dialog, or a sheet opened other than through `showAppSheet`.
- `app/test/l10n/voice_test.dart` fails on a Korean string ending a sentence in 합쇼체 and on an English string with an exclamation mark, with controls that the check finds each ending and passes 해요체.
- The sheet rule is checked where each sheet is tested: the duplicate sheet in `app/test/deck/card_editor_screen_test.dart` and the report sheet in `app/test/sharing/public_deck_screen_test.dart` have no cancel; the card delete confirmation in the former, the account deletion confirmation in `app/test/account/account_screen_test.dart`, and `showAppConfirm` in `app/test/design/app_sheet_test.dart`, put cancel above delete.
- `app/test/launcher_assets_test.dart` fails when a launcher icon or a splash image is missing, is not the size its catalogue names, or does not draw its source scaled to that size, and when a splash ground is not its colour; a control tells the light icon from the dark one.
- `app/test/screenshots/screenshots_test.dart` draws every screen and sheet in both themes, in Korean at a phone's size, when run with `--update-goldens --dart-define=SCREENSHOTS=true`; it writes them to `app/build/screenshots/` and is skipped otherwise.

## Rationale

- [ADR 0007](adr/0007-study-swipe-screen-and-session-toggle.md) records the study screen these principles generalize.
- [ADR 0079](adr/0079-name-a-card-s-sides-front-and-back-and-its-grade-the-response-on-the-phone-the-web-and-in-the-docs.md) records why a card's sides are 앞면 and 뒷면 and its grade 응답, and what keeps its wording.
- [ADR 0023](adr/0023-scroll-the-current-study-card-with-the-stack-and-centre-each-half.md) records why the current card scrolls with the stack and why each half of a split card centres its content.
- [ADR 0042](adr/0042-show-only-the-previous-and-the-current-study-card-at-one-size-re-decide-the-previous-card-by-a-swipe-and-open-it-on-a-tap.md) records why the study screen shows two cards of one size, and why the previous card is re-decided by a swipe and opened on a tap.
- [ADR 0035](adr/0035-show-the-previous-and-current-study-card-reach-earlier-cards-three-at-a-time-re-decide-the-centred-card-and-grade-each-card-by-its-colour-and-a-chip.md) records the study screen's grades by colour and chip, its answer buttons and first-run guide, the change of an answer by a drag on the centred card, the completion card's streak colour, mascot and "그만하기", and the split card drawn once in `deck`.
- [ADR 0011](adr/0011-shared-app-theme-bundled-font-and-today-builder.md) records why the theme is one file with a token extension, why the font is bundled, and why the choice is stored in `shared_preferences`.
- [ADR 0021](adr/0021-type-and-spacing-scales-and-a-shared-component-layer.md) records why the scales sit in the theme file, why the components are a shared layer of their own, and why every modal is a sheet.
- [ADR 0024](adr/0024-one-voice-and-a-sheet-action-rule.md) records why the strings are 해요체, why a sheet has a cancel only when it confirms an irreversible action, and why Google sign-in is Google's button with the bundle's PNG mark.
- [ADR 0044](adr/0044-show-a-guide-with-the-session-s-size-in-the-previous-card-s-place-at-every-session-s-start.md) records why a guide holds the previous card's place at every session's start, widening the no-hint rule.
- [ADR 0064](adr/0064-teach-study-with-a-first-use-finger-coach-and-show-the-day-s-last-card-and-a-brief-notice-when-a-day-resumes.md) records why that guide gave way to a first-use coach on the cards, one line in the empty place, and on a resumed day the day's last card and a brief notice.
- Issue #58 records the scales and the component set as the PM decided them on 2026-10-15, and issue #64 the voice, the sheet rule, the Google button and the sign-in and account screens.
- Issue #22 records the principles, the tokens and the screens as the owner approved them on 2026-10-15.
- [ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md) records the brand, Pretendard, the token values with the three adjusted for contrast, the icons and the generated launcher icons and splash; issue #72 records them as the PM decided them on 2026-10-15.

## Open questions

- Whether deleting a card should become undoable, so it needs no confirmation. Its study history is deleted with it today, which an undo would have to restore.
