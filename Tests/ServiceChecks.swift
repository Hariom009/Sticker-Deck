import Foundation
import UIKit
import ImageIO

@MainActor
final class TestClipboard: StickerClipboard {
    var copied = false
    var copiedGIF = false
    func copy(gif: Data, fallback: UIImage) throws { copiedGIF = true }
    func copy(_ image: UIImage) throws { copied = true }
}

@MainActor
final class FailingRepository: StickerRepository {
    var failLoad = false
    var writes = 0
    var initial: [Sticker] = []
    func load() throws -> [Sticker] {
        if failLoad { throw CocoaError(.fileReadCorruptFile) }
        return initial
    }
    func save(_ stickers: [Sticker]) throws { writes += 1; throw CocoaError(.fileWriteNoPermission) }
    func image(named: String) -> UIImage? { StickerImageService.sample("☕️") }
    func store(_ image: UIImage) throws -> String { throw CocoaError(.fileWriteNoPermission) }
    func removeUnreferencedImages(keeping stickers: [Sticker]) {}
}

struct StubSubjectService: SubjectCutting {
    let fails: Bool
    nonisolated func cutout(from image: UIImage) async throws -> UIImage {
        if fails { throw SubjectCutoutError.noSubject }
        return image
    }
}

@main
struct ServiceChecks {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = LocalStickerRepository(directory: directory)
        let initial = try repo.load()
        assert(initial.isEmpty)
        let clipboard = TestClipboard()
        let model = StickerLibraryViewModel(repository: repo, clipboard: clipboard)
        let draft = StickerEditorViewModel(source: StickerImageService.sample("☕️"))
        draft.appearance = .legacy
        draft.name = "Coffee"
        draft.caption = "Hello"
        model.save(draft)
        assert(model.stickers.count == 1)
        let saved = model.stickers[0]
        assert(repo.image(named: saved.renderedFile) != nil)
        let restored = StickerLibraryViewModel(repository: LocalStickerRepository(directory: directory), clipboard: clipboard)
        assert(restored.stickers == model.stickers)
        restored.copy(saved)
        assert(clipboard.copied && restored.stickers[0].lastCopiedAt != nil)
        restored.toggleFavorite(saved)
        assert(restored.stickers[0].isFavorite)
        restored.edit(restored.stickers[0])
        restored.editor?.name = "Changed"
        assert(restored.stickers[0].name == "Coffee")
        if let edit = restored.editor { restored.save(edit) }
        assert(restored.stickers[0].name == "Changed")
        assert(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("images").appendingPathComponent(saved.renderedFile).path))
        assert(restored.delete(restored.stickers[0]))
        let remaining = try repo.load()
        assert(remaining.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("images"), includingPropertiesForKeys: nil)
        assert(files.isEmpty)
        let failed = FailingRepository()
        failed.initial = [saved]
        let failingModel = StickerLibraryViewModel(repository: failed, clipboard: clipboard)
        assert(!failingModel.delete(saved))
        assert(failingModel.stickers == [saved] && failingModel.errorMessage != nil)
        failed.failLoad = true
        let unreadable = StickerLibraryViewModel(repository: failed, clipboard: clipboard)
        let previousWrites = failed.writes
        assert(unreadable.loadFailed)
        unreadable.save(draft)
        assert(failed.writes == previousWrites)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let circle = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).image { ctx in
            UIColor.red.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 10, y: 10, width: 80, height: 80))
        }
        let cutoutDraft = StickerEditorViewModel(source: circle, subjectService: StubSubjectService(fails: false))
        assert(!cutoutDraft.canSave)
        await cutoutDraft.prepareCutout()
        assert(cutoutDraft.cutout != nil && cutoutDraft.canSave && cutoutDraft.appearance.removesBackground)
        let outlined = cutoutDraft.renderedImage()
        let cg = outlined.cgImage!
        var pixels = [UInt8](repeating: 0, count: 512 * 512 * 4)
        let context = CGContext(data: &pixels, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 512 * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 512, height: 512))
        func pixel(_ x: Int, _ y: Int) -> [UInt8] { Array(pixels[((y * 512 + x) * 4)..<((y * 512 + x) * 4 + 4)]) }
        assert(pixel(0, 0)[3] == 0, "PNG corners must remain transparent")
        assert(pixel(256, 256)[0] > 240 && pixel(256, 256)[1] < 10, "Subject color must remain intact")
        assert(pixel(112, 256)[0] > 230 && pixel(112, 256)[1] > 230 && pixel(112, 256)[3] > 230,
               "Outline must extend outside the subject as an opaque white silhouette")
        try outlined.pngData()!.write(to: URL(fileURLWithPath: "/tmp/sticker-outline-check.png"))
        cutoutDraft.appearance.shadow = true
        cutoutDraft.appearance.flipped = true
        cutoutDraft.appearance.captionFont = .rounded
        cutoutDraft.appearance.captionPlacement = .top
        cutoutDraft.caption = "Hello"
        cutoutDraft.appearance.captionPosition = CaptionPosition(x: 0.98, y: 0.02)
        let captionRect = StickerImageService.captionLayout(cutoutDraft.caption, appearance: cutoutDraft.appearance)!.rect
        assert(CGRect(x: 0, y: 0, width: 512, height: 512).contains(captionRect), "Dragged caption must stay inside the canvas")
        assert(captionRect.maxX == 512 && captionRect.minY == 0, "Caption clamps to the edge it was dragged past")
        cutoutDraft.appearance.motion = .glitter
        let frames = cutoutDraft.renderedFrames()
        assert(frames.count == 40, "2 seconds at 20 FPS")
        assert(StickerImageService.gifData(frames: frames) != nil, "Frames encode as a GIF")
        model.reload()
        model.save(cutoutDraft)
        let subjectRecord = model.stickers[0]
        assert(subjectRecord.cutoutFile != nil && subjectRecord.appearance == cutoutDraft.appearance)
        assert(subjectRecord.animatedFile != nil && repo.data(named: subjectRecord.animatedFile!) != nil, "Motion saves a GIF beside the PNG")
        model.edit(subjectRecord)
        assert(model.editor?.cutout != nil && model.editor?.appearance == cutoutDraft.appearance)
        assert(!model.editor!.hasChanges)
        model.copy(subjectRecord)
        assert(clipboard.copiedGIF, "Animated stickers use the GIF clipboard path")
        assert(model.delete(subjectRecord))
        cutoutDraft.change("outline") { cutoutDraft.appearance.outlineWidth = 14 }
        assert(cutoutDraft.canUndo && cutoutDraft.appearance.outlineWidth == 14)
        cutoutDraft.undo()
        assert(cutoutDraft.appearance.outlineWidth == 8 && cutoutDraft.canRedo)
        cutoutDraft.redo()
        assert(cutoutDraft.appearance.outlineWidth == 14)
        cutoutDraft.appearance.animationSettings = StickerAnimationSettings(duration: 1, framesPerSecond: 15, playback: .reverse)
        let shortFrames = cutoutDraft.renderedFrames()
        assert(shortFrames.count == 15)
        let shortGIF = StickerImageService.gifData(frames: shortFrames, framesPerSecond: 15)!
        let gifSource = CGImageSourceCreateWithData(shortGIF as CFData, nil)!
        assert(CGImageSourceGetCount(gifSource) == 15)
        let properties = CGImageSourceCopyPropertiesAtIndex(gifSource, 0, nil)! as NSDictionary
        let gifProperties = properties[kCGImagePropertyGIFDictionary] as! NSDictionary
        let delay = (gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as! NSNumber).doubleValue
        assert(abs(delay - 1.0 / 15) < 0.01, "GIF delay matches selected frame rate")
        var capped = StickerAnimationSettings(duration: 9, framesPerSecond: 120, playback: .pingPong)
        assert(capped.safeDuration == 2 && capped.safeFPS == 20 && capped.frameCount == 40)
        assert(abs(capped.phase(0.25) - capped.phase(0.75)) < 0.001)
        capped.playback = .reverse
        assert(abs(capped.phase(0.2) - 0.8) < 0.001)
        cutoutDraft.appearance.outlineHex = "#123456"
        cutoutDraft.appearance.captionHex = "#ABCDEF"
        cutoutDraft.appearance.output = .png
        model.save(cutoutDraft)
        let stillRecord = model.stickers[0]
        assert(stillRecord.animatedFile == nil && stillRecord.appearance?.outlineHex == "#123456")
        let roundTrip = try repo.load()
        assert(roundTrip[0].appearance?.animationSettings?.framesPerSecond == 15)
        assert(roundTrip[0].appearance?.output == .png)
        model.save(cutoutDraft)
        let extraRecord = model.stickers.last!
        assert(extraRecord.id != stillRecord.id)
        assert(model.delete(ids: [stillRecord.id, extraRecord.id]))
        assert(!model.stickers.contains { $0.id == stillRecord.id || $0.id == extraRecord.id }, "Bulk delete removes every selected sticker")

        let failedDraft = StickerEditorViewModel(source: circle, subjectService: StubSubjectService(fails: true))
        await failedDraft.prepareCutout()
        assert(failedDraft.cutout == nil && failedDraft.cutoutMessage != nil && failedDraft.canSave)
        assert(!failedDraft.appearance.removesBackground)
        let encoded = try JSONEncoder().encode(saved)
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy.removeValue(forKey: "appearance")
        legacy.removeValue(forKey: "cutoutFile")
        let legacySticker = try JSONDecoder().decode(Sticker.self, from: JSONSerialization.data(withJSONObject: legacy))
        assert(legacySticker.appearance == nil && legacySticker.cutoutFile == nil)
        let legacyEditor = StickerEditorViewModel(source: circle, existing: legacySticker)
        assert(!legacyEditor.appearance.removesBackground && legacyEditor.appearance.outlineWidth == 0)
        let importDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: importDirectory) }
        let importRepo = LocalStickerRepository(directory: importDirectory)
        let importer = StickerLibraryViewModel(repository: importRepo, clipboard: clipboard, subjectService: StubSubjectService(fails: false))
        let opaqueFormat = UIGraphicsImageRendererFormat()
        opaqueFormat.scale = 1
        opaqueFormat.opaque = true
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 60), format: opaqueFormat).image { ctx in
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        }
        let animated = StickerImageService.gifData(frames: [circle, circle])!
        await importer.importBatch([
            StickerImport(name: nil) { photo.jpegData(compressionQuality: 0.9) },
            StickerImport(name: "Party cat") { circle.pngData() },
            StickerImport(name: nil) { animated },
            StickerImport(name: nil) { Data("not an image".utf8) },
        ])
        assert(importer.stickers.count == 3 && !importer.isImporting, "Three good items import, the broken one is skipped")
        assert(importer.stickers[0].name == "Sticker 1" && importer.stickers[0].cutoutFile != nil &&
               importer.stickers[0].appearance?.removesBackground == true, "Opaque photos get their subject lifted")
        assert(importer.stickers[1].name == "Party cat" && importer.stickers[1].cutoutFile == nil &&
               importer.stickers[1].appearance?.outlineWidth == 0, "Already-transparent stickers are kept as they are")
        assert(importer.stickers[2].animatedFile.flatMap { importRepo.data(named: $0) } != nil, "Animated GIFs keep their animation")
        assert(importer.toast?.contains("couldn’t be opened") == true, "Partial failure is reported")
        let persistedImports = try importRepo.load()
        assert(persistedImports.count == 3, "Batch is persisted")

        // "New" marks: every import is marked, copying clears one, closing the app clears the rest.
        assert(importer.stickers.allSatisfy(importer.isNew))
        importer.copy(importer.stickers[0])
        assert(!importer.isNew(importer.stickers[0]) && importer.isNew(importer.stickers[1]))
        importer.clearNewMarks()
        assert(!importer.stickers.contains(where: importer.isNew))

        // Sticker sheet: three round stickers in a row, a two-part sticker below (3 px gap), and a stray speck.
        let transparentSheet = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200), format: format).image { ctx in
            UIColor.red.setFill()
            for x in [50.0, 150, 250] { ctx.cgContext.fillEllipse(in: CGRect(x: x - 30, y: 70, width: 60, height: 60)) }
            ctx.fill(CGRect(x: 20, y: 160, width: 40, height: 30))
            ctx.fill(CGRect(x: 63, y: 160, width: 37, height: 30))
            ctx.fill(CGRect(x: 5, y: 5, width: 2, height: 2))
        }
        let pieces = StickerSheetSplitter.split(transparentSheet)
        assert(pieces.count == 4, "Three circles plus one merged two-part sticker; the speck is dropped")
        assert(pieces[0...2].allSatisfy { abs($0.size.width - 60) <= 2 }, "Circles come first, cropped tight")
        assert(abs(pieces[3].size.width - 80) <= 2, "Close parts stay one sticker, read after the row above")

        func alpha(_ image: UIImage, _ x: Int, _ y: Int) -> UInt8 {
            var pixel = [UInt8](repeating: 0, count: 4)
            let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image.cgImage!, in: CGRect(x: -x, y: y - image.cgImage!.height + 1, width: image.cgImage!.width, height: image.cgImage!.height))
            return pixel[3]
        }
        // Plain white sheet: the white eye inside a sticker must stay, the background must go.
        let whiteSheet = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200), format: opaqueFormat).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            UIColor.red.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 30, y: 50, width: 100, height: 100))
            ctx.cgContext.fillEllipse(in: CGRect(x: 170, y: 50, width: 100, height: 100))
            UIColor.white.setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 70, y: 90, width: 20, height: 20))
        }
        let keyed = StickerSheetSplitter.keyedBackground(whiteSheet)!
        assert(alpha(keyed, 2, 2) == 0 && alpha(keyed, 80, 100) == 255, "Background keyed out, enclosed white kept")
        let busy = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200), format: opaqueFormat).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 150, height: 200))
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 150, y: 0, width: 150, height: 200))
        }
        assert(StickerSheetSplitter.keyedBackground(busy) == nil, "No keying without a plain border")

        let transparentReview = StickerSheetViewModel(source: transparentSheet, subjectService: StubSubjectService(fails: false))
        await transparentReview.detect()
        assert(transparentReview.pieces.count == 4 && transparentReview.allSelected && !transparentReview.needsOutline)
        transparentReview.toggle(3)
        assert(transparentReview.chosen.count == 3)
        // The stub "cutout" returns the opaque sheet unchanged (one piece); keying finds both stickers and wins.
        let opaqueReview = StickerSheetViewModel(source: whiteSheet, subjectService: StubSubjectService(fails: false))
        await opaqueReview.detect()
        assert(opaqueReview.pieces.count == 2 && opaqueReview.needsOutline)
        await importer.addSheetPieces(opaqueReview.chosen, outlined: opaqueReview.needsOutline)
        assert(importer.stickers.count == 5 && importer.sheetReview == nil)
        assert(importer.stickers.suffix(2).allSatisfy { importer.isNew($0) && ($0.appearance?.outlineWidth ?? 0) > 0 },
               "Sheet pieces are new and outlined when cut from an opaque sheet")
        if CommandLine.arguments.count > 1 {
            let photoData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            guard let photo = StickerImageService.downsample(photoData) else { fatalError("Invalid smoke-test image") }
            do {
                let subject = try await AppleSubjectCutoutService().cutout(from: photo)
                try subject.pngData()!.write(to: URL(fileURLWithPath: "/tmp/sticker-vision-smoke.png"))
                print("Apple Vision smoke test: produced \(subject.size) transparent cutout.")
            } catch {
                print("Apple Vision smoke test unavailable: \(error.localizedDescription)")
            }
        }
        print("Passed: editor undo/redo, GIF frame count/timing, playback mapping, duration cap, output choice, custom colors and style persistence.")
        print("Passed: subject success/failure, transparent outline pixels, editable style persistence, legacy migration.")
        print("Passed: bulk import of photos, transparent stickers, animated GIFs, broken items, and persistence.")
        print("Passed: sticker sheet splitting, reading order, speck filtering, background keying with hole fill, review selection, new marks.")
        print("Passed: save/reload, PNG rendering, copy, recents, favorites, isolated editor, file cleanup, failed-save rollback, unreadable-library protection.")
    }
}
