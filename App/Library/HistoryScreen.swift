import InnerTube
import SwiftUI

struct HistoryScreen: View {
    let model: HistoryModel

    @State private var width = Metrics.defaultWindowWidth

    private var padding: CGFloat { width >= Metrics.widePageWidth ? Metrics.space32 : Metrics.space24 }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .task(id: model.loadKey) { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.space16) {
                    title
                    SkeletonRows(count: 8)
                }
                .padding(padding)
            }
            .scrollDisabled(true)
        case .failed:
            PageErrorView(onRetry: model.retry)
        case .empty:
            VStack(alignment: .leading, spacing: Metrics.space16) {
                title
                Text("Songs you play appear here")
                    .font(.rwBody)
                    .foregroundStyle(.textSecondary)
            }
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .loaded(let days):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Metrics.space24) {
                    title
                    ForEach(days, id: \.title) { day in
                        VStack(alignment: .leading, spacing: Metrics.space8) {
                            Text(day.title)
                                .font(.rwTitle)
                                .foregroundStyle(.textSecondary)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(Array(day.entries.enumerated()), id: \.offset) { _, entry in
                                TrackRow(
                                    song: entry.song, density: .detailed,
                                    onRemoveFromHistory: entry.feedbackToken == nil ? nil : { model.remove(entry) })
                            }
                        }
                    }
                }
                .padding(padding)
            }
        }
    }

    private var title: some View {
        Text("History")
            .font(.rwShelfTitle)
            .foregroundStyle(.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
#Preview("History") { HistoryPreview(.loaded) }
#Preview("Empty") { HistoryPreview(.empty) }
#Preview("Loading") { HistoryPreview(.loading) }
#Preview("Failed") { HistoryPreview(.failed) }

private struct HistoryPreview: View {
    @State private var model: HistoryModel

    init(_ variant: PreviewFixtures.HistoryVariant) {
        _model = State(initialValue: PreviewFixtures.historyModel(variant))
    }

    var body: some View {
        HistoryScreen(model: model)
            .frame(width: 1000, height: 800)
            .environment(NavigationModel())
            .environment(PreviewFixtures.nowPlaying())
            .environment(ToastCenter())
            .background(.themeBase)
    }
}
#endif
