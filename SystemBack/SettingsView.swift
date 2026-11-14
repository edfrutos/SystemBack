import SwiftUI

struct SettingsView: View {
    @State private var language = AppLanguage.selected
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var needsApproval = LoginItem.requiresApproval
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(verbatim: option.displayName).tag(option)
                    }
                }
                .onChange(of: language) { _, newValue in AppLanguage.select(newValue) }

                if language != AppLanguage.atLaunch {
                    HStack {
                        Text("The new language is applied after restarting SystemBack.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart Now") { AppLanguage.relaunch() }
                    }
                }
            }

            Section {
                Toggle("Open at Login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, enabled in applyLogin(enabled) }
                if needsApproval {
                    Text("Allow SystemBack in System Settings › General › Login Items.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }

    private func applyLogin(_ enabled: Bool) {
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
