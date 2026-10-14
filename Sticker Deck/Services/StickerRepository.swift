import UIKit

@MainActor
protocol StickerRepository {
    func load() throws -> [Sticker]
    func save(_ stickers: [Sticker]) throws
    func image(named: String) -> UIImage?
    func store(_ image: UIImage) throws -> String
    func store(_ data: Data, extension: String) throws -> String
    func data(named: String) -> Data?
    func removeUnreferencedImages(keeping stickers: [Sticker])
}

extension StickerRepository {
    func store(_ data: Data, extension: String) throws -> String { throw CocoaError(.fileWriteUnknown) }
    func data(named: String) -> Data? { nil }
}

@MainActor
final class LocalStickerRepository: StickerRepository {
    private let directory: URL
    private let cache = NSCache<NSString, UIImage>()
    private var images: URL { directory.appendingPathComponent("images", isDirectory: true) }
    private var metadata: URL { directory.appendingPathComponent("library.json") }

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appendingPathComponent("StickerDeck", isDirectory: true)
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func load() throws -> [Sticker] {
        guard FileManager.default.fileExists(atPath: metadata.path) else { return [] }
        return try JSONDecoder().decode([Sticker].self, from: Data(contentsOf: metadata))
    }

    func save(_ stickers: [Sticker]) throws {
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(stickers)
        try data.write(to: metadata, options: .atomic)
    }

    func image(named name: String) -> UIImage? {
        guard name == URL(fileURLWithPath: name).lastPathComponent else { return nil }
        if let image = cache.object(forKey: name as NSString) { return image }
        guard let image = UIImage(contentsOfFile: images.appendingPathComponent(name).path) else { return nil }
        cache.setObject(image, forKey: name as NSString, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        return image
    }

    func store(_ image: UIImage) throws -> String {
        guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        return try store(data, extension: "png")
    }

    func store(_ data: Data, extension: String) throws -> String {
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let name = UUID().uuidString + "." + `extension`
        try data.write(to: images.appendingPathComponent(name), options: .atomic)
        return name
    }

    func data(named name: String) -> Data? {
        guard name == URL(fileURLWithPath: name).lastPathComponent else { return nil }
        return try? Data(contentsOf: images.appendingPathComponent(name))
    }

    func removeUnreferencedImages(keeping stickers: [Sticker]) {
        let retained = Set(stickers.flatMap { [$0.sourceFile, $0.renderedFile] + [$0.cutoutFile, $0.animatedFile].compactMap { $0 } })
        guard let files = try? FileManager.default.contentsOfDirectory(at: images, includingPropertiesForKeys: nil) else { return }
        for file in files where ["png", "gif"].contains(file.pathExtension) && !retained.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
            cache.removeObject(forKey: file.lastPathComponent as NSString)
        }
    }
}
