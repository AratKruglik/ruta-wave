import InnerTube
import SwiftUI
import SystemKit

extension View {
    func placeholderStyle() -> some View {
        redacted(reason: .placeholder).disabled(true).allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct LoadErrorView: View {
    let title: LocalizedStringKey
    let onRetry: () -> Void
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?

    private var reason: LocalizedStringKey {
        network?.isOnline == false ? "You're offline" : "Check your connection and try again"
    }

    var body: some View {
        ContentUnavailableView {
            Text(title).font(.rwTitle)
        } description: {
            Text(reason)
        } actions: {
            Button("Retry", action: onRetry)
                .buttonStyle(PillButtonStyle(isProminent: true))
        }
    }
}

struct InlineErrorRow: View {
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: Metrics.space12) {
            Text("Couldn't load more")
                .font(.rwBody)
                .foregroundStyle(.textSecondary)
            Button("Retry", action: onRetry)
                .buttonStyle(LinkButtonStyle())
                .font(.rwButton)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.space16)
    }
}

struct EmptyPageView: View {
    let title: LocalizedStringKey
    var message: LocalizedStringKey?

    var body: some View {
        VStack(spacing: Metrics.space8) {
            Text(title)
                .font(.rwTitle)
                .foregroundStyle(.textPrimary)
            if let message {
                Text(message)
                    .font(.rwBody)
                    .foregroundStyle(.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(Metrics.space24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("States") {
    VStack(spacing: Metrics.space24) {
        InlineErrorRow(onRetry: {})
        LoadErrorView(title: "Couldn't load History", onRetry: {}).frame(height: 160)
        EmptyPageView(title: "Nothing from this artist yet").frame(height: 80)
    }
    .padding()
    .frame(width: 800)
    .environment(NavigationModel())
    .environment(PreviewFixtures.nowPlaying())
    .background(.themeBase)
}
#endif
