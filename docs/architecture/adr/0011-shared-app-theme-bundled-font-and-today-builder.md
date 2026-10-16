# ADR 0011: Draw every screen from one shared light and dark theme with a bundled IBM Plex Sans KR, and show study's counts in deck screens through one builder provider

> Status: accepted; its "Sizes and timings may stay as constants beside the screen that uses them" superseded by ADR-0021 for spacing, type, radii, heights and shadows; its font and colour values superseded by ADR-0027; its "Counts", `deck`'s `TodayCount`, `todayProvider` and `studyScreenProvider`, superseded by ADR-0039
> Date: 2026-10-15

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #22 redesigns the deck screens to an owner-approved design. The PM decided there:
  - `app/lib/shared/theme.dart` defines the app's light `ThemeData` and a `ThemeExtension` holding the design tokens, and a dark pair with the greens and reds lightened to WCAG AA on the dark surface;
  - the font is IBM Plex Sans KR, bundled as an asset with its OFL licence, with no runtime download;
  - `main.dart` passes the themes to `MaterialApp`; `study_style.dart`'s colours move onto the extension, and no colour is written outside the theme file;
  - the user picks system (the default), light or dark on the account screen, stored on the device and applied at once;
  - the deck list shows a "today" chip per deck, and the card list a "today" line and a "Study · n" button, besides #19's header card.
- [ADR 0007](0007-study-swipe-screen-and-session-toggle.md) kept the study screen's colours as constants in `study_style.dart`. Every other screen took Material's default colours.
- The counts the deck screens show come from the queue rules and the stored card states, which only `study` reads. A failed read is a `StudyFailure`, which only `study` describes ([ADR 0009](0009-multi-deck-session-and-random-queue-order.md)).
- Alternatives considered for the counts:
  - A count function declared in `deck` and overridden at the composition site. ADR 0009 rejected it: `deck` would receive a `StudyFailure` it cannot describe to the user.
  - One `study` widget behind a `deck` provider per place a count appears (header, chip, detail line, study button), as ADR 0009 did for the header. ADR 0009 named providers that keep multiplying as a sign it was wrong; this would add three.
- Alternatives considered for the stored choice:
  - The drift database. One device-local value would need a table, a schema version and a migration, and the database opens after the first frame.
- Alternatives considered for the font:
  - `google_fonts`, which downloads at run time unless each file is bundled anyway. The issue rules out a runtime download.

## Decision

- **Theme.** `app/lib/shared/theme.dart` holds the app's colour tokens as `AppColors`, a `ThemeExtension` with a light and a dark set, the light and dark `ThemeData` built from them, and the corner radii. A widget reads tokens through `AppColors.of(context)` or the `ColorScheme` built from them; no other file writes a colour. Sizes and timings may stay as constants beside the screen that uses them.
- **Font.** IBM Plex Sans KR Regular, Medium, SemiBold and Bold are bundled under `app/assets/fonts/`, as published in google/fonts at commit `2aa273e00174c62d5de0a8c4365299e26d0ecff2`, with that directory's `OFL.txt`. Both themes set it as the font family.
- **Choice.** The user's choice is a `ThemeMode`, stored under one key in `shared_preferences` through `SharedPreferencesWithCache`, which the composition site opens before `runApp` so the first frame is drawn in it. An absent or unknown stored value is `ThemeMode.system`. A new choice applies at once and is then stored.
- **Counts.** `deck` declares `TodayCount` (pending, counted as due and new, or unavailable with its message) and `todayProvider`, which builds a widget that counts a `DeckSelection` and shows the count through a builder `deck` supplies. The composition site overrides it with `study`'s `TodayCounter`, which reads, re-reads and describes failures as ADR 0009's header did. `deck` lays out every place a count appears, and its buttons open the session through `studyScreenProvider`. This replaces ADR 0009's `todayCardProvider` and its header that started the session itself.

## Consequences

- Every screen renders in both themes from one set of tokens, and a colour change is one edit in one file.
- The app grows by about 11 MB of font files, and the repository by the same.
- The font is frozen at the google/fonts commit named above; no bot proposes its update.
- Each deck row and the card list read the counts separately, one database read per deck shown.
- A new place that shows a count needs no new provider: `deck` passes another builder to `todayProvider`.
- `deck` declares a type, `TodayCount`, whose only producer is `study`.

## Signs the decision was wrong

- A colour still differs between screens that should match, or a screen hardcodes one that the colour scan does not catch.
- Users with many decks see the deck list's chips arrive late, from one read per deck.
- The builder grows parameters for one caller's needs, and `TodayCount` gains variants only one screen uses.
- The stored choice is lost on a platform where `shared_preferences` cannot write, and users report the theme resetting.
- The bundled weights are not the ones the design uses, or the font's size drives users away on small devices.
