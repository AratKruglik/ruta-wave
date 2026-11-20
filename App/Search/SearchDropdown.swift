import InnerTube
import SwiftUI

struct SearchDropdown: View {
    let model: SearchFieldModel
    let onAction: (SearchFieldModel.Action) -> Void

    private var typed: String { model.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.rows.enumerated()), id: \.offset) { index, row in
                rowView(row, isHighlighted: model.highlighted == index)
            }
        }
        .padding(.vertical, Metrics.space8)
        .background(Color.themeBase)
        .background(Color.surfaceRaised)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Metrics.radiusCard, bottomTrailingRadius: Metrics.radiusCard))
        .shadow(color: .shadow, radius: Metrics.dropdownShadowRadius, y: Metrics.space4)
        .onHover { model.isPointerOverDropdown = $0 }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func rowView(_ row: SearchFieldModel.Row, isHighlighted: Bool) -> some View {
        switch row {
        case .history(let entry):
            HistoryRow(entry: entry, isHighlighted: isHighlighted, onSelect: { onAction(model.activate(row)) }, onRemove: { model.remove(entry) })
        case .query(let query):
            QueryRow(query: query, typed: typed, isHighlighted: isHighlighted) { onAction(model.activate(row)) }
        case .item(let item):
            EntityRow(item: item, isHighlighted: isHighlighted) { onAction(model.activate(row)) }
        }
    }
}

private struct RowChrome<Content: View>: View {
    let height: CGFloat
    let isHighlighted: Bool
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.space12) { content }
                .padding(.horizontal, Metrics.space12)
                .frame(height: height)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isHighlighted ? Color.surfaceFill : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

private struct HistoryRow: View {
    let entry: SearchHistoryEntry
    let isHighlighted: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            RowChrome(height: Metrics.searchRowHeight, isHighlighted: isHighlighted, action: onSelect) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.rwIcon(Metrics.iconRow))
                    .foregroundStyle(.textTertiary)
                    .accessibilityHidden(true)
                Text(entry.query)
                    .font(.rwBody)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Metrics.hitTarget)
            }
            .accessibilityLabel(entry.query)
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.rwIcon(Metrics.iconRow))
                    .foregroundStyle(.textSecondary)
                    .frame(width: Metrics.hitTarget, height: Metrics.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, Metrics.space8)
            .help("Remove from recent searches")
            .accessibilityLabel("Remove from recent searches")
        }
    }
}

private struct QueryRow: View {
    let query: String
    let typed: String
    let isHighlighted: Bool
    let action: () -> Void

    private var label: Text {
        guard !typed.isEmpty, query.lowercased().hasPrefix(typed.lowercased()) else {
            return Text(verbatim: query).foregroundStyle(.textPrimary)
        }
        let split = query.index(query.startIndex, offsetBy: typed.count)
        return Text(verbatim: String(query[..<split])).foregroundStyle(.textPrimary)
            + Text(verbatim: String(query[split...])).foregroundStyle(.textSecondary)
    }

    var body: some View {
        RowChrome(height: Metrics.searchRowHeight, isHighlighted: isHighlighted, action: action) {
            Image(systemName: "magnifyingglass")
                .font(.rwIcon(Metrics.iconRow))
                .foregroundStyle(.textTertiary)
                .accessibilityHidden(true)
            label
                .font(.rwBody)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityLabel(query)
    }
}

private struct EntityRow: View {
    let item: MusicItem
    let isHighlighted: Bool
    let action: () -> Void

    var body: some View {
        RowChrome(height: Metrics.searchEntityRowHeight, isHighlighted: isHighlighted, action: action) {
            ArtworkImage(
                url: item.thumbnailURL, width: Metrics.artworkSize, height: Metrics.artworkSize, isCircle: item.isArtist,
                cornerRadius: Metrics.radiusThumb)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.cardTitle)
                    .font(.rwTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                if let subtitle = item.cardSubtitle {
                    Text(subtitle)
                        .font(.rwCaption)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityLabel([item.cardTitle, item.cardSubtitle].compactMap { $0 }.joined(separator: ", "))
    }
}
