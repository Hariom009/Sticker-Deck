import SwiftUI

/// Shows every sticker found on a sheet; all start selected. Tap to leave one out, then add the rest in one go.
struct StickerSheetReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var review: StickerSheetViewModel
    let onAdd: ([UIImage]) -> Void
    @ScaledMetric private var tileSize: CGFloat = 96

    private var title: String {
        guard review.didDetect else { return "Sticker sheet" }
        return review.pieces.count == 1 ? "1 sticker found" : "\(review.pieces.count) stickers found"
    }

    var body: some View {
        NavigationStack {
            Group {
                if !review.didDetect {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Finding stickers…").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if review.pieces.isEmpty {
                    ContentUnavailableView("No stickers found", systemImage: "square.dashed",
                                           description: Text("Try a sheet with some space between stickers, or use New sticker to add the whole image."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: tileSize), spacing: 10)], spacing: 10) {
                            ForEach(review.pieces.indices, id: \.self) { piece($0) }
                        }
                        .padding(16)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if review.didDetect && !review.pieces.isEmpty {
                    Button { onAdd(review.chosen) } label: {
                        Text(review.selected.count == 1 ? "Add 1 sticker" : "Add \(review.selected.count) stickers")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity).frame(minHeight: 52)
                            .foregroundStyle(DeckTheme.background)
                            .background(DeckTheme.ink, in: Capsule())
                    }
                    .disabled(review.selected.isEmpty)
                    .opacity(review.selected.isEmpty ? 0.4 : 1)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(DeckTheme.background)
                }
            }
            .background(DeckTheme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DeckTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                if review.didDetect && review.pieces.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(review.allSelected ? "Select none" : "Select all") { review.toggleAll() }
                    }
                }
            }
            .task { await review.detect() }
        }
        .tint(DeckTheme.accent)
    }

    private func piece(_ index: Int) -> some View {
        let isSelected = review.selected.contains(index)
        return Button { review.toggle(index) } label: {
            ZStack {
                EditorCheckerboard()
                Image(uiImage: review.pieces[index]).resizable().scaledToFit().padding(10)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? DeckTheme.ink : Color.clear, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? DeckTheme.ink : DeckTheme.secondary)
                    .background(Circle().fill(DeckTheme.background).padding(2))
                    .padding(6)
            }
            .opacity(isSelected ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sticker \(index + 1)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Double tap to leave it out" : "Double tap to include it")
    }
}
