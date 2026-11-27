import SwiftUI

struct TopBar<AccountPopover: View>: ToolbarContent {
    let isSignedIn: Bool
    let avatarURL: URL?
    let canGoBack: Bool
    let canGoForward: Bool
    let isSidebarVisible: Bool
    let selection: SidebarSection
    @Binding var isAccountPresented: Bool
    let onToggleSidebar: () -> Void
    let onBack: () -> Void
    let onForward: () -> Void
    let onSelectSection: (SidebarSection) -> Void
    let onSignIn: () -> Void
    @ViewBuilder let accountPopover: () -> AccountPopover

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: onToggleSidebar) { Label("Toggle sidebar", systemImage: "sidebar.left") }
                .help("Toggle sidebar")
            if !isSidebarVisible {
                Menu {
                    ForEach(SidebarSection.allCases, id: \.self) { section in
                        Button { onSelectSection(section) } label: { Label(section.title, systemImage: section.symbol) }
                    }
                } label: {
                    Label("Go", systemImage: selection.symbol)
                }
            }
            Button(action: onBack) { Label("Back", systemImage: "chevron.left") }
                .help("Back")
                .disabled(!canGoBack)
            Button(action: onForward) { Label("Forward", systemImage: "chevron.right") }
                .help("Forward")
                .disabled(!canGoForward)
        }
        searchItem
        ToolbarItem(placement: .primaryAction) { trailing }
    }

    @ToolbarContentBuilder private var searchItem: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: .principal) { SearchField().frame(minWidth: 240, idealWidth: 480, maxWidth: 720) }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { SearchField().frame(minWidth: 240, idealWidth: 480, maxWidth: 720) }
        }
    }

    @ViewBuilder private var trailing: some View {
        if isSignedIn {
            Button { isAccountPresented.toggle() } label: {
                AccountAvatar(url: avatarURL, size: Metrics.avatarSize)
            }
            .buttonStyle(.plain)
            .help("Account")
            .accessibilityLabel("Account")
            .popover(isPresented: $isAccountPresented) { accountPopover() }
        } else {
            Button(action: onSignIn) { Text("Sign in").lineLimit(1) }
                .buttonStyle(PillButtonStyle(isProminent: true))
        }
    }
}

struct AccountAvatar: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle").resizable().foregroundStyle(.textSecondary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
