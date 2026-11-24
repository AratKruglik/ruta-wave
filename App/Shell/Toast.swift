import Observation
import SwiftUI

struct Toast {
    let message: LocalizedStringResource
    let undo: (@MainActor () -> Void)?
}

@MainActor @Observable
final class ToastCenter {
    private(set) var toast: Toast?
    @ObservationIgnored private var dismissal: Task<Void, Never>?

    var message: LocalizedStringResource? { toast?.message }

    /// A new toast replaces the visible one together with its Undo, so only the latest action can be undone.
    func show(_ message: LocalizedStringResource, undo: (@MainActor () -> Void)? = nil) {
        dismissal?.cancel()
        toast = Toast(message: message, undo: undo)
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: Motion.toastDuration)
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

    var body: some View {
        HStack(spacing: Metrics.space12) {
            Text(toast.message)
            if toast.undo != nil {
                Button("Undo", action: onUndo)
                    .buttonStyle(.plain)
                    .foregroundStyle(.accentLink)
                    .help("Undo")
            }
        }
        .font(.rwBody)
        .foregroundStyle(.textPrimary)
        .padding(.horizontal, Metrics.space16)
        .padding(.vertical, Metrics.space12)
        .glassSurface(in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview {
    ToastView(toast: Toast(message: "This track is unavailable", undo: {}))
        .padding()
        .background(.themeBase)
}
