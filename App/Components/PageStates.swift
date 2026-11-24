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

struct SkeletonRows: View {
    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: Metrics.space12) {
                    RoundedRectangle(cornerRadius: Metrics.radiusThumb).fill(.surfaceFill)
                        .frame(width: Metrics.rowThumb, height: Metrics.rowThumb)
                    VStack(alignment: .leading, spacing: Metrics.space8) {
                        Capsule().fill(.surfaceFill).frame(width: 220, height: 12)
                        Capsule().fill(.surfaceFill).frame(width: 140, height: 10)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Metrics.space8)
                .frame(height: Metrics.rowHeightDetailed)
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

struct UnavailableView: View {
    let title: LocalizedStringKey
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: Metrics.space12) {
            Text(title)
                .font(.rwTitle)
                .foregroundStyle(.textPrimary)
            Button(action: onBack) { InversePillLabel(title: "Back") }
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

struct SkeletonTitle: View {
    var body: some View {
        Capsule().fill(.surfaceFill).frame(width: 280, height: 40)
            .accessibilityHidden(true)
    }
}

struct SkeletonTiles: View {
    var body: some View {
        HStack(spacing: Metrics.space16) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Metrics.radiusTile).fill(.surfaceFill)
                    .frame(maxWidth: .infinity, minHeight: Metrics.tileHeight, maxHeight: Metrics.tileHeight)
            }
        }
        .accessibilityHidden(true)
    }
}

struct SkeletonGrid: View {
    let count: Int

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.cardSize), spacing: Metrics.space16)], spacing: Metrics.space24) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Metrics.radiusCard).fill(.surfaceFill)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityHidden(true)
    }
}

struct SkeletonTopResult: View {
    var body: some View {
        HStack(spacing: Metrics.space16) {
            RoundedRectangle(cornerRadius: Metrics.radiusCard).fill(.surfaceFill)
                .frame(width: Metrics.cardSize, height: Metrics.cardSize)
            VStack(alignment: .leading, spacing: Metrics.space8) {
                Capsule().fill(.surfaceFill).frame(width: 200, height: 20)
                Capsule().fill(.surfaceFill).frame(width: 120, height: 12)
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}

#Preview("States") {
    VStack(spacing: Metrics.space24) {
        SkeletonChips()
        SkeletonShelf()
        InlineErrorRow(onRetry: {})
        PageErrorView(onRetry: {}).frame(height: 120)
        UnavailableView(title: "This album isn't available", onBack: {}).frame(height: 120)
        EmptyPageView(title: "Nothing from this artist yet").frame(height: 80)
    }
    .padding()
    .frame(width: 800)
    .background(.themeBase)
}
