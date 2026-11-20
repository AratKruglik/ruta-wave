import SwiftUI

struct HomeScreen: View {
    @Environment(BrowseStore.self) private var store

    var body: some View {
        BrowseScreen(model: store.home)
    }
}
