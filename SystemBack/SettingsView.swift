import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var language = AppLanguage.selected
    @State private var appearance = AppAppearance.selected
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

                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .onChange(of: appearance) { _, newValue in AppAppearance.select(newValue) }
            }

            Section {
                if model.isDriveConnected {
                    LabeledContent("Google Drive") {
                        if let email = model.driveEmail {
                            Text(verbatim: email).textSelection(.enabled)
                        } else {
                            Text("Connected")
                        }
                    }
                    Button("Disconnect Google Drive", role: .destructive) { model.disconnectDrive() }
                } else {
                    LabeledContent("Google Drive") {
                        Button("Connect Google Drive…") { model.connectDrive() }
                            .disabled(model.isConnectingDrive)
                    }
                }
            } header: {
                Text("Google Drive")
            } footer: {
                Text("SystemBack can only see the files it creates in your Drive. Backups go directly from this Mac to your account.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
        .task { await model.loadDriveAccount() }
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
