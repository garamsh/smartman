# ADR 0113: Copy a public deck's photos and sounds into the copier's own media, under new ids, when the deck is copied

> Status: accepted
> Date: 2026-10-27

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #428** records the PM's decision of 2026-10-27, made under the owner's overnight mandate: copy the files when the deck is copied.
- **The defect it fixes.** The worker on #427 found that the app downloads media only from the signed-in user's own folder, `{auth.uid}/{media id}`. A card copied from another user's public deck names the owner's media id ([ADR 0109](0109-store-an-image-block-s-boxes-in-fractions-of-the-image-and-draw-them-with-the-image-s-one-transform.md), [ADR 0112](0112-store-an-audio-block-by-media-id-and-length-up-to-60-seconds-and-play-the-front-s-sound-once-as-a-study-card-appears.md)). So the copier's device asks for a path that does not exist, and the photo or sound never shows.
- **What the server already allows.** `public.media_in_public_card` lets any signed-in user read a photo or a sound that a live card in a public deck, neither hidden nor deleted, names. No migration and no policy change is needed.
- **The owner's `media` row is not readable** by anyone else ([ADR 0107](0107-store-media-in-a-private-supabase-storage-bucket-named-by-media-id-and-give-each-deck-an-image.md)), and a Storage download returns bytes alone. A copy therefore cannot learn a file's type from the server.
- **`DeckRepository.addCards`** writes a copy in one drift transaction. That transaction holds the database while it runs, so no network request is made inside it.
- Alternatives considered:
  - **Keep the owner's id in each block and read across folders.** This is rejected on #428. The copy would break once the owner deletes the card or unpublishes the deck, and reading the copy would depend on another user's data.
  - **Store the owner's original id beside the new one, so a re-copy finds its duplicates.** The PM rejected this field in the dispatch of #428: it is the rejected alternative above in another form.
  - **Fetch the files in `SharingService` and pass new ids to `addCards`.** `SharingService` holds no `MediaStore`, so `main.dart` would change and `sharing` would come to depend on `media`. A copied file that a skipped card held would also have to be released again.
  - **Download inside the transaction.** A slow network would hold every other database write.
  - **Hold the fetched bytes in memory until the transaction commits.** At 5 MiB a sound, a deck of 200 sound cards would hold about 1 GiB, and a phone kills the app for that (PM review of #431).

## Decision

- **A copy owns its media.** Copying a public deck reads each photo and sound its cards hold from the owner's folder and stores it under a new media id in the copier's own media. Each copied block names the new id. Every later read stays in the copier's folder.
- **Where it happens.** `DeckRepository.addCards`, given `FromCopy` with the owner's id, does it in two steps:
  - before its transaction, it reads every file the incoming cards name through `MediaStore.fetchShared`. Each file is written to the device under its new id as it arrives, and only its id and its row's metadata are kept, so only the files in flight are held in memory;
  - inside the transaction, `MediaStore.addFetched` queues each file in `media_uploads` as the card holding it is written, so it uploads with the rest of the queue;
  - after the transaction, `MediaStore.discardFetched` deletes from the device each fetched file that no written card holds. If the transaction fails, it deletes them all.
  - `SharingService` passes the owner. `sharing` gains no dependency.
- **Once per file.** A file of the owner's that several cards in one copy hold is stored once, and they all name its one new id. A back's files are stored only when its card is added: a card skipped or merged as a duplicate stores none.
- **The type from the bytes.** A fetched file's kind and MIME type are read from its first bytes, the only types the bucket accepts:
  - JPEG is `image/jpeg`;
  - an MPEG-4 `ftyp` box is `audio/mp4`, and so is an ADTS AAC header (a frame sync with layer bits `00`), which is how a picked `.aac` is stored;
  - an ID3 tag, or a frame sync whose layer is not `00`, is `audio/mpeg`.
  - Other bytes count as a file that could not be read.
- **A file that cannot be read.** It cannot be read when:
  - the server holds none the copier may read, for example because the owner removed it;
  - its bytes are of no accepted type;
  - the network fails on 3 tries.

  Its block then names a new id that no file holds, so the view shows its no-media state. The copy still succeeds. Up to 4 files are read at once. `SupabaseMediaServer.download` takes the owner whose folder it reads, and reads the signed-in user's own folder without one.
- **Copies are independent.** Each copy, a re-copy of the same deck included, makes new ids. Deleting one copy releases only its own files.
- This **refines** ADR 0109's and ADR 0112's copy, which kept the owner's media id. A card copied from one's own public deck gets new ids too. A card copied within a deck still keeps its id. The server's read policy is unchanged; only the copy uses it now.

## Consequences

- A copied photo or sound shows on the copier's device at once. It still shows after the owner deletes the card, hides or unpublishes the deck, or deletes the account.
- The copier's storage holds a copy of each file, counted against the copier's own folder.
- A copy needs the network for the files as it already does for the cards. A file read at the copy is stored and uploaded offline-first, like a photo the user takes.
- A file missing at the time of the copy stays missing in that copy. Nothing fetches it again later.
- A photo's or a sound's card key is its media id. So a re-copy into a deck that already holds the same cards never finds a photo or sound card a duplicate, and it adds the card again whatever the duplicate choice says.
- A side whose blocks include one this build cannot read keeps that block as it is, unchanged. Any media id inside such a block is not copied.
- A copy writes its files to the device before it knows which cards it adds, and deletes the unused ones after. If the app is killed between the two, the unused files stay on the device with no queue row until the app's data is cleared, as a deleted deck's downloaded file does.

## Signs the decision was wrong

- Users who copy the same deck into one of their decks again report doubled photo or sound cards. That would ask for a duplicate check that does not rest on the media id.
- Copies of large decks are slow or fail for their media. That would ask for the files to be fetched in the background after the copy, through a queue of their own.
- Copiers' storage grows mostly with copied files. That would ask for files deduplicated by digest across users.
