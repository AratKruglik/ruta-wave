import SwiftUI

struct PlaceholderScreen: View {
    let title: LocalizedStringResource

    var body: some View {
        VStack(spacing: Metrics.space8) {
            Text(title)
                .font(.rwShelfTitle)
                .foregroundStyle(.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Coming soon")
                .font(.rwBody)
                .foregroundStyle(.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.themeBase)
    }
}

struct PlayerPagePlaceholder: View {
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PlaceholderScreen(title: "Player")
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.rwIcon(Metrics.iconBar))
                    .foregroundStyle(.textPrimary)
                    .frame(width: Metrics.hitTarget, height: Metrics.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close player page")
            .accessibilityLabel("Close player page")
            .padding(Metrics.space16)
        }
        .background(.themeBase)
    }
}

#Preview("Placeholder") {
    PlaceholderScreen(title: "Home").background(.themeBase)
}

#Preview("Player page") {
    PlayerPagePlaceholder(onClose: {}).frame(width: 600, height: 400)
}
