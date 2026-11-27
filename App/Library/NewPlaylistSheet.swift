import InnerTube
import SwiftUI

struct NewPlaylistSheet: View {
    let title: LocalizedStringKey
    let confirmTitle: LocalizedStringKey
    let showsPrivacy: Bool
    let isCreating: Bool
    let onCancel: () -> Void
    let onCreate: (NewPlaylistDraft) -> Void

    @State private var draft: NewPlaylistDraft

    init(
        title: LocalizedStringKey = "New playlist", confirmTitle: LocalizedStringKey = "Create", initial: NewPlaylistDraft = NewPlaylistDraft(),
        showsPrivacy: Bool = true, isCreating: Bool, onCancel: @escaping () -> Void, onCreate: @escaping (NewPlaylistDraft) -> Void
    ) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.showsPrivacy = showsPrivacy
        self.isCreating = isCreating
        self.onCancel = onCancel
        self.onCreate = onCreate
        _draft = State(initialValue: initial)
    }
    @FocusState private var isTitleFocused: Bool

    private static let privacies: [(PlaylistPrivacy, LocalizedStringKey)] = [
        (.public, "Public"), (.unlisted, "Unlisted"), (.private, "Private"),
    ]

    private var titleLength: Int { draft.title.trimmingCharacters(in: .whitespacesAndNewlines).count }
    private var isTooLong: Bool { titleLength > PlaylistEdit.maxTitleLength }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space16) {
            Text(title)
                .font(.rwShelfTitle)
                .foregroundStyle(.textPrimary)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Metrics.space4) {
                fieldLabel("Title")
                TextField("", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                    .font(.rwBody)
                    .controlSize(.large)
                    .focused($isTitleFocused)
                    .accessibilityLabel("Title")
                    .onSubmit(create)
                titleHint
            }
            VStack(alignment: .leading, spacing: Metrics.space4) {
                fieldLabel("Description")
                TextField("", text: $draft.description, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.rwBody)
                    .lineLimit(3...6)
                    .accessibilityLabel("Description")
            }
            if showsPrivacy {
                Picker("Privacy", selection: $draft.privacy) {
                    ForEach(Self.privacies, id: \.0) { privacy, title in Text(title).tag(privacy) }
                }
                .font(.rwBody)
            }
            HStack(spacing: Metrics.space12) {
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isValid || isCreating)
            }
        }
        .padding(Metrics.space24)
        .frame(width: 420)
        .onAppear { isTitleFocused = true }
    }

    private func fieldLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.rwCaption)
            .foregroundStyle(.textSecondary)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var titleHint: some View {
        if titleLength >= PlaylistEdit.maxTitleLength - 20 {
            HStack(spacing: Metrics.space8) {
                if isTooLong { Text("Titles can be up to \(PlaylistEdit.maxTitleLength) characters.") }
                Spacer(minLength: 0)
                Text(verbatim: "\(titleLength)/\(PlaylistEdit.maxTitleLength)").monospacedDigit()
            }
            .font(.rwCaption)
            .foregroundStyle(.textSecondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Titles can be up to \(PlaylistEdit.maxTitleLength) characters."))
            .accessibilityValue(Text(verbatim: "\(titleLength)"))
        }
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
