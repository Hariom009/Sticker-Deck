import SwiftUI

struct StickerSaveView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: StickerEditorViewModel
    @Bindable var library: StickerLibraryViewModel
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StickerImage(image: model.renderedImage()).frame(height: 130).frame(maxWidth: .infinity)
                        .background(DeckTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    field("Name") {
                        TextField("Name (optional)", text: $model.name).onChange(of: model.name) { _, value in
                            if value.count > 60 { model.name = String(value.prefix(60)) }
                        }
                    }
                    field("Collection") {
                        Picker("Collection", selection: $model.collection) {
                            ForEach(StickerCollection.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden()
                    }
                    field("Format") {
                        Picker("Format", selection: Binding(get: { model.appearance.resolvedOutput }, set: { model.appearance.output = $0 })) {
                            Text("Still PNG").tag(StickerOutput.png)
                            if model.appearance.motion != nil { Text("Animated GIF").tag(StickerOutput.gif) }
                        }.labelsHidden()
                    }
                    Text(model.appearance.resolvedOutput == .png ? "Transparent still image" : "\(model.appearance.animation.safeDuration.formatted()) \(model.appearance.animation.safeDuration == 1 ? "second" : "seconds") · \(model.appearance.animation.safeFPS) FPS · \(model.appearance.animation.frameCount) frames")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        saving = true
                        Task { @MainActor in
                            await Task.yield()
                            library.save(model)
                            saving = false
                        }
                    } label: {
                        HStack { if saving { ProgressView().tint(DeckTheme.background) }; Text(saving ? "Saving…" : "Save sticker") }
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(DeckTheme.background).background(DeckTheme.ink, in: Capsule())
                    }
                    .disabled(!model.canSave || saving)
                }
                .padding(20).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DeckTheme.background.ignoresSafeArea())
            .navigationTitle("Save your sticker").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly).disabled(saving) }
            }
            .alert("Couldn’t save sticker", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
                Button("OK", role: .cancel) { library.errorMessage = nil }
            } message: { Text(library.errorMessage ?? "") }
        }
        .interactiveDismissDisabled(saving)
        .tint(DeckTheme.accent)
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content().padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
                .background(DeckTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        }.disabled(saving)
    }
}
