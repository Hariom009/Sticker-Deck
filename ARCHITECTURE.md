# Sticker Deck architecture

Read this file before changing the app. Update it when responsibilities or paths change.

## Structure: SwiftUI + MVVM

- `Sticker Deck/Sticker_DeckApp.swift`: composition root. Creates the repository and library view model once per app lifecycle.
- `Sticker Deck/ContentView.swift`: thin root, injects the library view model into the library screen.
- `Models/Sticker.swift`: Codable metadata, collection/filter/sort enums, and deterministic library querying. No UI or disk access.
- `Models/StickerAppearance.swift`: persisted cutout preference, outline, shadow, flip, and caption style. Optional appearance/cutout fields on Sticker preserve decoding of older libraries.
- `Services/SubjectCutoutService.swift`: cancellable Apple Vision foreground extraction on a worker task, behind the injectable SubjectCutting protocol. Crops all detected subjects together and retains alpha; explicit no-subject/unavailable errors.
- `Services/StickerSheetSplitter.swift`: pure, nonisolated pixel work for sticker sheets. Splits an alpha mask into connected regions after a small dilation (`mergeDistance`, 1.2% of the longer side) so a sticker's detached parts stay together; drops specks under 2% of the largest region; returns tight crops in reading order (max 40). `keyedBackground` makes a plain-background sheet transparent from its median border color and keeps background-colored holes enclosed by a sticker.
- `ViewModels/StickerLibraryViewModel.swift`: single source of truth for the library; loading, querying, import state, bulk import, copying, favorites, delete, editor saves, and user-facing feedback.
- `ViewModels/StickerEditorViewModel.swift`: isolated editable draft, extraction/loading/failure state, validation, and output rendering. Source photo and cutout remain separate; new drafts auto-extract when the editor appears. Save is disabled during extraction or while a requested cutout is absent. Cancel never mutates the saved sticker.
- `ViewModels/StickerSheetViewModel.swift`: review state for one sticker sheet: detection, found pieces, and which are selected. Transparent sheets split on their own alpha; opaque sheets try the Vision cutout and background keying and keep whichever finds more stickers (Vision wins ties).
- `Services/StickerRepository.swift`: repository protocol and local implementation. Atomic metadata writes in Application Support/StickerDeck/library.json; original source, optional cutout, and rendered PNGs in its images directory. Image cache is bounded. Files referenced by metadata are retained until a successful save.
- `Services/StickerImageService.swift`: downsample imports, render transparent PNGs with alpha-based Core Image outline dilation, optional shadow/flip and caption styling, and write PNG clipboard data. Keep platform image and clipboard APIs here.
- `Theme/DeckTheme.swift`: semantic monochrome colors and shared visual tokens. App icon is the palette reference; no arbitrary category colors or promotional home copy.
- `Views/Library/StickerLibraryView.swift`: compact header, search, filters, sorting, grid, single and multi-select photo pickers, file importer, import progress, and presentation routing.
- `Views/Library/StickerSheetReviewView.swift`: grid of stickers found on a sheet, all selected by default; tap to leave one out, Select all/none, then Add N stickers.
- `Views/Components/StickerTile.swift`: copy target, long-press selection, and separate preview action. Reused image display.
- `Views/Detail/StickerDetailView.swift`: expanded image and top actions; routes edits back through the library.
- `Views/Editor/StickerEditorView.swift`: direct canvas editor for both new and existing stickers. Fixed preview, Undo/Redo and Play/Pause, four labeled tools (Subject, Outline, Text, Motion), and one inline tool panel at a time. Size and tilt have no sliders: pinch/twist gestures adjust subject size/tilt; gestures starting on the caption resize/move text.
- `Views/Editor/StickerEditorControls.swift`: contextual controls, subject cutout and flip, outline presets/slider/custom color, caption styling/placement, animation presets, duration, playback and FPS. Clip/Live Photo entry clearly explains that import processing is pending.
- `Views/Editor/StickerSaveView.swift`: optional name, collection, PNG/GIF output and final save confirmation. Opaque sheet with background interaction disabled.
- `Tests/ServiceChecks.swift` and `Tests/run-service-checks.sh`: simulator-executed checks for persistence, rendering, draft isolation, metadata mutations, cleanup, and failure rollback.
- `Tests/LibraryQueryChecks.swift`: executable checks for query/sort and metadata encoding, run with the command below.

## Data flow

View intent → @MainActor @Observable view model → injected repository/image service → updated model → SwiftUI.
Views own transient presentation state (sheet, confirmation, picker selection). View models own business state. Models never import SwiftUI. No disk or clipboard calls in views. Services are injected through protocols where persistence/copying side effects need substitution.

A save writes new source/rendered files first, then atomically commits metadata. Failure leaves the previous library intact. After commit, unreferenced image files are removed. Favorite/recent metadata changes use the same commit path. Failed loads surface an error and block mutations until a successful retry; never overwrite an unreadable library with an empty one.

## Interaction contract

- Tap a grid sticker: copy its rendered transparent PNG, show brief feedback, record recent use.
- Tap its ellipsis: open detail; do not copy. Preview, Copy, Edit, Favorite, and Delete remain accessible without long press.
- Long-press a grid sticker (or VoiceOver's Select action): enter selection. While selecting, taps toggle selection instead of copying, the ellipsis becomes a checkmark, the logo becomes Deselect all with a count, the header controls become Delete, and the create buttons hide. Delete asks for confirmation, then removes every selected sticker in one commit. Deselecting the last sticker ends selection.
- Search matches name, caption, and collection. Favorites and Recent intersect with search/collection. Recent orders by last copied time.
- Create opens the system photo picker, which grants access only to the chosen item. No full-library permission prompt is needed.
- The round button beside Create adds several stickers at once, from Photos (up to 30, in pick order) or Files (any count), without opening the editor. Each image is decoded off the main actor. Opaque photos get their subject lifted with the default outline, or stay whole if no subject is found. Images that are already see-through and multi-frame GIFs are kept exactly as they are; a GIF is stored as `animatedFile`, with its first frame as the still. File names become sticker names; otherwise "Sticker N". New stickers join the selected collection, or Things. Each sticker is committed as soon as it is ready, with no await between storing its files and the commit, so cleanup never removes in-flight files. Unreadable items are skipped and counted in the closing toast.
- The same menu splits a sticker sheet (one image holding many stickers) from Photos or Files. The sheet is opened at up to 2048 px so each piece stays sharp, reviewed in its own sheet, and the chosen pieces go through the bulk-import path. Pieces cut from an opaque sheet get the default outline because keying removes the creator's white border; pieces from a transparent sheet are kept as they are.
- Newly added stickers (editor saves of new stickers, bulk imports, sheet pieces) show a small NEW tag on the tile. Marks live only in memory: copying a sticker clears its mark, and the app going to the background clears all of them.
- Presentation surfaces and navigation bars use opaque semantic backgrounds. The library’s floating create button and toast are hidden and noninteractive during the photo picker, import, detail, editor, and detail-to-editor handoff; its inset remains reserved to avoid grid jumps. The canvas and tool bar stay in place while only the active control panel scrolls. Import opens the editor directly and lifts the subject automatically; there is no separate long-press/photo step. Save opens an opaque sheet for optional name, collection, and output format.
- New photos auto-extract the subject on appear. Failure shows a contextual Retry in the Subject tool and keeps the original usable. Original/cutout switching preserves both images. Existing stickers retain their appearance. Outline presets are None/Thin/Medium/Thick (0/4/8/14) with a 0...20 slider; optional hex colors override monochrome swatches for sticker art only. App chrome stays monochrome. Text drag stores normalized captionPosition; nil falls back to legacy placement.
- Editor undo/redo is owned by the view model, with bounded snapshots and coalescing for continuous edits. Automatic cutout and Save metadata are outside this history. Cached outlined preview layers keep animation transforms aligned with exported frames.
- Name is optional: an empty name is filled on save from the caption, else a running number.
- Save persists a draft; Cancel discards it. Deletion requires confirmation.
- Production starts empty. Debug-only `-demo-library` and `-demo-editor` use an isolated temporary demo repository for simulator design review; it never modifies a user's saved collection.

## Current scope and extension points

Static images, Apple Vision subject cutout, original/cutout switching, outline thickness/color, shadow, flipping, caption font/size/color/placement, scale/rotation, collections, favorites, recent use, PNG copying, and local persistence are implemented. Cutout includes all detected foreground instances; individual subject selection and manual mask refinement are not implemented. Motion preserves legacy Wobble/Bounce/Pulse/Glitter and adds Spin/Float/Pop/Shake. Optional animationSettings store 0.5...2-second duration, 15/20 FPS and Loop/Reverse/Back-and-forth. The same phase mapping and composition drive preview and GIF. Legacy settings default to 2 seconds at 20 FPS. Save can choose a still PNG or looping GIF; copying a GIF sticker includes its still PNG fallback. Clip/Live Photo importing, individual subject selection and animated PNG export are not implemented. iCloud sync, system sticker-pack installation, and sharing remain unimplemented. Do not put image processing inside views.

## Build and checks

The Xcode project uses filesystem-synchronized groups. Swift files under `Sticker Deck/` join the app target automatically. Keep scripts/docs/tests outside that directory unless adding an explicit test target. Current deployment target is iOS 27 (unchanged).

```sh
xcodebuild -project 'Sticker Deck.xcodeproj' -scheme 'Sticker Deck' -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/sticker-deck-build CODE_SIGNING_ALLOWED=NO build
swiftc 'Sticker Deck/Models/StickerAppearance.swift' 'Sticker Deck/Models/Sticker.swift' Tests/LibraryQueryChecks.swift -o /tmp/sticker-deck-checks
/tmp/sticker-deck-checks
# With an iOS simulator booted:
sh Tests/run-service-checks.sh
# Optional: pass a photo path to smoke-test Apple Vision on the booted simulator.
# Real-device testing is still required for subject accuracy and device support.
```

For UI changes check compact and larger widths, dark mode, large text, empty/search-empty states, copy feedback, and top toolbar actions. For persistence changes verify relaunch and failed-write behavior. Do not commit generated build output.
