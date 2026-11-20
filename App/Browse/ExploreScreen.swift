import SwiftUI

struct ExploreScreen: View {
    @Environment(BrowseStore.self) private var store

    var body: some View {
        BrowseScreen(model: store.explore)
    }
}
