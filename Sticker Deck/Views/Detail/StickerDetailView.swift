import SwiftUI

struct StickerDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: StickerLibraryViewModel
    let stickerID: UUID
    let onEdit: (Sticker) -> Void
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            if let sticker = model.sticker(id: stickerID) {
                ScrollView {
                    VStack(spacing: 12) {
                        Button { model.copy(sticker) } label: {
                            StickerImage(image: model.image(for: sticker))
                                .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                                .padding(24)
                                .background(DeckTheme.surface, in: RoundedRectangle(cornerRadius: 28))
                        }
                        .buttonStyle(.plain).accessibilityLabel("Copy \(sticker.name)")
                        Text(sticker.name).font(.title2.weight(.semibold))
                        Text(sticker.collection.rawValue).font(.subheadline).foregroundStyle(.secondary)
                        Text(model.toast ?? "Tap sticker to copy").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
                }
                .background(DeckTheme.background.ignoresSafeArea())
                .toolbarBackground(DeckTheme.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Copy", systemImage: "document.on.document") { model.copy(sticker) }
                        Button("Edit", systemImage: "pencil") { onEdit(sticker) }
                        Button(sticker.isFavorite ? "Remove favorite" : "Favorite", systemImage: sticker.isFavorite ? "heart.fill" : "heart") { model.toggleFavorite(sticker) }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    }
                }
                .confirmationDialog("Delete this sticker?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete sticker", role: .destructive) { if model.delete(sticker) { dismiss() } }
                } message: { Text("This removes it from your collection.") }
            }
        }
        .background(DeckTheme.background.ignoresSafeArea())
        .tint(DeckTheme.accent)
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}
