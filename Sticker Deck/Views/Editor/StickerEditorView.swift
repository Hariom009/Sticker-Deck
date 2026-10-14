import SwiftUI

enum StickerEditorTool: String, CaseIterable, Identifiable {
    case subject = "Subject", outline = "Outline", text = "Text", motion = "Motion"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .subject: "viewfinder"
        case .outline: "square.3.layers.3d"
        case .text: "textformat"
        case .motion: "film"
        }
    }
}

/// One canvas, four contextual tools. Creating and editing use the same screen.
struct StickerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: StickerEditorViewModel
    @Bindable var library: StickerLibraryViewModel
    @State private var tool: StickerEditorTool = .outline
    @State private var discardChanges = false
    @State private var showingSave = false
    @State private var cutoutAttempt = 0
    @State private var playing = false
    @State private var playbackStart = Date()
    @State private var captionDragBase: CGPoint?
    private enum PinchTarget { case subject(Double), caption(Double) }
    @State private var pinchTarget: PinchTarget?
    @State private var rotationBase: Double?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    header
                    canvas
                        .frame(height: max(150, min(340, geometry.size.height * 0.43)))
                        .padding(.horizontal, 16).padding(.bottom, 12)
                    tools
                    ScrollView {
                        StickerEditorControls(model: model, tool: tool) { cutoutAttempt += 1 }
                            .padding(.horizontal, 20).padding(.vertical, 16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: 560).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(DeckTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task(id: cutoutAttempt) {
                if cutoutAttempt == 0 { await model.prepareCutout() }
                else { await model.extractSubject() }
            }
            .onChange(of: model.appearance.motion) { _, motion in
                playing = motion != nil && !reduceMotion
                playbackStart = Date()
            }
            .onChange(of: reduceMotion) { _, reduced in if reduced { playing = false } }
            .confirmationDialog("Discard this sticker?", isPresented: $discardChanges, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
            } message: { Text("Your unsaved changes will be lost.") }
            .sheet(isPresented: $showingSave) {
                StickerSaveView(model: model, library: library)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(DeckTheme.background)
                    .presentationBackgroundInteraction(.disabled)
            }
            .alert("Couldn’t save sticker", isPresented: Binding(
                get: { library.errorMessage != nil && !showingSave },
                set: { if !$0 { library.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { library.errorMessage = nil }
            } message: { Text(library.errorMessage ?? "") }
        }
        .background(DeckTheme.background.ignoresSafeArea())
        .tint(DeckTheme.accent)
    }

    private var header: some View {
        HStack {
            Button("Cancel") {
                if model.hasChanges { discardChanges = true } else { dismiss() }
            }
            .foregroundStyle(.secondary).frame(minWidth: 65, minHeight: 44)
            Spacer(minLength: 8)
            Text(model.existing == nil ? "New sticker" : "Edit sticker").font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Button("Save") { playing = false; showingSave = true }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18).frame(minHeight: 38)
                .foregroundStyle(DeckTheme.background).background(DeckTheme.ink, in: Capsule())
                .disabled(!model.canSave)
                .opacity(model.canSave ? 1 : 0.4)
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
    }

    private var canvas: some View {
        GeometryReader { geometry in
            ZStack {
                EditorCheckerboard()
                TimelineView(.animation(minimumInterval: 1 / Double(model.appearance.animation.safeFPS), paused: !playing)) { timeline in
                    let elapsed = max(0, timeline.date.timeIntervalSince(playbackStart))
                    let phase = playing && model.appearance.motion != nil ? elapsed / model.appearance.animation.safeDuration : nil
                    StickerImage(image: model.renderedImage(phase: phase))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(10)
                        .contentShape(Rectangle())
                        .gesture(captionDrag(in: geometry.size))
                        .simultaneousGesture(MagnifyGesture().onChanged { value in
                            if pinchTarget == nil {
                                let hitsText = captionHit(in: geometry.size)?.contains(value.startLocation) == true
                                pinchTarget = hitsText ? .caption(model.appearance.captionSize) : .subject(model.scale)
                            }
                            switch pinchTarget {
                            case .subject(let base):
                                model.change("scale") { model.scale = min(1.2, max(0.6, base * value.magnification)) }
                            case .caption(let base):
                                model.change("captionSize") { model.appearance.captionSize = min(64, max(18, base * value.magnification)) }
                            case nil: break
                            }
                        }.onEnded { _ in pinchTarget = nil })
                        .simultaneousGesture(RotateGesture().onChanged { value in
                            let base = rotationBase ?? model.rotation
                            rotationBase = base
                            model.change("rotation") { model.rotation = (base + value.rotation.degrees).truncatingRemainder(dividingBy: 360) }
                        }.onEnded { _ in rotationBase = nil })
                        .simultaneousGesture(SpatialTapGesture().onEnded { value in
                            if captionHit(in: geometry.size)?.contains(value.location) == true { tool = .text }
                        })
                }
                if model.isExtracting {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Lifting subject…").font(.subheadline)
                    }
                    .padding(20).background(DeckTheme.background, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .topLeading) {
                Label(model.appearance.motion == nil ? "Still sticker" : "\(model.appearance.animation.safeDuration.formatted())s loop · \(model.appearance.animation.safeFPS) FPS", systemImage: "viewfinder")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(DeckTheme.background, in: RoundedRectangle(cornerRadius: 8))
                    .padding(12)
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 4) {
                    canvasButton("Undo", "arrow.uturn.backward", disabled: !model.canUndo) { model.undo() }
                    canvasButton("Redo", "arrow.uturn.forward", disabled: !model.canRedo) { model.redo() }
                    if model.appearance.motion != nil {
                        canvasButton(playing ? "Pause animation" : "Play animation", playing ? "pause.fill" : "play.fill") {
                            playbackStart = Date(); playing.toggle()
                        }
                    }
                }
                .padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                if tool == .text && !model.caption.isEmpty {
                    Text("Drag text to position").font(.caption2).foregroundStyle(.secondary)
                        .padding(12).allowsHitTesting(false)
                }
            }
        }
        .accessibilityLabel("Live sticker preview")
    }

    private func canvasButton(_ title: String, _ symbol: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.caption).frame(width: 36, height: 36)
                .background(DeckTheme.background, in: Circle())
        }
        .accessibilityLabel(title).disabled(disabled)
    }

    private var tools: some View {
        HStack(spacing: 3) {
            ForEach(StickerEditorTool.allCases) { item in
                Button { tool = item } label: {
                    VStack(spacing: 6) {
                        Image(systemName: item.symbol).font(.system(size: 20))
                        Text(item.rawValue).font(.caption2)
                    }
                    .frame(maxWidth: .infinity).frame(minHeight: 64)
                    .foregroundStyle(tool == item ? DeckTheme.ink : DeckTheme.secondary)
                    .background(tool == item ? DeckTheme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityAddTraits(tool == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 10)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func captionHit(in size: CGSize) -> CGRect? {
        let side = min(size.width - 20, size.height - 20)
        guard side > 0, let layout = StickerImageService.captionLayout(model.caption, appearance: model.appearance) else { return nil }
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        return CGRect(x: origin.x + layout.rect.minX * side / 512, y: origin.y + layout.rect.minY * side / 512,
                      width: layout.rect.width * side / 512, height: layout.rect.height * side / 512).insetBy(dx: -20, dy: -20)
    }

    private func captionDrag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4).onChanged { value in
            let side = min(size.width - 20, size.height - 20)
            guard side > 0 else { return }
            if captionDragBase == nil {
                guard captionHit(in: size)?.contains(value.startLocation) == true else { return }
                tool = .text
                let center = StickerImageService.captionCenter(model.appearance)
                captionDragBase = CGPoint(x: center.x / 512, y: center.y / 512)
            }
            guard let base = captionDragBase else { return }
            model.change("captionPosition") {
                model.appearance.captionPosition = CaptionPosition(x: min(0.96, max(0.04, base.x + value.translation.width / side)),
                                                                   y: min(0.96, max(0.04, base.y + value.translation.height / side)))
            }
        }.onEnded { _ in captionDragBase = nil }
    }
}

struct EditorCheckerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 12
            for row in 0...Int(size.height / cell) {
                for column in 0...Int(size.width / cell) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                 with: .color(.primary.opacity(0.025)))
                }
            }
        }
        .background(DeckTheme.surface).accessibilityHidden(true)
    }
}
