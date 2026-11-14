import SwiftUI

struct SettingsView: View {
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var needsApproval = LoginItem.requiresApproval
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Toggle("Open at Login", isOn: $opensAtLogin)
                .onChange(of: opensAtLogin) { _, enabled in apply(enabled) }
            if needsApproval {
                Text("Allow SystemBack in System Settings › General › Login Items.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }

    private func apply(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        opensAtLogin = LoginItem.isEnabled
        needsApproval = LoginItem.requiresApproval
    }
}
