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
            PlaceholderScreen(title: section.title)
        }
    }
}

struct RouteScreen: View {
    let route: Route

    var body: some View {
        PlaceholderScreen(title: route.title)
            .navigationBarBackButtonHidden()
    }
}
