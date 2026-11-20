import InnerTube
import SwiftUI

struct ExploreTiles: View {
    let links: [InnerTube.NavigationLink]

    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        HStack(spacing: Metrics.space16) {
            ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                Button { navigation.push(Route(target: link.target)) } label: {
                    VStack(spacing: Metrics.space8) {
                        Image(systemName: ExploreTile.symbol(for: link.target.browseId) ?? "music.note")
                            .font(.rwIcon(Metrics.iconSidebar))
                        Text(link.title)
                            .font(.rwTitle)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: Metrics.tileHeight)
                    .background(.surfaceFill, in: RoundedRectangle(cornerRadius: Metrics.radiusTile))
                    .contentShape(RoundedRectangle(cornerRadius: Metrics.radiusTile))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
