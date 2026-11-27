import AppSettings
import Auth
import InnerTube
import SwiftUI
import SystemKit

private struct ThemeKey: Equatable {
    let artworkURL: URL?
    let isEnabled: Bool
}

private struct ReloadKey: Equatable {
    let identity: Bool
    let attempt: Int
}

struct RootView: View {
    let session: AuthSession
    let nowPlaying: NowPlayingModel
    let toasts: ToastCenter
    let network: NetworkMonitor
    let links: LinkInbox

    @State private var browse: BrowseStore
    @State private var searchField: SearchFieldModel
    @State private var trackTabs: TrackTabsModel
    @State private var navigation: NavigationModel
    @State private var account = AccountModel()
    @State private var sidebar: SidebarModel
    @State private var guest = GuestModel()
    @State private var isSigningIn = false
    @State private var isAccountPresented = false
    @State private var isNewPlaylistPresented = false
    @State private var isCreatingPlaylist = false
    @State private var sidebarIdentity: Bool?
    @State private var accountAttempt = 0
    @State private var sidebarAttempt = 0
    @State private var guestAttempt = 0
    @State private var theme = ArtworkTheme()
    @State private var useArtworkColors = Preferences().useArtworkColors
    @State private var alwaysOnTop = Preferences().alwaysOnTop
    @State private var showsDislikeButton = Preferences().showDislikeButton
    @State private var karaokeEnabled = Preferences().karaokeEnabled

    /// Later main windows (a Dock reopen after closing) keep the page the user left instead of re-running launch rules.
    @MainActor private static var hasRestoredLaunchState = false

    init(session: AuthSession, nowPlaying: NowPlayingModel, toasts: ToastCenter, network: NetworkMonitor, links: LinkInbox) {
        self.session = session
        self.nowPlaying = nowPlaying
        self.toasts = toasts
        self.network = network
        self.links = links
        let preferences = Preferences()
        let isLaunch = !Self.hasRestoredLaunchState
        Self.hasRestoredLaunchState = true
        _navigation = State(initialValue: .restored(
            from: preferences.navigationState, isSignedIn: session.state.isSignedIn,
            startingPage: isLaunch ? SidebarSection(preference: preferences.startingPage) : nil, isLaunch: isLaunch))
        let client = InnerTubeClient()
        let searchLoader = SearchLoader.live(client)
        _browse = State(initialValue: BrowseStore(
            loader: .live(client), searchLoader: searchLoader, entityLoader: .live(client), libraryLoader: .live(client),
            toasts: toasts, credentials: { session.credentials }))
        _trackTabs = State(initialValue: TrackTabsModel(loader: .live(client), credentials: { session.credentials }))
        _sidebar = State(initialValue: SidebarModel(
            loader: .live(client), credentials: { session.credentials }, toasts: toasts))
        _searchField = State(initialValue: SearchFieldModel(
            loader: searchLoader, credentials: { session.credentials }, toasts: toasts))
    }

    var body: some View {
        Group {
            if case .keychainUnavailable = session.state {
                KeychainUnavailableView(onRetry: session.restore, onContinue: session.continueAsGuest)
            } else {
                shell
            }
        }
        .frame(minWidth: Metrics.minWindowWidth, minHeight: Metrics.minWindowHeight)
        .preferredColorScheme(.dark)
        .focusEffectDisabled()
        .environment(session)
        .environment(navigation)
        .environment(nowPlaying)
        .environment(trackTabs)
        .environment(toasts)
        .environment(network)
        .environment(sidebar)
        .environment(browse)
        .environment(searchField)
        .environment(\.requestSignIn, SignInRequest { isSigningIn = true })
        .environment(\.themeBase, theme.base)
        .environment(\.themeHeaderTop, theme.headerTop)
        .environment(\.showsDislikeButton, showsDislikeButton)
        .environment(\.karaokeEnabled, karaokeEnabled)
        .background(WindowLevel(isFloating: alwaysOnTop))
        .task(id: ThemeKey(artworkURL: nowPlaying.player.song?.artworkURL, isEnabled: useArtworkColors)) {
            await theme.update(artworkURL: useArtworkColors ? nowPlaying.player.song?.artworkURL : nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: DispatchQueue.main)) { _ in
            let preferences = Preferences()
            useArtworkColors = preferences.useArtworkColors
            alwaysOnTop = preferences.alwaysOnTop
            showsDislikeButton = preferences.showDislikeButton
            karaokeEnabled = preferences.karaokeEnabled
        }
        .onChange(of: session.state.isSignedIn) { _, signedIn in
            if signedIn {
                isSigningIn = false
            } else {
                isAccountPresented = false
                navigation.dropAccountRoutes()
            }
            browse.reset()
            searchField.reset()
            navigation.dropIdentityRoutes()
            trackTabs.reset()
            guest.reset()
            isNewPlaylistPresented = false
        }
        .onChange(of: navigation.snapshot(isSignedIn: session.state.isSignedIn)) { _, snapshot in
            Preferences().navigationState = try? JSONEncoder().encode(snapshot)
        }
        .onChange(of: links.pending, initial: true) { _, link in
            guard let link else { return }
            links.pending = nil
            open(link)
        }
        .onChange(of: network.reconnects) { retryFailedLoads() }
        .onChange(of: network.isOnline) { _, online in nowPlaying.networkChanged(isOnline: online) }
        .onChange(of: navigation.newPlaylistRequests) {
            if session.state.isSignedIn { isNewPlaylistPresented = true } else { isSigningIn = true }
        }
        .onChange(of: browse.lastPlaylistChange) { _, change in
            guard let change else { return }
            sidebar.applyLibraryChange(change.playlist, saved: change.saved)
            Task { await sidebar.load() }
        }
        .onChange(of: session.state.isSignedIn || guest.state == .connected, initial: true) { _, ready in
            browse.setReady(ready)
        }
        .onChange(of: session.isSessionExpired, initial: true) { _, expired in
            if expired { isSigningIn = true }
        }
        .sheet(isPresented: Binding(get: { isSigningIn }, set: { if !$0 { cancelSignIn() } })) {
            SignInSheet(session: session, onCancel: cancelSignIn)
        }
        .sheet(isPresented: $isNewPlaylistPresented) {
            NewPlaylistSheet(
                initial: NewPlaylistDraft(videoIds: navigation.pendingPlaylistVideoIds),
                isCreating: isCreatingPlaylist, onCancel: { isNewPlaylistPresented = false }, onCreate: createPlaylist)
        }
    }

    private var shell: some View {
        ShellView(
            isSignedIn: session.state.isSignedIn, avatarURL: avatarURL,
            sidebar: sidebar, guestFailed: !session.state.isSignedIn && guest.state == .failed, isOffline: !network.isOnline,
            isAccountPresented: $isAccountPresented, onRetrySidebar: { sidebarAttempt += 1 },
            onNewPlaylist: { navigation.requestNewPlaylist() },
            onPlaylistRemoved: { browse.playlistRemoved($0, deleted: $1) },
            onRetryGuest: { guestAttempt += 1 }, onSignIn: { isSigningIn = true }
        ) {
            AccountView(
                state: account.state, isSigningOut: session.isSigningOut,
                signOutFailed: session.signOutError != nil,
                onHistory: {
                    isAccountPresented = false
                    navigation.push(.history)
                },
                onSignOut: { Task { await session.signOut() } },
                onRetry: { accountAttempt += 1 })
        }
        .task(id: ReloadKey(identity: session.state.isSignedIn, attempt: accountAttempt)) {
            await account.load(session: session)
        }
        .task(id: ReloadKey(identity: session.state.isSignedIn, attempt: sidebarAttempt)) {
            // Reset here rather than in `onChange`: a reset that lands after this load started would drop its result.
            if sidebarIdentity != session.state.isSignedIn {
                sidebar.reset()
                sidebarIdentity = session.state.isSignedIn
            }
            await sidebar.load()
        }
        .task(id: ReloadKey(identity: session.state.isSignedIn, attempt: guestAttempt)) {
            guard !session.state.isSignedIn else { return }
            await guest.connect()
        }
    }

    private var avatarURL: URL? {
        if case .loaded(let info) = account.state { info.avatarURL } else { nil }
    }

    private func retryFailedLoads() {
        if case .failed = sidebar.state { sidebarAttempt += 1 }
        if !session.state.isSignedIn, guest.state == .failed { guestAttempt += 1 }
        if case .failed = account.state { accountAttempt += 1 }
    }

    private func createPlaylist(_ draft: NewPlaylistDraft) {
        guard !isCreatingPlaylist else { return }
        isCreatingPlaylist = true
        Task {
            let result = await sidebar.create(draft)
            isCreatingPlaylist = false
            switch result {
            case .created(let browseId):
                isNewPlaylistPresented = false
                browse.libraryChanged()
                navigation.push(.playlist(browseId: browseId))
            case .mayExist:
                isNewPlaylistPresented = false
                browse.libraryChanged()
                toasts.show("The playlist may have been created")
                await sidebar.load()
            case .failed:
                toasts.show("Couldn't create the playlist")
            case .discarded:
                break
            }
        }
    }

    private func open(_ link: MusicLink) {
        switch link {
        case .section(let section): navigation.select(section)
        case .route(.history) where !session.state.isSignedIn: isSigningIn = true
        case .route(let route): navigation.push(route)
        case .play, .openInBrowser: break
        }
    }

    private func cancelSignIn() {
        isSigningIn = false
        Task { await session.cancelSignIn() }
    }
}

private struct SignInSheet: View {
    let session: AuthSession
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if session.isSessionExpired {
                Text("Your session expired. Sign in again.")
                    .font(.rwBody)
                    .padding(Metrics.space8)
            }
            SignInView(session: session)
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .padding(Metrics.space8)
        }
        .frame(minWidth: 520, minHeight: 640)
    }
}

private struct KeychainUnavailableView: View {
    let onRetry: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: Metrics.space12) {
            Text("Couldn't access the saved session")
                .font(.rwTitle)
                .foregroundStyle(.textPrimary)
            Button("Try again", action: onRetry)
            Button("Continue without signing in", action: onContinue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .windowBackdrop()
    }
}

#Preview("Keychain unavailable") {
    KeychainUnavailableView(onRetry: {}, onContinue: {})
}
