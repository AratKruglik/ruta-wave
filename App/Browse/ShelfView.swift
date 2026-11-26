import InnerTube
import SwiftUI

struct ShelfView: View {
    let shelf: Shelf
    let onMore: (BrowseTarget) -> Void
    var moreTitle: LocalizedStringKey = "More"
    var isPanel = false

    @Environment(NavigationModel.self) private var navigation
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var firstVisible: Int?
    @State private var width: CGFloat = 0

    private var isCarousel: Bool { shelf.layout == .cards || (shelf.layout == .rows && !isPanel) }

    private var itemWidth: CGFloat {
        switch shelf.layout {
        case .rows: Metrics.rowColumnWidth
        default: shelf.items.first?.isVideoCard == true ? Metrics.videoCardWidth : Metrics.cardSize
        }
    }

    private var columns: [[MusicItem]] {
        stride(from: 0, to: shelf.items.count, by: Metrics.quickPickRows).map {
            Array(shelf.items[$0..<min($0 + Metrics.quickPickRows, shelf.items.count)])
        }
    }

    private var carouselCount: Int { shelf.layout == .rows ? columns.count : shelf.items.count }

    private var visibleCount: Int { max(1, Int((width + Metrics.space16) / (itemWidth + Metrics.space16))) }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: Metrics.space16) {
            if shelf.title != nil || shelf.strapline != nil { header }
            shelfBody
        }
        .accessibilityElement(children: .contain)
        if let label = shelf.title ?? shelf.strapline {
            content.accessibilityLabel(label)
        } else {
            content
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: Metrics.space12) {
            VStack(alignment: .leading, spacing: 2) {
                if let strapline = shelf.strapline {
                    Text(strapline.uppercased())
                        .font(.rwShelfStrapline)
                        .foregroundStyle(.textSecondary)
                }
                if let title = shelf.title {
                    Text(title)
                        .font(.rwShelfTitle)
                        .foregroundStyle(.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            Spacer(minLength: Metrics.space16)
            if let more = shelf.more {
                Button { onMore(more) } label: { InversePillLabel(title: moreTitle) }
                    .buttonStyle(.plain)
            }
            if isCarousel {
                ScrollArrowButton(symbol: "chevron.left", label: "Scroll left", isEnabled: (firstVisible ?? 0) > 0) {
                    scroll(by: -visibleCount)
                }
                ScrollArrowButton(
                    symbol: "chevron.right", label: "Scroll right", isEnabled: (firstVisible ?? 0) + visibleCount < carouselCount
                ) { scroll(by: visibleCount) }
            }
        }
    }

    private func scroll(by delta: Int) {
        let target = min(max((firstVisible ?? 0) + delta, 0), max(carouselCount - 1, 0))
        withAnimation(Motion.animation(Motion.panel, reduceMotion: reduceMotion)) { firstVisible = target }
    }

    @ViewBuilder
    private var shelfBody: some View {
        if shelf.isExploreTiles {
            ExploreTiles(links: links)
        } else if shelf.isLinkGrid {
            LinkChipGrid(links: links) { navigation.push(Route(target: $0.target)) }
        } else {
            switch shelf.layout {
            case .cards: carousel { index in MusicCard(item: shelf.items[index]) }
            case .rows where isPanel:
                LazyVStack(spacing: 0) {
                    ForEach(Array(shelf.items.enumerated()), id: \.offset) { _, item in listRow(item, startsRadio: true) }
                }
            case .rows: carousel { index in rowColumn(columns[index]) }
            case .grid:
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: itemWidth), spacing: Metrics.space16, alignment: .top)],
                    alignment: .leading, spacing: Metrics.space24
                ) {
                    ForEach(Array(shelf.items.enumerated()), id: \.offset) { _, item in MusicCard(item: item) }
                }
            case .list:
                LazyVStack(spacing: 0) {
                    ForEach(Array(shelf.items.enumerated()), id: \.offset) { _, item in listRow(item) }
                }
            }
        }
    }

    private var links: [InnerTube.NavigationLink] {
        shelf.items.compactMap { if case .link(let link) = $0 { link } else { nil } }
    }

    private func carousel<Content: View>(@ViewBuilder _ content: @escaping (Int) -> Content) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Metrics.space16) {
                ForEach(0..<carouselCount, id: \.self) { index in content(index).id(index) }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $firstVisible, anchor: .leading)
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func rowColumn(_ items: [MusicItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in listRow(item, startsRadio: true) }
        }
        .frame(width: Metrics.rowColumnWidth)
    }

    @ViewBuilder
    private func listRow(_ item: MusicItem, startsRadio: Bool = false) -> some View {
        if case .song(let song) = item {
            let density: TrackRow.Density = song.rank != nil ? .numbered : (shelf.layout == .list ? .detailed : .compact)
            TrackRow(song: song, density: density, onPlay: startsRadio ? { nowPlaying.startRadio(song) } : nil)
        } else {
            MusicCard(item: item)
        }
    }
}

#if DEBUG
#Preview("Shelves") {
    ScrollView {
        VStack(alignment: .leading, spacing: Metrics.space48) {
            ForEach(Array(PreviewFixtures.shelves.enumerated()), id: \.offset) { _, shelf in
                ShelfView(shelf: shelf, onMore: { _ in })
            }
        }
        .padding(Metrics.space32)
    }
    .frame(width: 1100, height: 900)
    .environment(NavigationModel())
    .environment(PreviewFixtures.nowPlaying())
    .background(.themeBase)
}
#endif
