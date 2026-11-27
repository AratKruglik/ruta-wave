import InnerTube
import SwiftUI

private let topAnchor = -1

struct BrowseScreen<Header: View>: View {
    @Bindable var model: BrowseModel
    @ViewBuilder let header: (BrowseModel.Content) -> Header

    @Environment(NavigationModel.self) private var navigation
    @State private var width = Metrics.defaultWindowWidth

    private var padding: CGFloat { width >= Metrics.widePageWidth ? Metrics.space32 : Metrics.space24 }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .task(id: model.loadKey) { await model.load() }
            .onReconnect { model.reloadIfFailed() }
            .onChange(of: navigation.scrollToTopRequests[navigation.selection]) { model.scrollAnchor = topAnchor }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ScrollView {
                model.source.skeleton
                    .padding(padding)
            }
            .scrollDisabled(true)
        case .failed:
            LoadErrorView(title: model.source.errorTitle, onRetry: model.retry)
        case .empty:
            model.source.emptyPage
        case .loaded(let page):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Metrics.space48) {
                    VStack(alignment: .leading, spacing: Metrics.space16) {
                        if let title = page.title {
                            Text(title)
                                .font(.rwDisplay)
                                .foregroundStyle(.textPrimary)
                                .accessibilityAddTraits(.isHeader)
                        }
                        header(page)
                        if !page.chips.isEmpty { ChipRow(chips: page.chips, onSelect: model.selectChip) }
                    }
                    .id(topAnchor)
                    ForEach(Array(page.shelves.enumerated()), id: \.offset) { index, shelf in
                        ShelfView(shelf: shelf, onMore: { navigation.push(Route(target: $0)) }, pageMargin: padding)
                            .id(index)
                    }
                    footer(page.paging)
                }
                .scrollTargetLayout()
                .padding(padding)
                .background(alignment: .top) { if model.source.isMoodSelected { ThemeHeaderGradient() } }
            }
            .scrollPosition(id: $model.scrollAnchor, anchor: .top)
        }
    }

    @ViewBuilder
    private func footer(_ paging: BrowseModel.Paging) -> some View {
        switch paging {
        case .idle: Color.clear.frame(height: 1).onAppear { model.loadMore() }
        case .loading: ProgressView().frame(maxWidth: .infinity).controlSize(.small)
        case .failed: InlineErrorRow(onRetry: model.retryMore)
        case .done: EmptyView()
        }
    }
}

@MainActor private extension BrowseModel.Source {
    var isMoodSelected: Bool {
        if case .home(let params) = self { params != nil } else { false }
    }

    @ViewBuilder var skeleton: some View {
        VStack(alignment: .leading, spacing: Metrics.space48) {
            switch self {
            case .home:
                ChipRow(chips: Array(repeating: Chip(title: "Placeholder"), count: 6), onSelect: { _ in })
                ForEach(0..<3, id: \.self) { _ in cardShelf }
            case .browse(let target):
                switch target.browseId {
                case BrowseTarget.explore.browseId:
                    ShelfView(shelf: .placeholderLinks([.newReleases, .charts, .moodsAndGenres]), onMore: { _ in })
                    ForEach(0..<2, id: \.self) { _ in cardShelf }
                case BrowseTarget.moodsAndGenres.browseId:
                    placeholderTitle
                    ForEach(0..<2, id: \.self) { _ in
                        ShelfView(
                            shelf: .placeholderLinks(Array(repeating: .moodCategory(params: ""), count: 12), title: "Placeholder shelf title"),
                            onMore: { _ in })
                    }
                case BrowseTarget.moodCategoryId:
                    placeholderTitle
                    ForEach(0..<2, id: \.self) { _ in cardShelf }
                default:
                    placeholderTitle
                    ShelfView(shelf: .placeholder(layout: .grid, count: 12), onMore: { _ in })
                }
            case .charts:
                placeholderTitle
                Picker("Country", selection: .constant(0)) {
                    Text(verbatim: "Placeholder country").tag(0)
                }
                .pickerStyle(.menu)
                .font(.rwButton)
                .fixedSize()
                ForEach(0..<2, id: \.self) { _ in
                    ShelfView(shelf: .placeholder(layout: .rows, count: 12, ranked: true), onMore: { _ in })
                }
            }
        }
        .placeholderStyle()
    }

    private var cardShelf: some View {
        ShelfView(shelf: .placeholder(layout: .cards), onMore: { _ in })
    }

    private var placeholderTitle: some View {
        Text(verbatim: "Placeholder title").font(.rwDisplay)
    }

    var errorTitle: LocalizedStringKey {
        switch self {
        case .home: "Couldn't load Home"
        case .charts: "Couldn't load Charts"
        case .browse(let target):
            switch target.browseId {
            case BrowseTarget.explore.browseId: "Couldn't load Explore"
            case BrowseTarget.newReleases.browseId: "Couldn't load New releases"
            case BrowseTarget.moodsAndGenres.browseId: "Couldn't load Moods & genres"
            case BrowseTarget.moodCategoryId: "Couldn't load this category"
            default: "Couldn't load this page"
            }
        }
    }

    var emptyPage: EmptyPageView {
        switch self {
        case .home: EmptyPageView(title: "Your home page is empty", message: "Play a few songs and recommendations will show up here.")
        case .charts: EmptyPageView(title: "No charts for this country", message: "Pick another country above.")
        case .browse(let target):
            switch target.browseId {
            case BrowseTarget.explore.browseId:
                EmptyPageView(title: "Nothing to explore right now", message: "New releases, charts and moods will show up here. Try again later.")
            case BrowseTarget.newReleases.browseId:
                EmptyPageView(title: "No new releases right now", message: "New albums and singles will show up here as they come out.")
            case BrowseTarget.moodsAndGenres.browseId, BrowseTarget.moodCategoryId:
                EmptyPageView(title: "Nothing in this category yet", message: "Playlists for this mood will show up here.")
            default:
                EmptyPageView(title: "Nothing more here", message: "This list has no items yet.")
            }
        }
    }
}

extension BrowseScreen where Header == EmptyView {
    init(model: BrowseModel) {
        self.init(model: model) { _ in EmptyView() }
    }
}

#if DEBUG
#Preview("Home, signed in") { BrowsePreview(.signedIn) }
#Preview("Home, guest") { BrowsePreview(.guest) }
#Preview("Loading") { BrowsePreview(.loading) }
#Preview("Error") { BrowsePreview(.failing) }
#Preview("Empty") { BrowsePreview(.empty) }

private struct BrowsePreview: View {
    @State private var model: BrowseModel

    init(_ variant: PreviewFixtures.BrowseVariant) {
        _model = State(initialValue: PreviewFixtures.browseModel(variant))
    }

    var body: some View {
        BrowseScreen(model: model)
            .frame(width: 1100, height: 800)
            .environment(NavigationModel())
            .environment(PreviewFixtures.nowPlaying())
            .background(.themeBase)
    }
}
#endif
