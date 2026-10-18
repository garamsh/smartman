# ADR 0054: Take the photo with the system camera or from the library, and remove the in-app camera view

> Status: accepted; its source sheet and the retake that reopened it superseded by ADR-0067
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #174 records the owner's report of 2026-10-18: on an iPhone 13 Pro with `main`'s release build, the capture screen stays black. Asked, the owner chose to take the photo with the iPhone's own camera instead of fixing the in-app view.
- On `main` at `63a4903f009cb1cb78ca1065180de87f744c11ab`, photo import opens on a full-screen camera view drawn with the `camera` package: a page-frame guide and hint, the deck chip, the detail step slider ([ADR 0052](0052-choose-a-photo-s-cards-and-how-full-their-answers-are-on-a-five-step-slider-in-the-app.md)), an album button through `image_picker`, and the shutter. The app releases the camera while it is out of the foreground and opens it again on return.
- **The black screen's cause, from the code.** No device log was read.
  - The view drew `camera` 0.12.1's `CameraPreview` inside a `FittedBox` with `BoxFit.cover`. `CameraPreview` is an `AspectRatio` over the platform view.
  - Flutter 3.47.7's `RenderFittedBox` lays out its child with unbounded constraints, and `RenderAspectRatio` given unbounded width and height has no size to take.
  - A debug build throws a `FlutterError` there. A release build strips the assertion: the preview takes an infinite size, and the `FittedBox` scales it to nothing, so nothing is painted over the black ground.
  - The tests drew a fixed-size stand-in for the preview, and the simulator has no camera, so neither path ever drew a real one.
- The PM confirmed the details below on 2026-10-18, on the worker's question in the dispatch.
- Alternatives considered:
  - Fixing the in-app view by giving the preview a bounded size. The owner chose the system camera, which handles focus and exposure and whose screen users know, and it removes the lifecycle code with the view.
  - Opening the photo import screen first and showing the source sheet over it. A cancel would then have to close a screen the user never asked to see.

## Decision

- **Entry.** The photo buttons of the home and deck screens open a sheet, "사진 가져오기", with "사진 찍기" (the system camera) and "앨범에서 고르기" (the library), both through `image_picker`. The screen opens only with a photo, on the Extracting step. A sheet dismissed or a picker cancelled opens nothing and shows no error. `photoImportProvider` therefore provides a function that starts the import over a context and resolves to the deck saved into. It used to provide the screen.
- **Retake.** "다시 찍기" on Review and on a failure opens the same sheet over the screen. A cancel leaves the screen as it was, and a photo replaces the review. "취소" while extracting closes the screen.
- **Review.** The deck chip "추가할 덱 · <name>" moves to Review, under the hint, which no longer names the deck. Choosing another deck reads that deck's card keys and regroups the duplicates against them. The slider is on Review alone. Everything else on Review is unchanged.
- **Refusal.** `image_picker`'s codes for refused or restricted camera or photo access are `PhotoAccessDenied`. It is shown in place of the screen with a retake and "설정 열기", which opens the app's page in iOS's settings through `url_launcher`'s `app-settings:`. When that page does not open, a snack bar says so. `CameraUnavailable`, a device with no camera, offers the retake, where the album still works.
- **Android.** The app declares neither `CAMERA` nor `RECORD_AUDIO`. `image_picker` asks for the camera permission only when the manifest declares it, so its camera intent and photo picker ask for nothing and never report a refusal. No dependency the app has opens Android's app settings page, and none is added for a refusal that cannot happen there.
- **Removed.** The `camera` dependency, the camera view with its page-frame guide, hint and shutter, `CameraSession`, the lifecycle code, `NSMicrophoneUsageDescription`, and the manifest's `CAMERA` and `RECORD_AUDIO` lines. `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` stay for `image_picker`.
- **Supersessions.** This replaces ADR 0052's slider "in capture and review" with the slider on Review alone.

## Consequences

- The black screen goes with the view. The removal is not a fix of an unknown bug: the cause above is the one the code shows.
- The camera's focus, exposure and screen are the system's, and the app has no page-frame guide. A photo framed badly is caught by the review, or by `NoCardsFound`.
- The deck and the step are chosen after the photo, so the user sees the cards before choosing where they go.
- A real-device check is the PM's after merge, since the simulator has no camera.

## Signs the decision was wrong

- Users ask for the frame guide, or more photos come back as `NoCardsFound` than before.
- The extra tap on the source sheet is a step users skip past: most pick the same source every time.
