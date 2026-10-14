import SwiftUI

struct StickerImage: View {
    let image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo.badge.exclamationmark").font(.largeTitle).foregroundStyle(.secondary) }
        }
        .accessibilityHidden(true)
    }
}

struct StickerTile: View {
    let sticker: Sticker
    let image: UIImage?
    var isNew = false
    /// nil outside selection mode.
    var isSelected: Bool? = nil
    /// Copies, or toggles selection while selecting.
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onPreview: () -> Void

    private var traits: AccessibilityTraits { isSelected == true ? [.isButton, .isSelected] : .isButton }
    private var label: String {
        if isSelected != nil { return sticker.name }
        return isNew ? "Copy \(sticker.name), new" : "Copy \(sticker.name)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // ponytail: tap + long-press modifiers instead of a Button, so a long hold never also fires the tap.
            StickerImage(image: image)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(3)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .onLongPressGesture(perform: onLongPress)
                .overlay(alignment: .topTrailing) {
                    if isNew {
                        Text("NEW").font(.system(size: 9, weight: .heavy)).tracking(0.4)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .foregroundStyle(DeckTheme.background)
                            .background(DeckTheme.ink, in: Capsule())
                            .padding(4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: isNew)
                .accessibilityElement()
                .accessibilityAddTraits(traits)
                .accessibilityLabel(label)
                .accessibilityHint(isSelected != nil ? "Selects or deselects the sticker" : "Copies the sticker image to the clipboard")
                .accessibilityAction(.default, onTap)
                .accessibilityAction(named: isSelected == true ? "Deselect" : "Select", onLongPress)
            HStack {
                if sticker.isFavorite {
                    Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                        .accessibilityLabel("Favorite")
                }
                if sticker.animatedFile != nil {
                    Image(systemName: "sparkles").font(.system(size: 10)).foregroundStyle(.secondary)
                        .accessibilityLabel("Animated")
                }
                Spacer(minLength: 0)
                if let isSelected {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isSelected ? DeckTheme.ink : DeckTheme.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onTap)
                        .accessibilityHidden(true)
                } else {
                    Button(action: onPreview) {
                        Image(systemName: "ellipsis").font(.system(size: 16, weight: .medium))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preview and edit \(sticker.name)")
                }
            }
            .padding(.leading, 10)
        }
        .background(isSelected == true ? DeckTheme.surface : .clear, in: RoundedRectangle(cornerRadius: 14))
    }
}
