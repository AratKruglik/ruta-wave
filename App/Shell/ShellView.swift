import AppSettings
import SwiftUI

struct ShellView<AccountPopover: View>: View {
    let isSignedIn: Bool
    let identity: ContentIdentity
    let avatarURL: URL?
    let sidebar: SidebarModel.State
    let guestFailed: Bool
    @Binding var isAccountPresented: Bool
    let onRetrySidebar: () -> Void
    let onRetryGuest: () -> Void
    let onSignIn: () -> Void
    @ViewBuilder let accountPopover: () -> AccountPopover

    @Environment(NavigationModel.self) private var navigation
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width = Metrics.defaultWindowWidth
    @State private var sidebarOverride: Bool?
    @State private var isSidebarCollapsedPreference = Preferences().sidebarCollapsed

    private var isNarrow: Bool { width < Metrics.sidebarAutoCollapseWidth }
    private var isBarVisible: Bool { nowPlaying.player.song != nil }
    private var isSidebarVisible: Bool { sidebarOverride ?? (!isNarrow && !isSidebarCollapsedPreference) }

    private var selectedPlaylistId: String? {
        if case .playlist(let browseId) = navigation.path(for: navigation.selection).last { browseId } else { nil }
    }

    var body: some View {
        Group {
            NavigationSplitView(columnVisibility: columnVisibility) {
                SidebarView(
                    selectedSection: navigation.selection, selectedPlaylistId: selectedPlaylistId, isSignedIn: isSignedIn,
                    playlists: sidebar, onSelectSection: navigation.select, onSelectPlaylist: openPlaylist,
                    onRetry: onRetrySidebar, onSignIn: onSignIn
                )
                .safeAreaPadding(.top, Metrics.topBarHeight)
                .ignoresSafeArea(.container, edges: .top)
                .navigationSplitViewColumnWidth(Metrics.sidebarWidth)
                .toolbar(removing: .sidebarToggle)
            } detail: {
                content
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if guestFailed { GuestBanner(onRetry: onRetryGuest) }
                    }
                    .safeAreaPadding(.top, Metrics.topBarHeight)
                    .ignoresSafeArea(.container, edges: .top)
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
            // The bar floats over both columns so content scrolls under its glass.
            .overlay(alignment: .top) {
                TopBar(
                    isSignedIn: isSignedIn, avatarURL: avatarURL, canGoBack: navigation.canGoBack,
                    canGoForward: navigation.canGoForward, isAccountPresented: $isAccountPresented,
                    onToggleSidebar: { setSidebarVisible(!isSidebarVisible) }, onHome: navigation.goHome,
                    onBack: navigation.back, onForward: navigation.forward, onSignIn: onSignIn, accountPopover: accountPopover)
            }
        }
        // The split view's window toolbar reserves a strip above the custom top bar even under .hiddenTitleBar;
        // hiding the toolbar itself would also remove the window buttons.
        .ignoresSafeArea(.container, edges: .top)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
            if (width < Metrics.sidebarAutoCollapseWidth) != (newWidth < Metrics.sidebarAutoCollapseWidth) { sidebarOverride = nil }
            width = newWidth
        }
        .overlay(alignment: .bottom) { bottomOverlay }
        .windowBackdrop()
        .noInitialFocus()
        .focusedSceneValue(\.navigation, navigation)
        .background(
            WindowEventMonitor(
                onBack: navigation.back, onForward: navigation.forward, onTogglePlay: nowPlaying.togglePlay))
    }

    private var content: some View {
        NavigationStack(path: Binding(
            get: { navigation.path(for: navigation.selection) },
            set: { navigation.setPath($0, for: navigation.selection) })
        ) {
            SectionRoot(section: navigation.selection, isSignedIn: isSignedIn)
                .navigationDestination(for: Route.self) { RouteScreen(route: $0) }
        }
        .id(StackIdentity(section: navigation.selection, content: identity))
        .contentMargins(.bottom, isBarVisible ? Metrics.playerBarHeight + Metrics.contentBottomMargin : 0, for: .scrollContent)
        .overlay {
            if navigation.isPlayerPagePresented {
                PlayerPagePlaceholder { navigation.isPlayerPagePresented = false }
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(Motion.animation(Motion.panel, reduceMotion: reduceMotion), value: navigation.isPlayerPagePresented)
    }

    private var bottomOverlay: some View {
        VStack(spacing: Metrics.space8) {
            if let message = toasts.message {
                ToastView(message: message)
                    .transition(.opacity)
            }
            if isBarVisible {
                PlayerBar(isPlayerPagePresented: Bindable(navigation).isPlayerPagePresented)
            }
        }
        .animation(Motion.animation(Motion.hover, reduceMotion: reduceMotion), value: toasts.message == nil)
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { isSidebarVisible ? .all : .detailOnly },
            set: { setSidebarVisible($0 != .detailOnly) })
    }

    private func setSidebarVisible(_ visible: Bool) {
        if isNarrow {
            sidebarOverride = visible
        } else {
            sidebarOverride = nil
            isSidebarCollapsedPreference = !visible
            Preferences().sidebarCollapsed = !visible
        }
    }

    private func openPlaylist(_ browseId: String) {
        guard selectedPlaylistId != browseId else { return }
        navigation.push(.playlist(browseId: browseId))
    }
}

private struct StackIdentity: Hashable {
    let section: SidebarSection
    let content: ContentIdentity
}

private struct GuestBanner: View {
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: Metrics.space12) {
            Text("Couldn't reach YouTube Music")
                .font(.rwBody)
                .foregroundStyle(.textPrimary)
            Button("Retry", action: onRetry)
                .buttonStyle(.plain)
                .font(.rwButton)
                .foregroundStyle(.accentLink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.space8)
        .background(.surfaceFill)
        .accessibilityElement(children: .combine)
    }
}

extension FocusedValues {
    @Entry var navigation: NavigationModel?
}

#if DEBUG
#Preview("Signed in, playing") {
    ShellPreview(isSignedIn: true, player: PreviewPlayer())
}

#Preview("Guest, nothing playing") {
    let player = PreviewPlayer()
    player.song = nil
    return ShellPreview(isSignedIn: false, player: player)
}

private struct ShellPreview: View {
    let isSignedIn: Bool
    let player: PreviewPlayer

    var body: some View {
        ShellView(
            isSignedIn: isSignedIn, identity: ContentIdentity(isSignedIn: isSignedIn, authUserIndex: 0), avatarURL: nil,
            sidebar: .loaded(isSignedIn ? PreviewFixtures.playlists : []), guestFailed: false,
            isAccountPresented: .constant(false), onRetrySidebar: {}, onRetryGuest: {}, onSignIn: {},
            accountPopover: { EmptyView() }
        )
        .environment(NavigationModel())
        .environment(PreviewFixtures.nowPlaying(player, signedIn: isSignedIn))
        .environment(ToastCenter())
        .frame(width: 1280, height: 800)
    }
}
#endif
