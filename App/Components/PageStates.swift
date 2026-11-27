import InnerTube
import SwiftUI

extension View {
    func placeholderStyle() -> some View {
        redacted(reason: .placeholder).disabled(true).allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct SkeletonChips: View {
    var body: some View {
        ChipRow(chips: Array(repeating: Chip(title: "Placeholder"), count: 6), onSelect: { _ in })
            .placeholderStyle()
    }
}

struct SkeletonShelf: View {
    var body: some View {
        ShelfView(shelf: .placeholder(layout: .cards), onMore: { _ in })
            .placeholderStyle()
    }
}

struct SkeletonRows: View {
    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                TrackRow(song: .placeholder, density: .detailed)
            }
        }
        .placeholderStyle()
    }
}

struct PageErrorView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: Metrics.space12) {
            Text("Couldn't load this page")
                .font(.rwTitle)
                .foregroundStyle(.textPrimary)
            Button("Retry", action: onRetry)
                .buttonStyle(PillButtonStyle(isProminent: true))
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
            Button("Back", action: onBack)
                .buttonStyle(PillButtonStyle(isProminent: true))
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
        Text(verbatim: "Placeholder title")
            .font(.rwDisplay)
            .placeholderStyle()
    }
}

struct SkeletonTiles: View {
    var body: some View {
        ShelfView(shelf: .placeholderLinks([.newReleases, .charts, .moodsAndGenres]), onMore: { _ in })
            .placeholderStyle()
    }
}

struct SkeletonCardGrid: View {
    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: Metrics.cardSize), spacing: Metrics.space16, alignment: .top)],
            alignment: .leading, spacing: Metrics.space24
        ) {
            ForEach(0..<12, id: \.self) { _ in MusicCard(item: .placeholder) }
        }
        .placeholderStyle()
    }
}

struct SkeletonChipGrid: View {
    var body: some View {
        ShelfView(shelf: .placeholderLinks(Array(repeating: .moodCategory(params: ""), count: 12), title: "Placeholder shelf title"), onMore: { _ in })
            .placeholderStyle()
    }
}

#if DEBUG
#Preview("States") {
    VStack(spacing: Metrics.space24) {
        SkeletonChips()
        SkeletonShelf()
        SkeletonChipGrid()
        InlineErrorRow(onRetry: {})
        PageErrorView(onRetry: {}).frame(height: 120)
        UnavailableView(title: "This album isn't available", onBack: {}).frame(height: 120)
        EmptyPageView(title: "Nothing from this artist yet").frame(height: 80)
    }
    .padding()
    .frame(width: 800)
    .environment(NavigationModel())
    .environment(PreviewFixtures.nowPlaying())
    .background(.themeBase)
}
#endif
