import SwiftUI

struct InversePillLabel: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.rwButton)
            .foregroundStyle(.textOnInverse)
            .padding(.horizontal, Metrics.space16)
            .frame(height: Metrics.pillHeight)
            .background(.surfaceInverse, in: Capsule())
            .fixedSize()
    }
}

struct SkeletonChips: View {
    var body: some View {
        HStack(spacing: Metrics.space8) {
            ForEach(0..<6, id: \.self) { _ in
                Capsule().fill(.surfaceFill).frame(width: 88, height: Metrics.chipHeight)
            }
        }
        .accessibilityHidden(true)
    }
}

struct SkeletonShelf: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space16) {
            RoundedRectangle(cornerRadius: Metrics.radiusThumb).fill(.surfaceFill).frame(width: 220, height: 28)
            HStack(spacing: Metrics.space16) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Metrics.radiusCard).fill(.surfaceFill)
                        .frame(width: Metrics.cardSize, height: Metrics.cardSize)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct PageErrorView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: Metrics.space12) {
            Text("Couldn't load this page")
                .font(.rwTitle)
                .foregroundStyle(.textPrimary)
            Button(action: onRetry) { InversePillLabel(title: "Retry") }
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
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
                .buttonStyle(.plain)
                .font(.rwButton)
                .foregroundStyle(.accentLink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.space16)
    }
}

struct EmptyPageView: View {
    var body: some View {
        Text("Nothing here yet")
            .font(.rwTitle)
            .foregroundStyle(.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("States") {
    VStack(spacing: Metrics.space24) {
        SkeletonChips()
        SkeletonShelf()
        InlineErrorRow(onRetry: {})
        PageErrorView(onRetry: {}).frame(height: 120)
        EmptyPageView().frame(height: 80)
    }
    .padding()
    .frame(width: 800)
    .background(.themeBase)
}
