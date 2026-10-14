import SwiftUI

@MainActor @Observable
final class StickerEditorViewModel: Identifiable {
    let id = UUID()
    let existing: Sticker?
    let source: UIImage
    private(set) var cutout: UIImage?
    private(set) var isExtracting = false
    private(set) var cutoutMessage: String?
    private(set) var didAttemptCutout = false
    private let subjectService: any SubjectCutting
    private let initialCutout: UIImage?
    private var undoStates: [EditState] = []
    private var redoStates: [EditState] = []
    @ObservationIgnored private var lastEditKey: String?
    @ObservationIgnored private var lastEditAt = Date.distantPast
    @ObservationIgnored private var previewKey: EditState?
    @ObservationIgnored private var previewSource: UIImage?
    @ObservationIgnored private var preparedPreview: UIImage?
    var name: String
    var caption: String
    var collection: StickerCollection
    var scale: Double
    var rotation: Double
    var appearance: StickerAppearance

    init(source: UIImage, existing: Sticker? = nil, cutout: UIImage? = nil,
         subjectService: (any SubjectCutting)? = nil) {
        self.source = source
        self.existing = existing
        self.cutout = cutout
        initialCutout = cutout
        self.subjectService = subjectService ?? AppleSubjectCutoutService()
        name = existing?.name ?? ""
        caption = existing?.caption ?? ""
        collection = existing?.collection ?? .things
        scale = existing?.scale ?? 1
        rotation = existing?.rotation ?? 0
        appearance = existing == nil ? StickerAppearance() : (existing?.appearance ?? .legacy)
    }

    var canSave: Bool {
        // An empty name is filled in on save from the caption or a running number.
        !isExtracting && (!appearance.removesBackground || cutout != nil)
    }
    var hasChanges: Bool {
        existing == nil || name != existing?.name || caption != existing?.caption ||
        collection != existing?.collection || scale != existing?.scale || rotation != existing?.rotation ||
        appearance != (existing?.appearance ?? .legacy) || cutout !== initialCutout
    }
    func prepareCutout() async {
        guard appearance.removesBackground, cutout == nil, !didAttemptCutout else { return }
        await extractSubject()
    }
    func extractSubject() async {
        guard !isExtracting else { return }
        isExtracting = true
        didAttemptCutout = true
        cutoutMessage = nil
        defer { isExtracting = false }
        do {
            let result = try await subjectService.cutout(from: source)
            try Task.checkCancellation()
            cutout = result
            appearance.removesBackground = true
        } catch is CancellationError {
            didAttemptCutout = false
        } catch {
            appearance.removesBackground = false
            cutoutMessage = error.localizedDescription
        }
    }
    private var subject: UIImage { appearance.removesBackground ? (cutout ?? source) : source }
    struct EditState: Equatable {
        var caption: String
        var scale: Double
        var rotation: Double
        var appearance: StickerAppearance
    }
    private var editState: EditState { EditState(caption: caption, scale: scale, rotation: rotation, appearance: appearance) }
    var canUndo: Bool { !undoStates.isEmpty }
    var canRedo: Bool { !redoStates.isEmpty }
    func change(_ key: String, _ update: () -> Void) {
        let previous = editState
        update()
        guard previous != editState else { return }
        let now = Date()
        if key != lastEditKey || now.timeIntervalSince(lastEditAt) > 0.65 {
            undoStates.append(previous)
            if undoStates.count > 50 { undoStates.removeFirst() }
        }
        lastEditAt = now; lastEditKey = key
        redoStates.removeAll()
    }
    private func apply(_ state: EditState) {
        caption = state.caption; scale = state.scale; rotation = state.rotation; appearance = state.appearance
        lastEditKey = nil
    }
    func undo() {
        guard let previous = undoStates.popLast() else { return }
        redoStates.append(editState); apply(previous)
    }
    func redo() {
        guard let next = redoStates.popLast() else { return }
        undoStates.append(editState); apply(next)
    }
    func selectMotion(_ motion: StickerMotion?) {
        change("motion") {
            appearance.motion = motion
            appearance.output = motion == nil ? .png : .gif
        }
    }
    func renderedImage(phase: Double? = nil) -> UIImage {
        let state = editState
        if previewKey != state || previewSource !== subject || preparedPreview == nil {
            preparedPreview = StickerImageService.outlinedSubject(source: subject, scale: scale, rotation: rotation, appearance: appearance)
            previewKey = state; previewSource = subject
        }
        return StickerImageService.compose(preparedPreview!, caption: caption, appearance: appearance, phase: phase)
    }
    func renderedFrames() -> [UIImage] {
        StickerImageService.renderFrames(source: subject, caption: caption, scale: scale, rotation: rotation, appearance: appearance)
    }
}
