import SwiftUI

/// Review state for splitting one sticker sheet into separate stickers.
@MainActor @Observable
final class StickerSheetViewModel: Identifiable {
    let id = UUID()
    let source: UIImage
    private(set) var pieces: [UIImage] = []
    private(set) var didDetect = false
    /// Pieces cut from an opaque sheet lose the creator's white border to the background, so they get the default outline.
    private(set) var needsOutline = false
    var selected: Set<Int> = []
    private let subjectService: any SubjectCutting

    init(source: UIImage, subjectService: any SubjectCutting) {
        self.source = source
        self.subjectService = subjectService
    }

    var chosen: [UIImage] { selected.sorted().map { pieces[$0] } }
    var allSelected: Bool { selected.count == pieces.count }

    func toggle(_ index: Int) {
        if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
    }
    func toggleAll() { selected = allSelected ? [] : Set(pieces.indices) }

    /// Transparent sheets split on their own alpha. Opaque sheets try both the Vision cutout and plain-background
    /// keying and keep whichever finds more stickers (Vision wins ties: it keeps white borders on white sheets).
    func detect() async {
        guard !didDetect else { return }
        let source = self.source
        var found: [UIImage]
        if await Task.detached(priority: .userInitiated, operation: { StickerImageService.hasTransparency(source) }).value {
            found = await Task.detached(priority: .userInitiated) { StickerSheetSplitter.split(source) }.value
        } else {
            needsOutline = true
            found = []
            if let cutout = try? await subjectService.cutout(from: source) {
                found = await Task.detached(priority: .userInitiated) { StickerSheetSplitter.split(cutout) }.value
            }
            let keyed = await Task.detached(priority: .userInitiated) {
                StickerSheetSplitter.keyedBackground(source).map { StickerSheetSplitter.split($0) } ?? []
            }.value
            if keyed.count > found.count { found = keyed }
        }
        guard !Task.isCancelled else { return }
        pieces = found
        selected = Set(found.indices)
        didDetect = true
    }
}
