import SwiftUI

struct StickerEditorControls: View {
    @Bindable var model: StickerEditorViewModel
    let tool: StickerEditorTool
    let onRetryCutout: () -> Void
    @State private var showingClipInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(tool == .subject ? "Your subject" : tool.rawValue).font(.subheadline.weight(.semibold))
                Spacer()
                if tool != .subject {
                    Button(tool == .text ? "Remove" : "Reset") { reset() }
                        .font(.caption).foregroundStyle(.secondary).frame(minHeight: 30)
                }
            }
            switch tool {
            case .subject: subject
            case .outline: outline
            case .text: text
            case .motion: motion
            }
        }
        .alert("Clip / Live Photo", isPresented: $showingClipInfo) {
            Button("OK", role: .cancel) {}
        } message: { Text("Video and Live Photo processing is coming next. You can animate a photo sticker with the presets below.") }
    }

    private func binding<Value>(_ key: String, get: @escaping () -> Value, set: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(get: get, set: { value in model.change(key) { set(value) } })
    }
    private func appearanceBinding<Value>(_ key: String, _ path: WritableKeyPath<StickerAppearance, Value>) -> Binding<Value> {
        binding(key, get: { model.appearance[keyPath: path] }, set: { model.appearance[keyPath: path] = $0 })
    }

    private var subject: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Image", selection: appearanceBinding("subject", \.removesBackground)) {
                Text("Subject only").tag(true).disabled(model.cutout == nil)
                Text("Original photo").tag(false)
            }
            .pickerStyle(.segmented).disabled(model.isExtracting)
            if let message = model.cutoutMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(model.cutout != nil ? "Background removed. You can switch back anytime." : "We’ll lift the subject from your photo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.cutout == nil {
                Button(action: onRetryCutout) {
                    Label(model.isExtracting ? "Finding subject…" : "Retry cutout", systemImage: "arrow.clockwise")
                        .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                        .background(DeckTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                }.disabled(model.isExtracting)
            }
            // ponytail: size and tilt are pinch/twist on the canvas; flip has no gesture, so it lives here.
            chip("Flip", symbol: "arrow.left.and.right", selected: model.appearance.flipped) {
                model.change("flip") { model.appearance.flipped.toggle() }
            }
        }
    }

    private var outline: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(Array(zip(["None", "Thin", "Medium", "Thick"], [0.0, 4, 8, 14])), id: \.0) { title, width in
                    chip(title, selected: model.appearance.outlineWidth == width) {
                        model.change("outlineWidth") { model.appearance.outlineWidth = width }
                    }
                }
            }
            slider("Thickness", value: appearanceBinding("outlineWidth", \.outlineWidth), range: 0...20,
                   displayed: model.appearance.outlineWidth == 0 ? "None" : "\(Int(model.appearance.outlineWidth))", step: 1)
            colorRow("Color", ink: \.outlineColor, hex: \.outlineHex)
                .disabled(model.appearance.outlineWidth == 0)
            Toggle("Soft shadow", isOn: appearanceBinding("shadow", \.shadow)).font(.subheadline)
        }
    }

    private var text: some View {
        VStack(spacing: 12) {
            TextField("Say something…", text: binding("caption", get: { model.caption }, set: { model.caption = String($0.prefix(40)) }))
                .padding(12).background(DeckTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Sticker caption")
            HStack {
                Picker("Font", selection: appearanceBinding("captionFont", \.captionFont)) {
                    ForEach(CaptionFont.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().accessibilityLabel("Caption font")
                Spacer()
                colorRow("", ink: \.captionColor, hex: \.captionHex)
            }
            slider("Text size", value: appearanceBinding("captionSize", \.captionSize), range: 18...64,
                   displayed: "\(Int(model.appearance.captionSize))", step: 1)
            HStack(spacing: 8) {
                positionChip("Top", y: 0.2)
                positionChip("Center", y: 0.5)
                positionChip("Bottom", y: 0.8)
            }
        }
    }

    private var motion: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                chip("Animate sticker", selected: true) {}
                chip("Clip / Live Photo", selected: false) { showingClipInfo = true }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                motionChip("Still", nil, "photo")
                motionChip("Bounce", .bounce, "arrow.up.and.down")
                motionChip("Wiggle", .wobble, "arrow.left.and.right")
                motionChip("Pulse", .pulse, "arrow.up.left.and.arrow.down.right")
                motionChip("Spin", .spin, "rotate.right")
                motionChip("Float", .float, "wind")
                motionChip("Pop", .pop, "circle")
                motionChip("Shake", .shake, "waveform")
                motionChip("Glitter", .glitter, "sparkles")
            }
            if model.appearance.motion != nil {
                HStack {
                    labeledMenu("Length") {
                        Picker("Length", selection: animationBinding("duration", get: { $0.duration }, set: { $0.duration = $1 })) {
                            ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { Text("\($0.formatted())s\($0 == 2 ? " · max" : "")").tag($0) }
                        }.labelsHidden()
                    }
                    Spacer()
                    labeledMenu("Playback") {
                        Picker("Playback", selection: animationBinding("playback", get: { $0.playback }, set: { $0.playback = $1 })) {
                            ForEach(StickerPlayback.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden()
                    }
                }
                HStack {
                    Text("Quality").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    chip("15 FPS", selected: model.appearance.animation.safeFPS == 15) { setFPS(15) }
                    chip("20 FPS", selected: model.appearance.animation.safeFPS == 20) { setFPS(20) }
                }
            }
        }
    }

    private func labeledMenu<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(label).font(.caption2).foregroundStyle(.secondary); content() }
    }
    private func animationBinding<Value>(_ key: String, get: @escaping (StickerAnimationSettings) -> Value,
                                         set: @escaping (inout StickerAnimationSettings, Value) -> Void) -> Binding<Value> {
        binding(key, get: { get(model.appearance.animation) }, set: { value in
            var settings = model.appearance.animation; set(&settings, value); model.appearance.animationSettings = settings
        })
    }
    private func setFPS(_ fps: Int) {
        model.change("fps") { var settings = model.appearance.animation; settings.framesPerSecond = fps; model.appearance.animationSettings = settings }
    }
    private func motionChip(_ title: String, _ motion: StickerMotion?, _ symbol: String) -> some View {
        Button { model.selectMotion(motion) } label: {
            VStack(spacing: 6) { Image(systemName: symbol).font(.body); Text(title).font(.caption2) }
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(model.appearance.motion == motion ? DeckTheme.background : DeckTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.appearance.motion == motion ? DeckTheme.ink : Color.clear, lineWidth: 1))
        }
        .accessibilityAddTraits(model.appearance.motion == motion ? .isSelected : [])
    }
    private func chip(_ title: String, symbol: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol) }
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.caption).frame(maxWidth: .infinity, minHeight: 40)
            .foregroundStyle(selected ? DeckTheme.background : DeckTheme.ink)
            .background(selected ? DeckTheme.ink : DeckTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        }.accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, displayed: String, step: Double) -> some View {
        VStack(spacing: 2) {
            HStack { Text(title); Spacer(); Text(displayed).monospacedDigit() }.font(.caption).foregroundStyle(.secondary)
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }
    }
    private func positionChip(_ title: String, y: Double) -> some View {
        let selected = model.appearance.captionPosition.map { abs($0.y - y) < 0.02 } ?? ((title == "Bottom" && model.appearance.captionPlacement == .bottom) || (title == "Top" && model.appearance.captionPlacement == .top))
        return chip(title, selected: selected) {
            model.change("captionPosition") { model.appearance.captionPosition = CaptionPosition(x: 0.5, y: y) }
        }
    }
    private func colorRow(_ title: String, ink: WritableKeyPath<StickerAppearance, StickerInk>, hex: WritableKeyPath<StickerAppearance, String?>) -> some View {
        HStack(spacing: 8) {
            if !title.isEmpty { Text(title).font(.caption).foregroundStyle(.secondary); Spacer() }
            ForEach(StickerInk.allCases) { color in
                Button {
                    model.change("color") { model.appearance[keyPath: ink] = color; model.appearance[keyPath: hex] = nil }
                } label: {
                    Circle().fill(Color(uiColor: StickerImageService.color(color))).frame(width: 27, height: 27)
                        .overlay(Circle().stroke(DeckTheme.secondary.opacity(0.4), lineWidth: 1))
                        .padding(4)
                        .overlay(Circle().stroke(model.appearance[keyPath: ink] == color && model.appearance[keyPath: hex] == nil ? DeckTheme.ink : Color.clear, lineWidth: 1.5))
                }.accessibilityLabel("\(color.rawValue) \(title.isEmpty ? "text" : "outline")")
            }
            ColorPicker("Custom color", selection: binding("customColor", get: {
                Color(uiColor: StickerImageService.color(model.appearance[keyPath: ink], hex: model.appearance[keyPath: hex]))
            }, set: { model.appearance[keyPath: hex] = StickerImageService.hex(UIColor($0)) }), supportsOpacity: false)
                .labelsHidden().frame(width: 32).accessibilityLabel("Custom \(title.isEmpty ? "text" : "outline") color")
        }
    }
    private func reset() {
        model.change("reset") {
            switch tool {
            case .subject: break
            case .outline: model.appearance.outlineWidth = 8; model.appearance.outlineColor = .white; model.appearance.outlineHex = nil; model.appearance.shadow = false
            case .text: model.caption = ""
            case .motion: model.appearance.motion = nil; model.appearance.animationSettings = nil; model.appearance.output = .png
            }
        }
    }
}
