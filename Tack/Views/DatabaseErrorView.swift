import SwiftUI

/// Shown in place of the app when the production model container can't be opened (M7). Minimal by
/// design: state the problem, no recovery beyond quitting and retrying. Never appears under
/// `--uitest` (test-store failures hard-crash instead, to surface loudly in CI).
struct DatabaseErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Tack couldn't open its database")
                .font(.title2.weight(.semibold))
            // The human sentence leads (quit-and-retry IS the intended recovery path); the raw
            // error detail is still there for support, demoted below it.
            Text("Quit and reopen Tack to try again. Your boards are stored safely on disk.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Quit Tack") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(minWidth: 360, minHeight: 260)
    }
}
