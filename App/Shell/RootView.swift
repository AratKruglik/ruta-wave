import Auth
import InnerTube
import SwiftUI

private struct ReloadKey: Equatable {
    let identity: ContentIdentity
    let attempt: Int
}

struct RootView: View {
    let session: AuthSession
    let nowPlaying: NowPlayingModel
    let toasts: ToastCenter

    @State private var browse: BrowseStore
    @State private var searchField: SearchFieldModel
    @State private var navigation = NavigationModel()
    @State private var account = AccountModel()
    @State private var sidebar: SidebarModel
    @State private var guest = GuestModel()
    @State private var isSigningIn = false
    @State private var isAccountPresented = false
    @State private var isNewPlaylistPresented = false
    @State private var isCreatingPlaylist = false
    @State private var sidebarIdentity: ContentIdentity?
    @State private var accountAttempt = 0
    @State private var sidebarAttempt = 0
    @State private var guestAttempt = 0

    init(session: AuthSession, nowPlaying: NowPlayingModel, toasts: ToastCenter) {
        self.session = session
        self.nowPlaying = nowPlaying
        self.toasts = toasts
        let client = InnerTubeClient()
        let searchLoader = SearchLoader.live(client)
        _browse = State(initialValue: BrowseStore(
            loader: .live(client), searchLoader: searchLoader, entityLoader: .live(client), libraryLoader: .live(client),
            toasts: toasts, credentials: { session.credentials }))
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
        .environment(session)
        .environment(navigation)
        .environment(nowPlaying)
        .environment(toasts)
        .environment(sidebar)
        .environment(browse)
        .environment(searchField)
        .environment(\.requestSignIn, SignInRequest { isSigningIn = true })
        .onChange(of: session.state.isSignedIn) { _, signedIn in
            if signedIn {
                isSigningIn = false
            } else {
                isAccountPresented = false
                navigation.dropAccountRoutes()
            }
        }
        .onChange(of: session.contentIdentity) {
            browse.reset()
            searchField.reset()
            navigation.dropIdentityRoutes()
            nowPlaying.resetAccountState()
            guest.reset()
            toasts.reset()
            isNewPlaylistPresented = false
        }
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
        .onChange(of: session.isAddingAccount) { _, adding in
            if !adding { accountAttempt += 1 }
        }
        .sheet(isPresented: Binding(get: { isSigningIn }, set: { if !$0 { cancelSignIn() } })) {
            SignInSheet(session: session, onCancel: cancelSignIn)
        }
        .sheet(isPresented: $isNewPlaylistPresented) {
            NewPlaylistSheet(
                initial: NewPlaylistDraft(videoIds: navigation.pendingPlaylistVideoIds),
                isCreating: isCreatingPlaylist, onCancel: { isNewPlaylistPresented = false }, onCreate: createPlaylist)
        }
        .sheet(isPresented: Binding(get: { session.isAddingAccount }, set: { if !$0 { session.cancelAddAccount() } })) {
            AddAccountSheet(session: session)
        }
    }

    private var shell: some View {
        ShellView(
            isSignedIn: session.state.isSignedIn, identity: session.contentIdentity, avatarURL: avatarURL,
            sidebar: sidebar, guestFailed: !session.state.isSignedIn && guest.state == .failed,
            isAccountPresented: $isAccountPresented, onRetrySidebar: { sidebarAttempt += 1 },
            onNewPlaylist: { navigation.requestNewPlaylist() },
            onPlaylistRemoved: { browse.playlistRemoved($0, deleted: $1) },
            onRetryGuest: { guestAttempt += 1 }, onSignIn: { isSigningIn = true }
        ) {
            AccountView(
                state: account.state, authUserIndex: session.authUserIndex, isSigningOut: session.isSigningOut,
                signOutFailed: session.signOutError != nil,
                onSwitch: { session.authUserIndex = $0 },
                onAddAccount: {
                    isAccountPresented = false
                    session.addAccount()
                },
                onHistory: {
                    isAccountPresented = false
                    navigation.push(.history)
                },
                onSignOut: { Task { await session.signOut() } },
                onRetry: { accountAttempt += 1 })
        }
        .task(id: ReloadKey(identity: session.contentIdentity, attempt: accountAttempt)) {
            await account.load(session: session)
        }
        .task(id: ReloadKey(identity: session.contentIdentity, attempt: sidebarAttempt)) {
            // Reset here rather than in `onChange`: a reset that lands after this load started would drop its result.
            if sidebarIdentity != session.contentIdentity {
                sidebar.reset()
                sidebarIdentity = session.contentIdentity
            }
            await sidebar.load()
        }
        .task(id: ReloadKey(identity: session.contentIdentity, attempt: guestAttempt)) {
            guard !session.state.isSignedIn else { return }
            await guest.connect()
        }
    }

    private var avatarURL: URL? {
        if case .loaded(let info, _) = account.state { info.avatarURL } else { nil }
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

private struct AddAccountSheet: View {
    let session: AuthSession

    var body: some View {
        VStack(spacing: 0) {
            SignInView(session: session)
            Button("Cancel") { session.cancelAddAccount() }
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
