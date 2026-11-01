# ADR 0142: Read a spreadsheet's number formats in Dart and save its cards in one transaction on the phone

> Status: accepted
> Date: 2026-11-02

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #495** builds [ADR 0125](0125-add-cards-from-an-xlsx-or-csv-file-by-choosing-columns-and-reviewing-before-save.md)'s spreadsheet import on the phone. ADR 0125 states behaviour for both platforms, and three of its decisions rest on what the web has and the phone does not.
- **SSF is JavaScript.** ADR 0125 §Cells draws a number "by SSF 0.11.2". pub.dev's two spreadsheet readers do not replace it, and cannot be installed here: `excel` 4.0.6, last published 2024-08-20, and `spreadsheet_decoder` 2.3.0, last published 2024-09-09, require `archive` ^3.6.1 and an `xml` below 7, and `app/pubspec.lock` holds `archive` 4.5.2 and `xml` 7.0.1 through `image`.
- **The phone makes no requests.** ADR 0125 §Duplicates and §Writes save in requests of at most 100 cards, each with a stable id, because a request can fail after it wrote. A write on the phone is a local transaction, which commits or leaves nothing.
- **A file picker is not a file input.** The platform's picker greys out what the filter excludes.
- **The rule ADR 0125's body is under.** `docs/architecture/README.md` §Rules, "ADRs are append-only", keeps a changed decision out of the frozen body, so the issue's dated note in ADR 0125 is this ADR.
- **Alternatives considered:**
  - **Run SSF in a JavaScript engine on the phone.** A runtime in the app for one package, which draws a number in a word list.
  - **Port SSF line by line.** About 900 lines of regular-expression dispatch that exist for its quirks, such as cutting `000-0000` to its width, which Excel does not do.
  - **Draw every number as General.** A date would read as 46324.
  - **Keep the 100-card batches.** A batch boundary would save a part of the file and stop on a duplicate in the next, marking "저장됨" with no failure that needs it.

## Decision

These hold on the phone. ADR 0125 holds in everything it does not change here, and on the web in full.

- **Number formats.** `shownNumber` in `app/lib/deck/src/spreadsheet_format.dart` reads a format as SSF 0.11.2 reads one: its sections and conditions, its tokens, its date parts and elapsed times, and General. Where SSF refuses a format, it draws General, as the web does. `app/test/deck/spreadsheet_test.dart` holds fifty cases whose expected text ssf 0.11.2 printed.
  - It differs from SSF on purpose where SSF differs from Excel: a negative number exactly halfway rounds away from zero, `000-0000` keeps a digit past its width, and a negative number keeps its sign through `0.0` where the rounded text is zero.
  - It draws General for a number of 1e21 or more and for `B1` and `B2`, SSF's calendars.
  - Against ssf 0.11.2 over 12,127 pairs of 135 formats and 67 values, it differs on 440: 84 at 1e21, and 356 at those cases above and on formats a sheet rarely holds, such as `0,0`, `? ?`, `0.0?` and `0-0`.
- **One transaction.** The chosen cards are checked and saved whole: the first row repeating a stored card or an earlier row stops the save before any write, with ADR 0125's sentences and its "n행 빼기" and "그래도 추가". So no card is saved part-way, nothing is marked "저장됨", the mapping is never locked by a save, and a retried save has nothing to deduplicate, so a card takes a new id rather than one stable for its row.
- **The picker.** The picker offers `.xlsx` and `.csv`. The refusal of another extension stays, for a provider that passes one through.
- **Reading.** A file is read on an isolate, every visible sheet at once, each row parsed apart, so a sheet past 1,000 rows is refused on reaching row 1,001 and a sheet that unpacks to 50 MB is never one document in memory. A column past Excel's 16,384 refuses the sheet as unreadable.
- **The shared step's words.** The save button reads as photo import's, "카드 n장 추가", in place of "n장 추가", and a new deck is named on saving and offered 덱 꾸미기, as photo import does. A file opened from a deck saves into that deck, with no choice shown.

## Consequences

- No JavaScript runtime and no new transitive package: `archive` and `xml`, already in `app/pubspec.lock` through `image`, become direct.
- A custom format met only on the phone may draw differently from the web where SSF's reading has a quirk this reader does not copy.
- The web keeps its batches and its "저장됨"; the two clients differ in a state the phone never reaches.

## Signs the decision was wrong

- A reported cell that the web draws and the phone draws differently, for a format users commonly write.
- A file large enough that one transaction holds the database noticeably long.
