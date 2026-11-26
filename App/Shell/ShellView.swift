import AppSettings
import SwiftUI

struct ShellView<AccountPopover: View>: View {
    let isSignedIn: Bool
    let avatarURL: URL?
    let sidebar: SidebarModel
    let guestFailed: Bool
    let isOffline: Bool
    @Binding var isAccountPresented: Bool
    let onRetrySidebar: () -> Void
    let onNewPlaylist: () -> Void
    let onPlaylistRemoved: (String, Bool) -> Void
    let onRetryGuest: () -> Void
    let onSignIn: () -> Void
    @ViewBuilder let accountPopover: () -> AccountPopover

    @Environment(NavigationModel.self) private var navigation
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(ToastCenter.self) private var toasts
    @Environment(SearchFieldModel.self) private var search
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width = Metrics.defaultWindowWidth
    @State private var sidebarOverride: Bool?
    @State private var isSidebarCollapsedPreference = Preferences().sidebarCollapsed

    private var isNarrow: Bool { WindowLayout.isNarrow(width: width) }
    private var isBarVisible: Bool { nowPlaying.player.song != nil }
    private var isSidebarVisible: Bool {
        WindowLayout.isSidebarVisible(width: width, override: sidebarOverride, collapsedPreference: isSidebarCollapsedPreference)
    }

    private var selectedPlaylistId: String? {
        if case .playlist(let browseId) = navigation.path(for: navigation.selection).last { browseId } else { nil }
    }

    var body: some View {
        Group {
            NavigationSplitView(columnVisibility: columnVisibility) {
                SidebarView(
                    selectedSection: navigation.selection, selectedPlaylistId: selectedPlaylistId, isSignedIn: isSignedIn,
                    model: sidebar, onSelectSection: navigation.select, onSelectPlaylist: openPlaylist,
                    onNewPlaylist: onNewPlaylist, onPlaylistRemoved: onPlaylistRemoved, onRetry: onRetrySidebar, onSignIn: onSignIn
                )
                .id(isSignedIn)
                .accessibilityHidden(navigation.isPlayerPagePresented)
                .safeAreaPadding(.top, Metrics.topBarHeight)
                .ignoresSafeArea(.container, edges: .top)
                .navigationSplitViewColumnWidth(Metrics.sidebarWidth)
                .toolbar(removing: .sidebarToggle)
            } detail: {
                content
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if isOffline {
                            OfflineBanner()
                        } else if guestFailed {
                            GuestBanner(onRetry: onRetryGuest)
                        }
                    }
                    .safeAreaPadding(.top, Metrics.topBarHeight)
                    .ignoresSafeArea(.container, edges: .top)
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
            // Pushed pages are hosted by the split view itself and draw above anything inside the detail column,
            // so the player page sits over the whole split view, inset past the sidebar.
            .overlay {
                // The animation stays inside the overlay: an animated transaction over the split view re-shows the stack's root page.
                ZStack {
                    if navigation.isPlayerPagePresented {
                        PlayerPage { navigation.isPlayerPagePresented = false }
                            .safeAreaPadding(.top, Metrics.topBarHeight)
                            .padding(.leading, isSidebarVisible ? Metrics.sidebarWidth : 0)
                            .transition(.move(edge: .bottom))
                    }
                }
                .animation(Motion.animation(Motion.panel, reduceMotion: reduceMotion), value: navigation.isPlayerPagePresented)
            }
            // The bar floats over both columns so content scrolls under its glass.
            .overlay(alignment: .top) {
                TopBar(
                    isSignedIn: isSignedIn, avatarURL: avatarURL, canGoBack: navigation.canGoBack,
                    canGoForward: navigation.canGoForward, isAccountPresented: $isAccountPresented,
                    onToggleSidebar: { setSidebarVisible(!isSidebarVisible) },
                    onBack: navigation.back, onForward: navigation.forward, onSignIn: onSignIn, accountPopover: accountPopover)
                    .accessibilityHidden(navigation.isPlayerPagePresented)
            }
        }
        // The split view's window toolbar reserves a strip above the custom top bar even under .hiddenTitleBar;
        // hiding the toolbar itself would also remove the window buttons.
        .ignoresSafeArea(.container, edges: .top)
        .windowFrameMonitor { newWidth in
            if WindowLayout.crossesCollapseThreshold(from: width, to: newWidth) { sidebarOverride = nil }
            width = newWidth
        }
        .overlay(alignment: .bottom) { bottomOverlay }
        .windowBackdrop()
        .noInitialFocus()
        .focusedSceneValue(\.navigation, navigation)
        .onChange(of: navigation.path(for: navigation.selection).last, initial: true) { _, route in
            if case .search(let query, _) = route { search.showQuery(query) }
        }
        .background(
            WindowEventMonitor(
                onBack: navigation.back, onForward: navigation.forward, onTogglePlay: nowPlaying.togglePlay,
                onMouseDown: search.mouseDownInWindow))
    }

    private var barInset: CGFloat { isBarVisible ? Metrics.playerBarHeight + Metrics.contentBottomMargin : 0 }

    private var content: some View {
        NavigationStack(path: Binding(
            get: { navigation.path(for: navigation.selection) },
            set: { navigation.setPath($0, for: navigation.selection) })
        ) {
            SectionRoot(section: navigation.selection, isSignedIn: isSignedIn)
                .navigationDestination(for: Route.self) {
                    // Pushed pages are hosted outside the stack's modifiers, so they need the bar inset of their own.
                    RouteScreen(route: $0)
                        .contentMargins(.bottom, barInset, for: .scrollContent)
                        .safeAreaPadding(.top, Metrics.topBarHeight)
                        .ignoresSafeArea(.container, edges: .top)
                }
        }
        .id(StackIdentity(section: navigation.selection, content: isSignedIn))
        .contentMargins(.bottom, barInset, for: .scrollContent)
        .disabled(navigation.isPlayerPagePresented)
        .accessibilityHidden(navigation.isPlayerPagePresented)
    }

    private var bottomOverlay: some View {
        VStack(spacing: Metrics.space8) {
            if let toast = toasts.toast {
                ToastView(toast: toast, onUndo: toasts.undo)
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
        guard selectedPlaylistId != browseId else {
            navigation.isPlayerPagePresented = false
            return
        }
        navigation.push(.playlist(browseId: browseId))
    }
}

private struct StackIdentity: Hashable {
    let section: SidebarSection
    let content: Bool
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

private struct OfflineBanner: View {
    var body: some View {
        VStack(spacing: Metrics.space4) {
            Text("You're offline")
                .font(.rwBody)
                .foregroundStyle(.textPrimary)
            Text("Pages you've opened stay available. Everything reloads when you're back online.")
                .font(.rwCaption)
                .foregroundStyle(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.space8)
        .background(.surfaceFill)
        .accessibilityElement(children: .combine)
        .onAppear { AccessibilityNotification.Announcement(String(localized: "You're offline")).post() }
    }
}

extension FocusedValues {
    @Entry var navigation: NavigationModel?
}

#if DEBUG
#Preview("Signed in, playing") {
    ShellPreview(isSignedIn: true, player: PreviewPlayer())
}

#Preview("Minimum window 960 x 600") {
    ShellPreview(isSignedIn: true, player: PreviewPlayer(), width: Metrics.minWindowWidth, height: Metrics.minWindowHeight)
}

#Preview("Guest, nothing playing") {
    let player = PreviewPlayer()
    player.song = nil
    return ShellPreview(isSignedIn: false, player: player)
}

private struct ShellPreview: View {
    let isSignedIn: Bool
    let player: PreviewPlayer
    var width: CGFloat = 1280
    var height: CGFloat = 800
    @State private var sidebar: SidebarModel

    init(isSignedIn: Bool, player: PreviewPlayer, width: CGFloat = 1280, height: CGFloat = 800) {
        self.isSignedIn = isSignedIn
        self.player = player
        self.width = width
        self.height = height
        _sidebar = State(initialValue: PreviewFixtures.sidebarModel(isSignedIn ? .loaded : .guest))
    }

    var body: some View {
        ShellView(
            isSignedIn: isSignedIn, avatarURL: nil,
            sidebar: sidebar, guestFailed: false, isOffline: false,
            isAccountPresented: .constant(false), onRetrySidebar: {}, onNewPlaylist: {}, onPlaylistRemoved: { _, _ in },
            onRetryGuest: {}, onSignIn: {},
            accountPopover: { EmptyView() }
        )
        .environment(NavigationModel())
        .environment(PreviewFixtures.nowPlaying(player, signedIn: isSignedIn))
        .environment(ToastCenter())
        .environment(PreviewFixtures.searchFieldModel(.empty))
        .task { await sidebar.load() }
        .frame(width: width, height: height)
    }
}
#endif
