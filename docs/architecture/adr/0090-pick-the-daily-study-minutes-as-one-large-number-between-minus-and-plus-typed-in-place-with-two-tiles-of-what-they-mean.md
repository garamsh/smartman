# ADR 0090: Pick the daily study minutes as one large number between − and +, typed in place, with two tiles of what they mean

> Status: accepted
> Date: 2026-10-20

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #303**, the owner's decision of 2026-10-20 after comparing four designs. The sheet of [ADR 0086](0086-show-and-change-the-daily-study-minutes-on-the-today-card-the-completion-card-a-one-time-first-run-step-the-account-screen-and-the-web-s-today-page.md) held six preset buttons, "직접 정하기" revealing − and + in steps of 5, a preview box of two sentences, and "저장". The owner found it cluttered and not intuitive.
- **The chosen design** is the artboard "C. 큰 숫자 + − 버튼": the minutes as one large number between − and +, the number typed when tapped, and two tiles under it. The issue drops the artboard's quick chips.
- **ADR 0086 rejected a typed value** because the keyboard would cover the preview and a field needs its own validation message. The issue answers both: the sheet scrolls so the tiles stay above the keyboard, and one line under the number says what is accepted.
- **No server change.** `save_study_settings` and `saveDailyMinutes` already accept any whole number from 5 to 180 ([ADR 0085](0085-fill-each-day-s-new-cards-from-the-daily-study-minutes-the-user-sets-stored-per-user-on-the-server-and-synced.md)).
- **Alternatives considered:**
  - **Keep the presets beside the number**, as the artboard's quick chips. The issue drops them: they are the clutter the owner named, and − and + reach every preset in a few presses.
  - **A date for when the new cards are all started**, as ADR 0085's preview named it. A tile has the width of half the sheet, and "n일 뒤" fits it in every language where "M월 D일쯤" with its sentence did not. A count of days also needs no time zone, so both clients compute it from the counts alone.
  - **Commit a typed number on every keystroke.** "1" on the way to "15" would fall outside the bounds and flash the error. The number is committed on Done, Enter or leaving the field, while the tiles follow each keystroke that lands within the bounds.

## Decision

- **The picker**, in the app's sheet and first-run step and in the web's dialog, under the title and its sentence:
  - **the number:** the minutes in the figure style with "분" beside it, between a − and a + button that move them by `dailyMinuteStep`, 5, within 5 to 180. Each step disables at its bound.
  - **the tiles**, on the brand tint, side by side:
    - "하루 새 카드" with "약 n장": today's new cards left at the minutes shown;
    - "새 카드 모두 시작" with when the remaining new cards are all started: "오늘", or "n일 뒤", or "새 카드를 모두 시작했어요" with none left, or "이 시간은 복습으로 차서 새 카드는 시작하지 않아요" when the reviews fill the minutes.
    - In a backlog they give way to the sentence "밀린 복습을 마칠 때까지 새 카드는 쉬어요."
  - **"저장"**, and on the first-run step "건너뛰기", as ADR 0086 placed them.
- **No preset buttons and no "직접 정하기".** `dailyMinutePresets` is removed on both clients.
- **Typing in place.** Tapping the number turns it into a field holding it, selected:
  - the app opens the number keypad; the web turns the number into a text input with `inputmode="numeric"`;
  - it takes digits only, at most three;
  - any whole number from 5 to 180 is accepted. Outside them, a line under the number says "5분에서 180분 사이로 적어 주세요", the field stays open, and "저장" is disabled until it is fixed;
  - Done or Enter, or leaving the field, commits it; an empty field keeps the minutes before;
  - the tiles follow the number as it is typed, while it is within the bounds;
  - the sheet scrolls, so the tiles stay visible above the keyboard.
- **When the new cards are all started** is a count of days after today, `daysToStartAll`: none when today takes them all, otherwise the rest over the day's figure rounded up, and never when that figure is zero.
- **Screen readers:**
  - the number is a button read as "하루 n분, 눌러서 직접 입력", and the field as "하루 공부 시간(분)";
  - − and + are read as "5분 줄이기" and "5분 늘리기";
  - the tiles are a polite live region, heard again when they change.
- **Focus.** On the web the dialog opens with the focus on the number and keeps Tab inside it (`keepFocusInside`). Enter that commits gives the focus back to the number. On both clients, a step that disables at its bound while focused hands the focus to the other step.
- **Unchanged from ADR 0086:** the control and where it shows, the first-run step's conditions, the completion card's line, the account row, the save and its failure, and the counts read again when the sheet closes.

## Consequences

- The sheet is shorter: one row and two tiles in place of two rows of presets, a toggle and a preview box.
- A user can set any whole number of minutes, not only a multiple of 5.
- The preview no longer names today's reviews, which the today card already states.
- This supersedes ADR 0086's six choices, its custom value in steps of 5 with no typed value, and its preview's sentences, and ADR 0085's day the last new card starts, now a count of days.

## Signs the decision was wrong

- Users miss that the number can be typed, and press + many times to reach a large value.
- The out-of-range line shows often, because users type a number of hours or seconds.
- Users ask for the presets back.
