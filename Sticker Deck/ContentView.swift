import SwiftUI

struct ContentView: View {
    let model: StickerLibraryViewModel
    var body: some View {
        StickerLibraryView(model: model)
    }
}
