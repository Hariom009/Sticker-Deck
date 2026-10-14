import SwiftUI

@main
struct Sticker_DeckApp: App {
    @State private var library: StickerLibraryViewModel

    init() {
        let repository: LocalStickerRepository
        #if DEBUG
        let isDemo = ProcessInfo.processInfo.arguments.contains("-demo-library") || ProcessInfo.processInfo.arguments.contains("-demo-editor")
        #else
        let isDemo = false
        #endif
        if isDemo {
            repository = LocalStickerRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent("StickerDeckDemo"))
            if (try? repository.load().isEmpty) == true {
                let samples: [(String, String, StickerCollection)] = [
                    ("😎", "Cool", .reactions), ("🤍", "Love", .reactions), ("🐈", "Cat", .animals),
                    ("☕️", "Coffee", .things), ("👀", "Looking", .reactions), ("🦦", "Otter", .animals),
                    ("🥐", "Croissant", .things), ("🫠", "Melting", .reactions), ("🐕", "Good boy", .animals),
                    ("🎧", "Headphones", .things), ("😭", "Crying", .reactions), ("🐥", "Chick", .animals),
                    ("🍒", "Cherries", .things), ("🥳", "Celebrate", .reactions), ("🦋", "Butterfly", .animals),
                    ("🌷", "Tulip", .things), ("🤌", "Perfect", .reactions), ("🧸", "Teddy", .things)
                ]
                do {
                    let records = try samples.enumerated().map { index, sample in
                        let image = StickerImageService.sample(sample.0)
                        let file = try repository.store(image)
                        return Sticker(name: sample.1, collection: sample.2, sourceFile: file, renderedFile: file,
                                       isFavorite: index % 4 == 0, createdAt: Date().addingTimeInterval(Double(-index)))
                    }
                    try repository.save(records)
                } catch { /* Demo setup cannot affect the production repository. */ }
            }
        } else { repository = LocalStickerRepository() }
        let model = StickerLibraryViewModel(repository: repository)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demo-editor") {
            let sample = StickerImageService.sample("🐼")
            model.editor = StickerEditorViewModel(source: sample, cutout: sample)
        }
        #endif
        _library = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup { ContentView(model: library) }
    }
}
