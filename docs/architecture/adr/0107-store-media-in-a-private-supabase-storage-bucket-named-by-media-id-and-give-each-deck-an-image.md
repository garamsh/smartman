# ADR 0107: Store media in a private Supabase Storage bucket, named by media id, and give each deck an image

> Status: accepted
> Date: 2026-10-26

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #383** records the owner's request of 2026-10-26 for deck images, and their plan for image-based cards (blanks over an image) and audio after. The storage chosen now serves those too.
- **The PM's decision on #383**, delegated by the owner: Supabase Storage, in a private bucket, with media referenced by id, never by URL.
  - Storage is already part of the project: one sign-in, row-level security on `storage.objects` keyed to `auth.uid()`, and the same client SDK in the app and the web, with no second set of credentials or billing.
  - It takes resumable uploads, which audio will need, and signs URLs for private reads.
  - Its objects are S3-compatible.
- **[ADR 0103](0103-give-each-deck-an-icon-and-a-colour-stored-as-two-unchecked-keys-and-drawn-on-its-tile-in-place-of-the-initial.md)** gave each deck an icon and a colour, chosen in the 덱 꾸미기 sheet. A deck's image is chosen there too.
- **[ADR 0106](0106-store-each-card-s-template-and-each-block-s-version-and-id-derive-one-face-or-front-back-from-blanks-and-keep-unknown-shapes-unchanged.md)** says a later image or audio block holds a media id from this issue.
- **Storage refuses a delete of `storage.objects` in SQL** (its `protect_delete` trigger, met on the local stack of Supabase CLI 2.122.0), since the bytes would stay behind. A delete goes through the Storage API.
- Alternatives considered:
  - **S3 directly.** It needs AWS credentials, a signing function and a mapping from users to keys of its own, for no gain at this scale.
  - **Store a URL in the deck.** A URL ties every row to one host and one signing scheme; moving the bytes would rewrite every row that holds one.
  - **A public bucket.** Every image would be readable by anyone holding its address, including those of private decks.
  - **An interactive cropper.** `image_cropper` needs a native activity declared in the Android manifest. A centred square, cropped automatically, fits the square tile; an interactive crop is left for later.
  - **A foreign key from `decks.image_media_id` to `media`.** A device pushes the deck before its upload lands, so the key would refuse the deck, and sync with it, while the device is offline.

## Decision

- **Referenced by id.** A stored file is named by a media id, a UUID the device makes. A deck, and later a card block, holds that id, never a URL. Moving the bytes to S3 or R2 is a copy plus a change to how an id resolves; no row is rewritten.
- **The `media` table** holds one row per file: `id`, `user_id`, `kind` (`image`, with `audio` reserved), `mime_type`, `byte_size`, `sha256` and `created_at`. Its key is `(user_id, id)`: an id is unique only within its owner's rows, so no user can take an id another user's device made, which a public deck's `image_media_id` shows to anyone. Its owner inserts, reads and deletes its rows; no one updates one, and no one else reads one. It goes with its user by cascade.
- **The private bucket `media`** holds each file at `{owner}/{media id}`.
  - Its owner uploads a file only after inserting the row that names it, at exactly that path, and reads and deletes its own files. No one overwrites a file.
  - Any signed-in user reads the image of a deck the decks policy shows them as public: not hidden, not deleted, and the object's owner's own deck. No one else reads a file.
  - A suspended user inserts no `media` row and uploads no file, through restrictive insert policies like those on `decks` and `cards`.
  - The migration creates the bucket in every project, and sets a `media` bucket already there to the same privacy and limits; `supabase/config.toml` declares the same for the local stack.
- **Size limits.** A stored image is a JPEG, cropped to its centred square and scaled to at most 1024 px a side, at quality 85. The bucket accepts `image/jpeg` alone and at most 10 MiB a file, which `media.byte_size` checks too. The limit is a ceiling, not the target: the prepared image is far smaller, and the client's resize, not the limit, sets its size (the owner's decision on #383, 2026-10-26). Audio widens the MIME types in its own migration.
- **A deck's image.** `decks.image_media_id`, nullable with no foreign key, synced with the deck. A deck with one draws it on its tile; one without, or whose file cannot be read, draws its icon.
- **The device.** A new domain, `media` (`app/lib/media/`), keeps files in the app's support directory under their ids.
  - A chosen image is cropped and stored on the device first, so it shows at once, and queued for upload. A file another device stored is downloaded on first read and kept.
  - The device's `media_uploads` and `media_deletions` tables queue the files to upload and those the user let go. Sync drains both after each run of its rows, and a transfer that fails stays queued and retries with sync's backoff.
  - A deck that takes a new image, loses its image, or is deleted releases the old one, in the same transaction as the deck's write. A released file is deleted from the server, then the device.
- **Account deletion.** `delete-account` deletes every object in the user's folder through the Storage API, then the user, whose rows cascade.
- **Sharing.** A copy of a public deck carries its cards' text, not the deck's image.

## Consequences

- An image shows on its device before it reaches the server, and on another device once both have synced; until then that device draws the icon.
- A deck deleted on another device leaves its downloaded file on this one until the app's data is cleared.
- A file released but still queued for deletion when the user signs out, which clears the queues with the rest of the device's data, stays on the server until the account is deleted.
- The web draws only icons until its own follow-up issue reads the bucket.
- An owner can replace its own file's bytes by deleting it and uploading again under the same name, and nothing compares `sha256` or `byte_size` with the file stored. Both reach only the owner's own content.
- `delete-account` can leave a file behind if another of the user's devices uploads between its last listing and the user's deletion; the user's row goes by cascade, and the file stays orphaned in the bucket.

## Signs the decision was wrong

- Storage or egress costs become material, which would ask for S3 or R2 behind the same ids.
- Users ask to frame the crop themselves, which would ask for an interactive cropper.
- Orphaned files pile up on the server, which would ask for a sweep that deletes files no row names.
