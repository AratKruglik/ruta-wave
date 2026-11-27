import AppKit
import InnerTube
import SwiftUI

struct SearchDropdown: View {
    let model: SearchFieldModel
    let onAction: (SearchFieldModel.Action) -> Void

    @Environment(\.themeBase) private var themeBase

    private var typed: String { model.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.rows.enumerated()), id: \.offset) { index, row in
                if case .item = row, index > 0, !model.rows[index - 1].isItem {
                    Divider().overlay(.strokeSubtle).padding(.vertical, Metrics.space4)
                }
                rowView(row, isHighlighted: model.highlighted == index)
            }
        }
        .padding(.vertical, Metrics.space8)
        .background(themeBase)
        .background(Color.surfaceRaised)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Metrics.radiusCard, bottomTrailingRadius: Metrics.radiusCard))
        .shadow(color: .shadow, radius: Metrics.dropdownShadowRadius, y: Metrics.space4)
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

extension SearchFieldModel.Row {
    fileprivate var isItem: Bool { if case .item = self { true } else { false } }
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
            .buttonStyle(IconButtonStyle())
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

/// Hosts the suggestion list in a non-key child window: a toolbar clips an overlay, and a popover would take key
/// from the window, stealing the field's first responder and its Esc, arrow and typing handling.
struct SuggestionPanel<Content: View>: NSViewRepresentable {
    let isPresented: Bool
    let model: SearchFieldModel
    @ViewBuilder let content: Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onLayout = { [weak coordinator = context.coordinator] in coordinator?.reposition() }
        context.coordinator.anchor = view
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        model.fieldFrame = { [weak view] in view.map { $0.convert($0.bounds, to: nil) } ?? .zero }
        context.coordinator.update(
            isPresented: isPresented,
            content: content.padding(.horizontal, Metrics.dropdownShadowRadius).padding(.bottom, Metrics.dropdownShadowRadius * 2)
                .environment(\.themeBase, context.environment.themeBase),
            onResign: { [weak model] in model?.close() })
    }

    static func dismantleNSView(_ view: AnchorView, coordinator: Coordinator) { coordinator.tearDown() }

    final class AnchorView: NSView {
        var onLayout: () -> Void = {}

        override func layout() {
            super.layout()
            onLayout()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onLayout()
        }
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class HostingView<Root: View>: NSHostingView<Root> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    @MainActor
    final class Coordinator {
        weak var anchor: AnchorView?
        private var panel: Panel?
        private var hosting: HostingView<AnyView>?
        private var content = AnyView(EmptyView())
        private var resignToken: NSObjectProtocol?
        private var isPresented = false

        func update(isPresented: Bool, content: some View, onResign: @escaping @MainActor () -> Void) {
            self.isPresented = isPresented
            self.content = AnyView(content)
            guard isPresented, let parent = anchor?.window else {
                hide()
                return
            }
            let panel = self.panel ?? makePanel()
            panel.appearance = parent.effectiveAppearance
            if panel.parent !== parent {
                parent.addChildWindow(panel, ordered: .above)
                resignToken = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: parent, queue: .main) { _ in
                    MainActor.assumeIsolated { onResign() }
                }
            }
            reposition()
        }

        func reposition() {
            guard isPresented, let anchor, let window = anchor.window, let panel, let hosting else { return }
            let field = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let inset = Metrics.dropdownShadowRadius
            hosting.rootView = AnyView(content.frame(width: field.width + inset * 2))
            let size = hosting.fittingSize
            panel.setFrame(
                NSRect(x: field.minX - inset, y: field.minY - Metrics.space4 - size.height, width: size.width, height: size.height),
                display: true)
        }

        func tearDown() { hide() }

        private func makePanel() -> Panel {
            let hosting = HostingView(rootView: AnyView(EmptyView()))
            let panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.contentView = hosting
            self.panel = panel
            self.hosting = hosting
            return panel
        }

        private func hide() {
            if let resignToken { NotificationCenter.default.removeObserver(resignToken) }
            resignToken = nil
            guard let panel else { return }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }
}
