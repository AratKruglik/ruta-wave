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
    }
}

#Preview("Placeholder") {
    PlaceholderScreen(title: "Home").background(.themeBase)
}
