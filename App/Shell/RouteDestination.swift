import SwiftUI

struct SectionRoot: View {
    let section: SidebarSection
    let isSignedIn: Bool
    @Environment(\.requestSignIn) private var requestSignIn
    @Environment(BrowseStore.self) private var store

    var body: some View {
        if section == .library, !isSignedIn {
            LibraryGuestView(onSignIn: requestSignIn.perform)
        } else {
            switch section {
            case .home: HomeScreen()
            case .explore: ExploreScreen()
            case .library: LibraryScreen(model: store.library).id(store.generation)
            }
        }
    }
}

struct RouteScreen: View {
    let route: Route

    @Environment(BrowseStore.self) private var store

    var body: some View {
        Group {
            if case .history = route {
                HistoryScreen(model: store.history)
            } else if case .library = route {
                LibraryScreen(model: store.library)
            } else if let model = store.searchModel(for: route) {
                SearchScreen(model: model)
            } else if let model = store.model(for: route) {
                if case .explore(.charts) = route { ChartsScreen(model: model) } else { BrowseScreen(model: model) }
            } else if let model = store.entityModel(for: route) {
                EntityScreen(model: model)
            } else {
                PlaceholderScreen(title: route.title)
            }
        }
        .id(store.generation)
        .navigationBarBackButtonHidden()
    }
}
