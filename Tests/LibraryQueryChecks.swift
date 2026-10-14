import Foundation

@main
struct LibraryQueryChecks {
    static func main() throws {
        let old = Date(timeIntervalSince1970: 100)
        let new = Date(timeIntervalSince1970: 200)
        let a = Sticker(name: "Café", collection: .things, sourceFile: "a.png", renderedFile: "b.png", caption: "Morning", isFavorite: true, createdAt: old, lastCopiedAt: new)
        let b = Sticker(name: "Cat", collection: .animals, sourceFile: "c.png", renderedFile: "d.png", createdAt: new, lastCopiedAt: old)
        let c = Sticker(name: "Hello", collection: .words, sourceFile: "e.png", renderedFile: "f.png", createdAt: new)
        let all = [a, b, c]
        func query(_ search: String = "", _ filter: LibraryFilter = .all, _ collection: StickerCollection? = nil, _ sort: LibrarySort = .newest) -> [Sticker] {
            LibraryQuery.results(all, search: search, filter: filter, collection: collection, sort: sort)
        }
        assert(query("  morning ").map(\.id) == [a.id])
        assert(query("cafe").map(\.id) == [a.id])
        assert(query("animals").map(\.id) == [b.id])
        assert(query("", .favorites).map(\.id) == [a.id])
        assert(query("", .favorites, .animals).isEmpty)
        assert(query("", .recent).map(\.id) == [a.id, b.id])
        assert(query("", .all, nil, .name).map(\.id) == [a.id, b.id, c.id])
        assert(query("", .all).last?.id == a.id)
        assert(query("missing").isEmpty)
        let decoded = try JSONDecoder().decode([Sticker].self, from: JSONEncoder().encode(all))
        assert(decoded == all)
        print("Passed: search, normalization, collections, favorites, recent order, name/date sorting, empty results, metadata round trip.")
    }
}
