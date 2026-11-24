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

/// One horizontal line; a trailing fade shows when it overflows.
struct ChipRow: View {
    let chips: [Chip]
    let onSelect: (Chip) -> Void

    @State private var contentWidth: CGFloat = 0
    @State private var viewWidth: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Metrics.space8) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    ChipView(title: chip.title, isSelected: chip.isSelected) { onSelect(chip) }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        }
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewWidth = $0 }
        .frame(height: Metrics.chipHeight)
        .mask {
            LinearGradient(
                stops: [.init(color: .black, location: 0), .init(color: .black, location: contentWidth > viewWidth ? 0.94 : 1),
                        .init(color: contentWidth > viewWidth ? .clear : .black, location: 1)],
                startPoint: .leading, endPoint: .trailing)
        }
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
