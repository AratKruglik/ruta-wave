import AppKit
import SwiftUI

struct TopBar<AccountPopover: View>: View {
    let isSignedIn: Bool
    let avatarURL: URL?
    let canGoBack: Bool
    let canGoForward: Bool
    @Binding var isAccountPresented: Bool
    let onToggleSidebar: () -> Void
    let onBack: () -> Void
    let onForward: () -> Void
    let onSignIn: () -> Void
    @ViewBuilder let accountPopover: () -> AccountPopover

    @Environment(\.themeBase) private var themeBase

    var body: some View {
        HStack(spacing: Metrics.space8) {
            BarIconButton(symbol: "sidebar.left", size: Metrics.iconBar, label: "Toggle sidebar", action: onToggleSidebar)
                .padding(.horizontal, LiquidGlass.isAvailable ? Metrics.space4 : 0)
            .glassSurface(in: Capsule(), fallback: nil)
            .padding(.leading, Metrics.space24)
            HStack(spacing: Metrics.space8) {
                BarIconButton(symbol: "chevron.left", size: Metrics.iconBar, label: "Back", action: onBack)
                    .disabled(!canGoBack)
                BarIconButton(symbol: "chevron.right", size: Metrics.iconBar, label: "Forward", action: onForward)
                    .disabled(!canGoForward)
            }
            .padding(.horizontal, LiquidGlass.isAvailable ? Metrics.space4 : 0)
            .glassSurface(in: Capsule(), fallback: nil, interactive: true)
            Spacer(minLength: Metrics.space16)
            SearchField()
                .frame(minWidth: 240, maxWidth: 720)
            Spacer(minLength: Metrics.space16)
            trailing
        }
        .padding(.leading, Metrics.trafficLightsInset)
        .padding(.trailing, Metrics.space16)
        .frame(height: Metrics.topBarHeight)
        .glassGroup()
        .background(TitleBarDragArea())
        .background(backdrop)
    }

    /// On macOS 26 the pages' scroll edge effect covers the content under the bar; older systems get the opaque bar.
    private var backdrop: Color { LiquidGlass.isAvailable ? .clear : themeBase }

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

private struct TitleBarDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard event.clickCount == 2 else {
                window?.performDrag(with: event)
                return
            }
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window?.performMiniaturize(nil)
            case "None": break
            default: window?.performZoom(nil)
            }
        }
    }
}

#if DEBUG
#Preview("Signed in") {
    TopBar(
        isSignedIn: true, avatarURL: nil, canGoBack: true, canGoForward: false, isAccountPresented: .constant(false),
        onToggleSidebar: {}, onBack: {}, onForward: {}, onSignIn: {}, accountPopover: { EmptyView() }
    )
    .frame(width: 1100)
    .environment(PreviewFixtures.searchFieldModel(.empty))
    .environment(NavigationModel())
    .environment(PreviewFixtures.nowPlaying())
    .background(.themeBase)
}

#Preview("Guest") {
    TopBar(
        isSignedIn: false, avatarURL: nil, canGoBack: false, canGoForward: false, isAccountPresented: .constant(false),
        onToggleSidebar: {}, onBack: {}, onForward: {}, onSignIn: {}, accountPopover: { EmptyView() }
    )
    .frame(width: 960)
    .environment(PreviewFixtures.searchFieldModel(.empty))
    .environment(NavigationModel())
    .environment(PreviewFixtures.nowPlaying())
    .background(.themeBase)
}
#endif
