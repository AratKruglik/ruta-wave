import InnerTube
import SwiftUI
import SystemKit

struct RelatedView: View {
    let browseId: String

    @Environment(TrackTabsModel.self) private var trackTabs
    @Environment(NavigationModel.self) private var navigation
    @State private var attempt = 0

    private var phase: TrackTabsModel.Phase<BrowsePage> {
        trackTabs.related.flatMap { $0.id == browseId ? $0.phase : nil } ?? .loading
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task(id: TabLoadKey(id: browseId, generation: trackTabs.generation, attempt: attempt)) {
                await trackTabs.loadRelated(browseId)
            }
            .onReconnect { if case .failed = phase { attempt += 1 } }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading: SkeletonRows(count: 6).accessibilityHidden(true)
        case .loaded(let page): loaded(page)
        case .empty: RelatedEmptyView(onRetry: retry)
        case .failed: RelatedErrorView(onRetry: retry)
        }
    }

    private func retry() {
        trackTabs.discardRelated()
        attempt += 1
    }

    private func loaded(_ page: BrowsePage) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.space32) {
                ForEach(Array(page.shelves.items.enumerated()), id: \.offset) { _, shelf in
                    ShelfView(shelf: shelf, onMore: { navigation.push(Route(target: $0)) }, isPanel: true)
                }
                if let about = page.about { aboutBlock(about) }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func aboutBlock(_ about: DescriptionShelf) -> some View {
        VStack(alignment: .leading, spacing: Metrics.space12) {
            if let title = about.title {
                Text(verbatim: title)
                    .font(.rwShelfTitle)
                    .foregroundStyle(.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            ExpandableText(text: about.text)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(about.title ?? "")
    }
}

struct RelatedEmptyView: View {
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Text("Nothing related for this track").font(.rwTitle)
        } actions: {
            Button(action: onRetry) { InversePillLabel(title: "Retry") }
                .buttonStyle(.plain)
        }
    }
}

struct RelatedErrorView: View {
    let onRetry: () -> Void
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?

    private var reason: LocalizedStringKey {
        network?.isOnline == false ? "You're offline" : "Check your connection and try again"
    }

    var body: some View {
        ContentUnavailableView {
            Text("Couldn't load Related").font(.rwTitle)
        } description: {
            Text(reason)
        } actions: {
            Button(action: onRetry) { InversePillLabel(title: "Retry") }
                .buttonStyle(.plain)
        }
    }
}

#if DEBUG
#Preview("Related") {
    RelatedView(browseId: "MPTRtpreview")
        .frame(width: 400, height: 600)
        .padding()
        .environment(PreviewFixtures.trackTabs())
        .environment(NavigationModel())
        .environment(PreviewFixtures.nowPlaying())
        .background(.themeBase)
}
#endif
