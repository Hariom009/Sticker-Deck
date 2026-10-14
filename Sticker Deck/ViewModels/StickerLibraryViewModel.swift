import SwiftUI

/// One item of a bulk import. `name` comes from a file name when there is one.
/// `addsOutline` gives an already-transparent image the default outline (pieces cut from an opaque sheet).
struct StickerImport {
    var name: String?
    var addsOutline = false
    var load: () async throws -> Data?
}

@MainActor @Observable
final class StickerLibraryViewModel {
    private(set) var stickers: [Sticker] = []
    private(set) var isLoadingPhoto = false
    private(set) var importProgress: (done: Int, total: Int)?
    /// Stickers added this session. Not persisted: a fresh launch starts empty, and copying a sticker clears its mark.
    private(set) var newStickerIDs: Set<UUID> = []
    var sheetReview: StickerSheetViewModel?
    private(set) var loadFailed = false
    var search = ""
    var filter: LibraryFilter = .all
    var collection: StickerCollection?
    var sort: LibrarySort = .newest
    var errorMessage: String?
    var toast: String?
    var editor: StickerEditorViewModel?
    private let repository: any StickerRepository
    private let clipboard: any StickerClipboard
    private let subjectService: any SubjectCutting
    private var toastTask: Task<Void, Never>?

    init(repository: any StickerRepository, clipboard: (any StickerClipboard)? = nil,
         subjectService: (any SubjectCutting)? = nil) {
        self.repository = repository
        self.clipboard = clipboard ?? SystemStickerClipboard()
        self.subjectService = subjectService ?? AppleSubjectCutoutService()
        reload()
    }

    var isImporting: Bool { importProgress != nil }
    func isNew(_ sticker: Sticker) -> Bool { newStickerIDs.contains(sticker.id) }
    func clearNewMarks() { newStickerIDs.removeAll() }

    var visibleStickers: [Sticker] {
        LibraryQuery.results(stickers, search: search, filter: filter, collection: collection, sort: sort)
    }
    func reload() {
        do { stickers = try repository.load(); loadFailed = false }
        catch { loadFailed = true; errorMessage = "Your collection couldn’t be opened. Retry before making changes." }
    }
    func image(for sticker: Sticker) -> UIImage? { repository.image(named: sticker.renderedFile) }
    func sticker(id: UUID) -> Sticker? { stickers.first { $0.id == id } }

    @discardableResult private func commit(_ updated: [Sticker]) -> Bool {
        guard !loadFailed else { return false }
        do { try repository.save(updated); stickers = updated; return true }
        catch { errorMessage = "Changes couldn’t be saved. Please try again."; return false }
    }
    func copy(_ sticker: Sticker) {
        guard let image = image(for: sticker) else { errorMessage = "This sticker’s image is missing."; return }
        do {
            if let file = sticker.animatedFile, let gif = repository.data(named: file) { try clipboard.copy(gif: gif, fallback: image) }
            else { try clipboard.copy(image) }
            var updated = stickers
            if let index = updated.firstIndex(where: { $0.id == sticker.id }) {
                updated[index].lastCopiedAt = Date()
                _ = commit(updated)
            }
            newStickerIDs.remove(sticker.id)
            showToast("Sticker copied")
        } catch { errorMessage = "This sticker couldn’t be copied." }
    }
    func toggleFavorite(_ sticker: Sticker) {
        var updated = stickers
        guard let index = updated.firstIndex(where: { $0.id == sticker.id }) else { return }
        updated[index].isFavorite.toggle()
        commit(updated)
    }
    @discardableResult func delete(_ sticker: Sticker) -> Bool { delete(ids: [sticker.id]) }
    @discardableResult func delete(ids: Set<UUID>) -> Bool {
        let success = commit(stickers.filter { !ids.contains($0.id) })
        if success {
            newStickerIDs.subtract(ids)
            repository.removeUnreferencedImages(keeping: stickers)
            showToast(ids.count == 1 ? "Sticker deleted" : "\(ids.count) stickers deleted")
        }
        return success
    }
    func edit(_ sticker: Sticker) {
        guard let source = repository.image(named: sticker.sourceFile) else { errorMessage = "The original image is missing."; return }
        let cutout = sticker.cutoutFile.flatMap { repository.image(named: $0) }
        editor = StickerEditorViewModel(source: source, existing: sticker, cutout: cutout)
    }
    func importPhoto(loadData: () async throws -> Data?) async {
        guard !loadFailed, !isLoadingPhoto else { return }
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        do {
            guard let data = try await loadData() else { throw CocoaError(.fileReadCorruptFile) }
            let image = await Task.detached(priority: .userInitiated) { StickerImageService.downsample(data) }.value
            guard !Task.isCancelled else { return }
            guard let image else { throw CocoaError(.fileReadCorruptFile) }
            editor = StickerEditorViewModel(source: image)
        } catch { if !Task.isCancelled { errorMessage = "This photo couldn’t be opened. Choose another image or try again." } }
    }
    /// Files picked in the document browser are security-scoped; access is opened only while each file is read.
    private static func readScoped(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }
    func importFiles(_ urls: [URL]) async {
        await importBatch(urls.map { url in
            StickerImport(name: url.deletingPathExtension().lastPathComponent) { try Self.readScoped(url) }
        })
    }

    /// Opens one sticker sheet for review. Sheets keep up to 2048 px so each cut-out sticker stays sharp.
    func reviewSheet(loadData: () async throws -> Data?) async {
        guard !loadFailed, !isLoadingPhoto else { return }
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        do {
            guard let data = try await loadData() else { throw CocoaError(.fileReadCorruptFile) }
            let image = await Task.detached(priority: .userInitiated) { StickerImageService.downsample(data, maxPixelSize: 2048) }.value
            guard !Task.isCancelled else { return }
            guard let image else { throw CocoaError(.fileReadCorruptFile) }
            sheetReview = StickerSheetViewModel(source: image, subjectService: subjectService)
        } catch { if !Task.isCancelled { errorMessage = "This image couldn’t be opened. Choose another image or try again." } }
    }
    func reviewSheetFile(_ url: URL) async { await reviewSheet { try Self.readScoped(url) } }

    /// Adds the chosen pieces of a reviewed sheet through the normal bulk path.
    func addSheetPieces(_ pieces: [UIImage], outlined: Bool) async {
        sheetReview = nil
        await importBatch(pieces.map { piece in StickerImport(addsOutline: outlined) { piece.pngData() } })
    }

    /// Adds many images straight to the library, no editor. Photos get their subject lifted with the default outline;
    /// images that are already see-through (existing stickers) and animated GIFs are kept exactly as they are.
    /// Each sticker is committed as soon as it is ready, so files are never unreferenced across an await.
    func importBatch(_ items: [StickerImport]) async {
        guard !loadFailed, importProgress == nil, !items.isEmpty else { return }
        importProgress = (0, items.count)
        defer { importProgress = nil }
        var added = 0, failed = 0
        for item in items {
            guard !Task.isCancelled else { break }
            do {
                guard let data = try await item.load() else { throw CocoaError(.fileReadCorruptFile) }
                guard let decoded = await Task.detached(priority: .userInitiated, operation: { StickerImageService.decodeImport(data) }).value
                else { throw CocoaError(.fileReadCorruptFile) }
                var appearance = StickerAppearance()
                var cutout: UIImage?
                if decoded.isAnimatedGIF || decoded.hasTransparency {
                    appearance.removesBackground = false
                    if !item.addsOutline { appearance.outlineWidth = 0 }
                } else if let subject = try? await subjectService.cutout(from: decoded.image) {
                    cutout = subject
                } else {
                    appearance.removesBackground = false
                }
                // No awaits from here to commit: a concurrent save/delete cleanup can't see these files unreferenced.
                let rendered = StickerImageService.render(source: cutout ?? decoded.image, caption: "", scale: 1, rotation: 0, appearance: appearance)
                let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                var record = Sticker(name: name.flatMap { $0.isEmpty ? nil : String($0.prefix(60)) } ?? "Sticker \(stickers.count + 1)",
                                     sourceFile: try repository.store(decoded.image), renderedFile: try repository.store(rendered))
                record.collection = collection ?? .things
                record.appearance = appearance
                if let cutout { record.cutoutFile = try repository.store(cutout) }
                if decoded.isAnimatedGIF { record.animatedFile = try repository.store(data, extension: "gif") }
                guard commit(stickers + [record]) else {
                    repository.removeUnreferencedImages(keeping: stickers)
                    failed += items.count - added - failed
                    break
                }
                newStickerIDs.insert(record.id)
                added += 1
            } catch {
                repository.removeUnreferencedImages(keeping: stickers)
                failed += 1
            }
            importProgress?.done += 1
        }
        guard added > 0 || failed > 0 else { return }
        if added > 0 { search = ""; filter = .all }
        if failed == 0 { showToast(added == 1 ? "1 sticker added" : "\(added) stickers added") }
        else if added == 0 { errorMessage = "These images couldn’t be imported. Try different files." }
        else { showToast("\(added) added · \(failed) couldn’t be opened") }
    }

    func save(_ draft: StickerEditorViewModel) {
        guard draft.canSave, !loadFailed else { return }
        do {
            let sourceFile: String
            if let existing = draft.existing { sourceFile = existing.sourceFile }
            else { sourceFile = try repository.store(draft.source) }
            let renderedFile = try repository.store(draft.renderedImage())
            var record = draft.existing ?? Sticker(name: draft.name, sourceFile: sourceFile, renderedFile: renderedFile)
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            record.name = !name.isEmpty ? name : !draft.caption.isEmpty ? draft.caption : "Sticker \(stickers.count + 1)"
            record.caption = draft.caption
            record.collection = draft.collection
            record.scale = draft.scale
            record.rotation = draft.rotation
            record.renderedFile = renderedFile
            record.appearance = draft.appearance
            if let cutout = draft.cutout { record.cutoutFile = try repository.store(cutout) }
            record.animatedFile = nil
            if draft.appearance.motion != nil && draft.appearance.resolvedOutput == .gif {
                guard let gif = StickerImageService.gifData(frames: draft.renderedFrames(), framesPerSecond: draft.appearance.animation.safeFPS) else { throw CocoaError(.fileWriteUnknown) }
                record.animatedFile = try repository.store(gif, extension: "gif")
            }
            var updated = stickers.filter { $0.id != record.id }
            updated.append(record)
            if commit(updated) {
                if draft.existing == nil { newStickerIDs.insert(record.id) }
                editor = nil
                search = ""; filter = .all; collection = nil
                repository.removeUnreferencedImages(keeping: stickers)
                showToast("Sticker saved")
            } else { repository.removeUnreferencedImages(keeping: stickers) }
        } catch {
            repository.removeUnreferencedImages(keeping: stickers)
            errorMessage = "This sticker couldn’t be saved. Please try again."
        }
    }
    private func showToast(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
