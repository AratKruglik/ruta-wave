import Observation
import SwiftUI

struct Toast {
    let message: LocalizedStringResource
    let undo: (@MainActor () -> Void)?
}

@MainActor @Observable
final class ToastCenter {
    private(set) var toast: Toast?
    @ObservationIgnored private(set) var dismissal: Task<Void, Never>?
    @ObservationIgnored private var isHeld = false
    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Void

    init(sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    var message: LocalizedStringResource? { toast?.message }

    /// A new toast replaces the visible one together with its Undo, so only the latest action can be undone.
    func show(_ message: LocalizedStringResource, undo: (@MainActor () -> Void)? = nil) {
        toast = Toast(message: message, undo: undo)
        scheduleDismissal()
    }

    /// Pointer or keyboard focus on the toast pauses dismissal; releasing restarts the full duration.
    func setHeld(_ held: Bool) {
        isHeld = held
        scheduleDismissal()
    }

    private func scheduleDismissal() {
        dismissal?.cancel()
        dismissal = nil
        guard let toast, !isHeld else { return }
        let duration = toast.undo == nil ? Motion.toastDuration : Motion.toastActionDuration
        dismissal = Task { [weak self, sleep] in
            await sleep(duration)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func undo() {
        guard let action = toast?.undo else { return }
        reset()
        action()
    }

    func reset() {
        dismissal?.cancel()
        toast = nil
    }
}

struct ToastView: View {
    let toast: Toast
    var onUndo: () -> Void = {}
    var onHold: (Bool) -> Void = { _ in }
    @State private var isHovered = false
    @FocusState private var isUndoFocused: Bool

    var body: some View {
        HStack(spacing: Metrics.space12) {
            Text(toast.message)
            if toast.undo != nil {
                Button("Undo", action: onUndo)
                    .buttonStyle(LinkButtonStyle())
                    .help("Undo")
                    .focused($isUndoFocused)
            }
        }
        .font(.rwBody)
        .foregroundStyle(.textPrimary)
        .padding(.horizontal, Metrics.space16)
        .padding(.vertical, Metrics.space12)
        .glassSurface(in: Capsule())
        .onHover { isHovered = $0 }
        .onChange(of: isHovered || isUndoFocused) { _, held in onHold(held) }
        .onDisappear { onHold(false) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
        .onChange(of: String(localized: toast.message), initial: true) { _, text in
            AccessibilityNotification.Announcement(text).post()
        }
    }
}

#Preview {
    ToastView(toast: Toast(message: "This track is unavailable", undo: {}))
        .padding()
        .background(.themeBase)
}
