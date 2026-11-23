import InnerTube
import SwiftUI

struct NewPlaylistSheet: View {
    let isCreating: Bool
    let onCancel: () -> Void
    let onCreate: (NewPlaylistDraft) -> Void

    @State private var draft = NewPlaylistDraft()
    @FocusState private var isTitleFocused: Bool

    private static let privacies: [(PlaylistPrivacy, LocalizedStringKey)] = [
        (.public, "Public"), (.unlisted, "Unlisted"), (.private, "Private"),
    ]

    private var isTooLong: Bool { draft.title.trimmingCharacters(in: .whitespacesAndNewlines).count > PlaylistEdit.maxTitleLength }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space16) {
            Text("New playlist")
                .font(.rwShelfTitle)
                .foregroundStyle(.textPrimary)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Metrics.space4) {
                TextField("Title", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                    .font(.rwBody)
                    .focused($isTitleFocused)
                    .accessibilityLabel("Title")
                    .onSubmit(create)
                if isTooLong {
                    Text("Titles can be up to \(PlaylistEdit.maxTitleLength) characters.")
                        .font(.rwCaption)
                        .foregroundStyle(.textSecondary)
                }
            }
            TextField("Description (optional)", text: $draft.description, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.rwBody)
                .lineLimit(3...6)
                .accessibilityLabel("Description")
            Picker("Privacy", selection: $draft.privacy) {
                ForEach(Self.privacies, id: \.0) { privacy, title in Text(title).tag(privacy) }
            }
            .font(.rwBody)
            HStack(spacing: Metrics.space12) {
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isValid || isCreating)
            }
        }
        .padding(Metrics.space24)
        .frame(width: 420)
        .onAppear { isTitleFocused = true }
    }

    private func create() {
        guard draft.isValid, !isCreating else { return }
        onCreate(draft)
    }
}

#Preview {
    NewPlaylistSheet(isCreating: false, onCancel: {}, onCreate: { _ in })
        .background(.themeBase)
}
