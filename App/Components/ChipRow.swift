import InnerTube
import SwiftUI

struct ChipView: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.rwButton)
                .foregroundStyle(isSelected ? .textOnInverse : .textPrimary)
                .padding(.horizontal, Metrics.space16)
                .frame(height: Metrics.chipHeight)
                .background(isSelected ? .surfaceInverse : .surfaceFill, in: Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
        .onReturn(action)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One horizontal line; a trailing fade and scroll arrows show when it overflows.
struct ChipRow: View {
    let chips: [Chip]
    let onSelect: (Chip) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentWidth: CGFloat = 0
    @State private var viewWidth: CGFloat = 0
    @State private var firstVisible: Int?

    private var isOverflowing: Bool { contentWidth > viewWidth }

    private var visibleCount: Int {
        guard contentWidth > 0, !chips.isEmpty else { return 1 }
        return max(1, Int(viewWidth / (contentWidth / CGFloat(chips.count))))
    }

    var body: some View {
        HStack(spacing: Metrics.space8) {
            scroller
            if isOverflowing {
                ScrollArrowButton(symbol: "chevron.left", label: "Scroll left", isEnabled: (firstVisible ?? 0) > 0) {
                    scroll(by: -visibleCount)
                }
                ScrollArrowButton(
                    symbol: "chevron.right", label: "Scroll right", isEnabled: (firstVisible ?? 0) + visibleCount < chips.count
                ) { scroll(by: visibleCount) }
            }
        }
        .onChange(of: chips.count) { firstVisible = 0 }
    }

    private var scroller: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Metrics.space8) {
                ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                    ChipView(title: chip.title, isSelected: chip.isSelected) { onSelect(chip) }
                        .id(index)
                }
            }
            .scrollTargetLayout()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        }
        .scrollPosition(id: $firstVisible, anchor: .leading)
        .scrollIndicators(.hidden)
        .contentMargins(.vertical, 0, for: .scrollContent)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewWidth = $0 }
        .frame(height: Metrics.chipHeight)
        .mask {
            LinearGradient(
                stops: [.init(color: .black, location: 0), .init(color: .black, location: isOverflowing ? 0.94 : 1),
                        .init(color: isOverflowing ? .clear : .black, location: 1)],
                startPoint: .leading, endPoint: .trailing)
        }
    }

    private func scroll(by delta: Int) {
        let target = min(max((firstVisible ?? 0) + delta, 0), max(chips.count - 1, 0))
        withAnimation(Motion.animation(Motion.panel, reduceMotion: reduceMotion)) { firstVisible = target }
    }
}

/// Mood and genre buttons with their coloured edge.
struct LinkChipGrid: View {
    let links: [InnerTube.NavigationLink]
    let onOpen: (InnerTube.NavigationLink) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: Metrics.space16)], spacing: Metrics.space16) {
            ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                Button { onOpen(link) } label: {
                    HStack(spacing: Metrics.space12) {
                        Rectangle()
                            .fill(link.stripeColor.map { Color(argb: $0) } ?? Color.white.opacity(0.20))
                            .frame(width: Metrics.space4)
                        Text(link.title)
                            .font(.rwTitle)
                            .foregroundStyle(.textPrimary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .frame(height: Metrics.rowHeightDetailed)
                    .background(.surfaceFill, in: RoundedRectangle(cornerRadius: Metrics.radiusCard))
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusCard))
                    .contentShape(RoundedRectangle(cornerRadius: Metrics.radiusCard))
                }
                .buttonStyle(.plain)
                .onReturn { onOpen(link) }
            }
        }
    }
}

#Preview("Chips") {
    VStack(alignment: .leading, spacing: Metrics.space24) {
        ChipRow(
            chips: [Chip(title: "Relax"), Chip(title: "Workout", isSelected: true), Chip(title: "Focus")], onSelect: { _ in })
        LinkChipGrid(
            links: [
                InnerTube.NavigationLink(title: "Chill", target: BrowseTarget(browseId: "x"), stripeColor: 4288988671),
                InnerTube.NavigationLink(title: "Commute", target: BrowseTarget(browseId: "y"), stripeColor: 4294951424),
                InnerTube.NavigationLink(title: "Plain", target: BrowseTarget(browseId: "z")),
            ], onOpen: { _ in })
    }
    .padding()
    .frame(width: 700)
    .background(.themeBase)
}

#Preview("Chips under a bottom content margin") {
    VStack(alignment: .leading) {
        ChipRow(chips: [Chip(title: "Playlists", isSelected: true), Chip(title: "Songs"), Chip(title: "Albums")], onSelect: { _ in })
        Spacer()
    }
    .contentMargins(.bottom, 112, for: .scrollContent)
    .padding()
    .frame(width: 500, height: 200)
    .background(.themeBase)
}
