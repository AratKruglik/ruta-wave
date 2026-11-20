import Observation
import SwiftUI

@MainActor @Observable
final class ToastCenter {
    private(set) var message: LocalizedStringResource?
    @ObservationIgnored private var dismissal: Task<Void, Never>?

    func show(_ message: LocalizedStringResource) {
        dismissal?.cancel()
        self.message = message
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: Motion.toastDuration)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

struct ToastView: View {
    let message: LocalizedStringResource

    var body: some View {
        Text(message)
            .font(.rwBody)
            .foregroundStyle(.textPrimary)
            .padding(.horizontal, Metrics.space16)
            .padding(.vertical, Metrics.space12)
            .background(.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.radiusCard))
            .background(.themeBase, in: RoundedRectangle(cornerRadius: Metrics.radiusCard))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview {
    ToastView(message: "This track is unavailable")
        .padding()
        .background(.themeBase)
}
