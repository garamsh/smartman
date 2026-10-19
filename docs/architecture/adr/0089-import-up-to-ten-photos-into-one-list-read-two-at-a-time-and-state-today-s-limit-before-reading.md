# ADR 0089: Import up to ten photos into one list, read two at a time, and state today's limit before reading

> Status: accepted
> Date: 2026-10-20

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- A photo import took one photo: a camera shot or one pick from the album, one `extract-cards` call, and one list ([ADR 0054](0054-take-the-photo-with-the-system-camera-or-from-the-library-and-remove-the-in-app-camera-view.md), [ADR 0065](0065-import-a-photo-s-cards-from-one-list-of-sections-each-with-its-form-menu-row-checks-and-an-edit-sheet.md)). A chapter of several pages took as many imports, each saved on its own.
- The owner asked for several photos in one import; the PM decided the design in issue #272: up to 10 photos from the album in pick order, the camera still one shot, "사진 더 추가" for more pages in the same import, each photo its own call with at most 2 at a time, one progress screen with each photo's state, a failure that loses no other photo, one list grouped by photo then by topic, one save, and a cancel that starts no further call.
- The function counts each photo against the plan's daily limit through `public.begin_extraction`, which only `service_role` may call ([ADR 0071](0071-give-each-user-a-plan-whose-model-and-daily-limit-an-admin-sets-in-the-database-and-make-one-model-call-per-photo.md), [ADR 0073](0073-keep-the-extraction-prompt-as-append-only-versions-in-the-database-served-by-an-active-and-an-admin-only-test-label-and-record-what-served-each-call.md)). The app could not tell before reading how many photos today's limit leaves. The issue asked for that number up front, and the coordinator chose an additive read-only function for it, needing only the PM's confirmation, under three constraints: it returns only the caller's own limit and count, it shares `begin_extraction`'s plan resolution and day, and pgTAP covers each plan, an ended Special and `anon`.

## Decision

- **Picking.** The album picks up to 10 photos in one system picker, through `image_picker`'s `pickMultiImage` with its `limit`, in pick order. The camera takes one. `PhotoSource.pickFromLibrary` returns each picked photo as its own future, prepared when its turn comes, so one undecodable file fails its photo alone.
- **One photo is as before.** A single photo, however picked, goes straight to Extracting and keeps its failure screens and its retake. The several-photo path starts only with two or more photos, or with photos added to a list.
- **Today's limit, before reading.** A new `public.extraction_allowance()`, `security definer`, executable by `authenticated` alone, returns the caller's plan's `daily_limit` and the photos counted today, read from `auth.uid()` with no user argument. It resolves the plan through `private.plan_of`, as `begin_extraction` does, and counts the same rows of `extraction_usage` from the same UTC midnight, so the two agree, which a pgTAP test checks on each plan. With fewer left than picked, the app reads only the first ones left and says "오늘 n장 더 만들 수 있어요. 처음 n장만 읽어요." over the progress; with none left, it shows the daily-limit failure, or a snack bar over the list. Where the allowance cannot be read, as offline, every photo is sent and a refusal shows on its photo, with no note up front.
- **Reading.** A `PhotoBatch` reads the photos in order with at most 2 calls open, starting the next as one ends. A photo that fails stays failed, saying why, with "다시 시도" where retrying can help and "빼기"; the others go on. The list opens once every photo is read or left out; with every photo left out, the screen closes, or returns to the list.
- **Progress.** One screen: the heading "사진 k/n 읽는 중", a heading and a live region, with k the photo now read; a bar of the photos read; one row per photo with its thumbnail, "사진 i" and its state in words and an icon: 기다리는 중, 읽는 중, 카드 n장, or the failure; the privacy note; and "취소" at the bottom. Once only failures remain, the heading says "사진 n장을 읽지 못했어요".
- **Cancel.** "취소" aborts the calls open, starts no other and closes the screen, or returns to the list when photos were being added to one. Photos already counted stay counted, as a cancelled single photo does.
- **The list.** With one photo, the list is as before. With several, it groups by photo, then by topic and kind as before: each photo a collapsible group headed by its thumbnail, "사진 i" and its row count, a heading and a button whose state is expanded or collapsed. A section's form stays keyed by deck, kind and topic, so a form chosen in one photo's section is the default for the same topic in a later photo. A card key appearing in two photos is two rows, and saving merges them as cards of one key always merge.
- **Adding photos.** "사진 더 추가", under the sections, opens a sheet with "사진 찍기" and "앨범에서 고르기" and reads the photos taken into the same list, up to 10 photos in all, keeping every earlier row's checks, edits and forms. The retake shows only while the list holds one photo, since with several it would not say which photo it replaces.
- **Saving.** "카드 n장 추가" saves every photo's included rows in one `DeckRepository.addCards` call, as one photo's rows were.
- No Edge Function or prompt changes.
- **Alternatives considered:**
  - **Saying nothing before reading and showing each refusal on its photo.** It needs no server change, but the user learns of the limit only after waiting on photos that were never going to be read. It remains the fallback when the allowance cannot be read.
  - **Reading the count in the app from `extraction_usage`.** The app may select its own rows, but the limit lives in the private plans, and resolving the plan in the app would copy `begin_extraction`'s rules where they could drift.
  - **All photos at once, or one at a time.** All at once multiplies the open uploads and the model's concurrent calls per user; one at a time doubles the wait. The issue fixes 2.
  - **One flat list of every photo's sections.** It loses which page a card came from, which the user needs to check a card against its page.

## Consequences

- A chapter is one import and one save. The calls cost what as many single imports cost, and today's limit counts each photo.
- With 2 calls at a time, a page of 10 photos takes about five calls' time; more at once would hit the function's per-user lock and the model's rate limits harder for little gain on a phone's upload.
- The app reads the allowance once per batch. It can still be overtaken by another device importing at the same moment; the function's count stays the limit, and the refusal then shows on the photo.
- The migration adds one function and changes nothing that existed; it deploys on merge with the PM's confirmation.
- The progress screen and the photo groups are new layouts; the single-photo path is unchanged, so its tests stand as they were.

## Signs the decision was wrong

- Users regularly pick more than 10 photos and import twice, or pick 2 or 3 and find the grouping heavier than the single list.
- The allowance and the function disagree, and a photo the note promised is refused.
- Reading 2 at a time is often slower than the progress suggests, or the function's lock or the model's rate limit refuses the second call.
