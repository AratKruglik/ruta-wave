import SwiftUI

struct SectionRoot: View {
    let section: SidebarSection
    let isSignedIn: Bool
    @Environment(\.requestSignIn) private var requestSignIn

    var body: some View {
        if section == .library, !isSignedIn {
            GuestPromptContent(reason: "Sign in to see your library", onSignIn: requestSignIn.perform)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch section {
            case .home: HomeScreen()
            case .explore: ExploreScreen()
            case .library: PlaceholderScreen(title: section.title)
            }
        }
    }
}

struct RouteScreen: View {
    let route: Route

    @Environment(BrowseStore.self) private var store

    var body: some View {
        Group {
            if let model = store.searchModel(for: route) {
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
