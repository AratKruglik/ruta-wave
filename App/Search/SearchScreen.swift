import InnerTube
import SwiftUI

extension SearchSection.Kind {
    fileprivate var title: LocalizedStringKey {
        switch self {
        case .songs: "Songs"
        case .videos: "Videos"
        case .albums: "Albums"
        case .artists: "Artists"
        case .playlists: "Playlists"
        }
    }
}

struct SearchScreen: View {
    let model: SearchModel

    @Environment(NavigationModel.self) private var navigation
    @State private var width = Metrics.defaultWindowWidth
    @State private var selection = TrackSelection()

    private var padding: CGFloat { width >= Metrics.widePageWidth ? Metrics.space32 : Metrics.space24 }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space16) {
            if !model.chips.isEmpty {
                ChipRow(chips: chipItems, onSelect: select)
                    .padding(.horizontal, padding)
                    .padding(.top, padding)
            } else if case .loading = model.state {
                ChipRow(chips: Array(repeating: Chip(title: "Placeholder"), count: 6), onSelect: { _ in })
                    .placeholderStyle()
                    .padding(.horizontal, padding)
                    .padding(.top, padding)
            }
            results
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task(id: model.loadKey) { await model.load() }
        .onReconnect { model.reloadIfFailed() }
    }

    private var chipItems: [Chip] {
        [Chip(title: String(localized: "All"), isSelected: model.isAllSelected)]
            + model.chips.map {
                Chip(
                    title: $0.title, target: $0.target, searchParams: $0.searchParams, isSelected: model.isChipSelected($0),
                    watchTarget: $0.watchTarget)
            }
    }

    private func select(_ chip: Chip) {
        let route = Route.search(query: model.query, filter: chip.isSelected ? nil : chip.searchParams)
        let path = navigation.path(for: navigation.selection)
        if path.count >= 2, path[path.count - 2] == route { navigation.back() } else { navigation.replaceLast(route) }
    }

    @ViewBuilder
    private var skeleton: some View {
        Group {
            if model.isAllSelected {
                VStack(alignment: .leading, spacing: Metrics.space32) {
                    VStack(alignment: .leading, spacing: Metrics.space16) {
                        header("Top result")
                        TopResultCard(item: .placeholder)
                    }
                    placeholderRows(4)
                    ShelfView(shelf: .placeholder(layout: .cards), onMore: { _ in }, pageMargin: padding)
                }
            } else {
                switch SearchSection.Kind(filter: model.filter) {
                case .albums, .artists, .playlists:
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: Metrics.cardSize), spacing: Metrics.space16, alignment: .top)],
                        alignment: .leading, spacing: Metrics.space24
                    ) {
                        ForEach(0..<12, id: \.self) { _ in MusicCard(item: .placeholder) }
                    }
                case .songs, .videos, .none: placeholderRows(8)
                }
            }
        }
        .placeholderStyle()
    }

    private func placeholderRows(_ count: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in TrackRow(song: .placeholder, density: .detailed) }
        }
    }

    @ViewBuilder
    private var results: some View {
        switch model.state {
        case .loading:
            ScrollView {
                skeleton.padding(padding)
            }
            .scrollDisabled(true)
        case .failed:
            LoadErrorView(title: "Couldn't load search results", onRetry: model.retry)
        case .empty:
            ContentUnavailableView.search(text: model.query)
        case .loaded(let content):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Metrics.space32) {
                    if let correction = content.correction { CorrectionLine(correction: correction) }
                    if content.isFiltered { filtered(content) } else { grouped(content) }
                }
                .padding(padding)
            }
        }
    }

    @ViewBuilder
    private func grouped(_ content: SearchModel.Content) -> some View {
        if let top = content.topResult {
            VStack(alignment: .leading, spacing: Metrics.space16) {
                header("Top result")
                TopResultCard(item: top, isSubscribed: content.isTopResultSubscribed, onToggleSubscribed: model.toggleTopResultSubscribed)
            }
        }
        ForEach(content.sections, id: \.kind) { section in
            VStack(alignment: .leading, spacing: Metrics.space16) {
                HStack {
                    header(section.kind.title)
                    Spacer(minLength: Metrics.space16)
                    if let params = section.showAllParams {
                        Button("Show all") { navigation.push(.search(query: model.query, filter: params)) }
                            .buttonStyle(PillButtonStyle())
                    }
                }
                sectionBody(section)
            }
        }
    }

    @ViewBuilder
    private func sectionBody(_ section: SearchSection) -> some View {
        switch section.kind {
        case .songs, .videos:
            let songs = section.items.compactMap { if case .song(let song) = $0 { song } else { nil } }
            let order = songs.map(\.rowKey)
            VStack(spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.offset) { _, song in
                    TrackRow(
                        song: song, density: .detailed,
                        selection: section.kind == .songs ? $selection.row(for: song, order: order, songs: songs) : nil)
                }
            }
            .trackSelection($selection, songs: section.kind == .songs ? songs : [])
        case .albums, .artists, .playlists:
            ShelfView(shelf: Shelf(title: nil, layout: .cards, items: section.items), onMore: { navigation.push(Route(target: $0)) }, pageMargin: padding)
        }
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.rwShelfTitle)
            .foregroundStyle(.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func filtered(_ content: SearchModel.Content) -> some View {
        let items = content.items
        let songs = items.compactMap { if case .song(let song) = $0 { song } else { nil } }
        if songs.count == items.count {
            let order = songs.map(\.rowKey)
            LazyVStack(spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                    TrackRow(song: song, density: .detailed, selection: $selection.row(for: song, order: order, songs: songs))
                        .onAppear { prefetch(index, of: items.count) }
                }
            }
            .trackSelection($selection, songs: songs)
        } else {
            LazyVGrid(
                columns: [GridItem(
                    .adaptive(minimum: items.first?.isVideoCard == true ? Metrics.videoCardWidth : Metrics.cardSize), spacing: Metrics.space16, alignment: .top)],
                alignment: .leading, spacing: Metrics.space24
            ) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    MusicCard(item: item)
                        .onAppear { prefetch(index, of: items.count) }
                }
            }
        }
        footer(content.paging)
    }

    private func prefetch(_ index: Int, of count: Int) {
        if index >= count - 10 { model.loadMore() }
    }

    @ViewBuilder
    private func footer(_ paging: SearchModel.Paging) -> some View {
        switch paging {
        case .loading: ProgressView().frame(maxWidth: .infinity).controlSize(.small)
        case .failed: InlineErrorRow(onRetry: model.retryMore)
        case .idle: Color.clear.frame(height: 1).onAppear { model.loadMore() }
        case .done: EmptyView()
        }
    }
}

private struct CorrectionLine: View {
    let correction: SearchCorrection

    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space4) {
            Text("Showing results for \(correction.correctedQuery)")
                .font(.rwTitle)
                .foregroundStyle(.textPrimary)
            Button {
                navigation.push(.search(query: correction.originalQuery, filter: correction.originalParams))
            } label: {
                Text("Search instead for \(correction.originalQuery)")
                    .font(.rwBody)
                    .foregroundStyle(.accentLink)
            }
            .buttonStyle(.plain)
        }
    }
}

#if DEBUG
#Preview("All") { SearchScreenPreview(.all) }
#Preview("Filtered") { SearchScreenPreview(.filtered) }
#Preview("Loading") { SearchScreenPreview(.loading) }
#Preview("Empty") { SearchScreenPreview(.empty) }
#Preview("Error") { SearchScreenPreview(.failing) }

private struct SearchScreenPreview: View {
    @State private var model: SearchModel

    init(_ variant: PreviewFixtures.SearchVariant) {
        _model = State(initialValue: PreviewFixtures.searchModel(variant))
    }

    var body: some View {
        SearchScreen(model: model)
            .frame(width: 1100, height: 800)
            .environment(NavigationModel())
            .environment(PreviewFixtures.nowPlaying())
            .background(.themeBase)
    }
}
#endif
