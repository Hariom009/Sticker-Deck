import Foundation

enum StickerCollection: String, Codable, CaseIterable, Identifiable {
    case reactions = "Reactions", words = "Words", animals = "Animals", things = "Things"
    var id: String { rawValue }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All", favorites = "Favorites", recent = "Recent"
    var id: String { rawValue }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case newest = "Newest first", name = "Name A–Z"
    var id: String { rawValue }
}

struct Sticker: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var collection: StickerCollection = .things
    var sourceFile: String
    var renderedFile: String
    var caption = ""
    var scale: Double = 1
    var rotation: Double = 0
    var isFavorite = false
    var createdAt = Date()
    var lastCopiedAt: Date?
    var cutoutFile: String?
    var appearance: StickerAppearance?
    var animatedFile: String?
}

enum LibraryQuery {
    static func results(_ stickers: [Sticker], search: String, filter: LibraryFilter,
                        collection: StickerCollection?, sort: LibrarySort) -> [Sticker] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return stickers.filter { sticker in
            (filter != .favorites || sticker.isFavorite) &&
            (filter != .recent || sticker.lastCopiedAt != nil) &&
            (collection == nil || sticker.collection == collection) &&
            (term.isEmpty || [sticker.name, sticker.caption, sticker.collection.rawValue]
                .contains { $0.localizedStandardContains(term) })
        }.sorted { lhs, rhs in
            if filter == .recent, lhs.lastCopiedAt != rhs.lastCopiedAt {
                return (lhs.lastCopiedAt ?? .distantPast) > (rhs.lastCopiedAt ?? .distantPast)
            }
            if sort == .name, lhs.name != rhs.name {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
