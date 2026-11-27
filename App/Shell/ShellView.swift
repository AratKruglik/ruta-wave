import AppKit
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
    @Environment(\.themeBase) private var themeBase
    @State private var width = Metrics.defaultWindowWidth
    @State private var sidebarOverride: Bool?
    @State private var detailLeadingEdge: CGFloat = 0
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
                .focusSection()
                .focusable(!navigation.isPlayerPagePresented)
                .accessibilityHidden(navigation.isPlayerPagePresented)
                .barClearance(.bottom, playerBarClearance)
                .barClearance(.top, Metrics.topBarHeight)
                .ignoresSafeArea(.container, edges: .top)
                .navigationSplitViewColumnWidth(Metrics.sidebarWidth)
                .toolbar(removing: .sidebarToggle)
            } detail: {
                content
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: {
                        detailLeadingEdge = $0
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if isOffline {
                            OfflineBanner()
                        } else if guestFailed {
                            GuestBanner(onRetry: onRetryGuest)
                        }
                    }
                    .barClearance(.bottom, playerBarClearance)
                    .barClearance(.top, Metrics.topBarHeight)
                    .ignoresSafeArea(.container, edges: .top)
                    .focusSection()
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
            .toolbar {
                TopBar(
                    isSignedIn: isSignedIn, avatarURL: avatarURL, canGoBack: navigation.canGoBack || navigation.isPlayerPagePresented,
                    canGoForward: navigation.canGoForward, isSidebarVisible: isSidebarVisible, selection: navigation.selection,
                    isAccountPresented: $isAccountPresented, onToggleSidebar: { setSidebarVisible(!isSidebarVisible) },
                    onBack: navigation.back, onForward: navigation.forward, onSelectSection: navigation.select, onSignIn: onSignIn,
                    accountPopover: accountPopover)
            }
            // Pushed pages are hosted by the split view itself and draw above anything inside the detail column,
            // so the player page sits over the whole split view, inset to the detail column's live leading edge (the sidebar is resizable).
            .overlay {
                // The animation stays inside the overlay: an animated transaction over the split view re-shows the stack's root page.
                ZStack {
                    if navigation.isPlayerPagePresented {
                        PlayerPage { navigation.isPlayerPagePresented = false }
                            .barClearance(.bottom, playerBarClearance)
                            .barClearance(.top, Metrics.topBarHeight)
                            .padding(.leading, isSidebarVisible ? max(detailLeadingEdge, 0) : 0)
                            .transition(.move(edge: .bottom))
                    }
                }
                .animation(Motion.pageAnimation(reduceMotion: reduceMotion), value: navigation.isPlayerPagePresented)
            }
        }
        // Every column reserves the toolbar strip itself (barClearance), so the container's top safe area is ignored.
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .top) {
            if !LiquidGlass.isAvailable {
                themeBase.frame(height: Metrics.topBarHeight).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .windowFrameMonitor { newWidth in
            if WindowLayout.crossesCollapseThreshold(from: width, to: newWidth) { sidebarOverride = nil }
            width = newWidth
        }
        .overlay(alignment: .bottom) { bottomOverlay }
        .windowBackdrop()
        .noInitialFocus()
        .focusedSceneValue(\.navigation, navigation)
        .background {
            Button("Search") { navigation.requestSearchFocus() }
                .keyboardShortcut("l")
                .hidden()
        }
        .background(
            WindowEventMonitor(
                onBack: navigation.back, onForward: navigation.forward, onTogglePlay: nowPlaying.togglePlay,
                onMouseDown: search.mouseDown(at:)))
    }

    /// The bar's footprint including the gap under its glass, so the last row ends above it.
    private var playerBarClearance: CGFloat { isBarVisible ? Metrics.playerBarHeight + Metrics.space8 : 0 }

    private var content: some View {
        NavigationStack(path: Binding(
            get: { navigation.path(for: navigation.selection) },
            set: { navigation.setPath($0, for: navigation.selection) })
        ) {
            SectionRoot(section: navigation.selection, isSignedIn: isSignedIn)
                .cappedContentWidth()
                .navigationDestination(for: Route.self) {
                    // Pushed pages are hosted outside the stack's modifiers, so they need the bar clearance of their own.
                    RouteScreen(route: $0)
                        .cappedContentWidth()
                        .barClearance(.bottom, playerBarClearance)
                        .barClearance(.top, Metrics.topBarHeight)
                        .ignoresSafeArea(.container, edges: .top)
                }
        }
        .id(StackIdentity(section: navigation.selection, content: isSignedIn))
        .disabled(navigation.isPlayerPagePresented)
        .accessibilityHidden(navigation.isPlayerPagePresented)
    }

    private var bottomOverlay: some View {
        VStack(spacing: Metrics.space8) {
            if let toast = toasts.toast {
                ToastView(toast: toast, onUndo: toasts.undo, onHold: toasts.setHeld)
                    .transition(.opacity)
            }
            if isBarVisible {
                PlayerBar(isPlayerPagePresented: Bindable(navigation).isPlayerPagePresented)
                    .focusSection()
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
        if NSApp.currentEvent?.type == .keyDown, selectedPlaylistId != nil {
            navigation.replaceLast(.playlist(browseId: browseId))
        } else {
            navigation.push(.playlist(browseId: browseId))
        }
    }
}

private extension View {
    func cappedContentWidth() -> some View {
        frame(maxWidth: Metrics.contentMaxWidth).frame(maxWidth: .infinity)
    }
}

/// The bars float over the split view because a safe area set outside it does not reach the columns, so every column,
/// pushed page and the player page reserves their space itself. On macOS 26 the reserved space is a bar, which gives
/// the scroll views under it the system scroll edge effect.
private struct BarClearance: ViewModifier {
    let edge: VerticalEdge
    let height: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .safeAreaBar(edge: edge, spacing: 0) {
                    Color.clear.frame(height: height).allowsHitTesting(false).accessibilityHidden(true)
                }
                .scrollEdgeEffectStyle(edge == .top ? .hard : .soft, for: edge == .top ? .top : .bottom)
        } else {
            content.safeAreaPadding(edge == .top ? .top : .bottom, height)
        }
    }
}

private extension View {
    func barClearance(_ edge: VerticalEdge, _ height: CGFloat) -> some View {
        modifier(BarClearance(edge: edge, height: height))
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
                .buttonStyle(LinkButtonStyle())
                .font(.rwButton)
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
