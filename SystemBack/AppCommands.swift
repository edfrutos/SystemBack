import SwiftUI
import SystemBackCore

/// Acciones de la ventana principal que la barra de menús necesita (HIG: todo lo de la barra
/// de herramientas también va en un menú, con su atajo).
struct MainWindowActions {
    var selectedJobID: BackupJob.ID?
    var showsActivity: Bool
    var newJob: () -> Void
    var restoreFromFile: () -> Void
    var toggleActivity: () -> Void
}

extension FocusedValues {
    @Entry var mainWindowActions: MainWindowActions?
}

struct AppCommands: Commands {
    let model: AppModel
    @FocusedValue(\.mainWindowActions) private var actions

    private var job: BackupJob? {
        guard let id = actions?.selectedJobID else { return nil }
        return model.jobs.first { $0.id == id }
    }

    private var hasArchives: Bool {
        guard let job else { return false }
        return !(model.archives[job.id]?.isEmpty ?? true)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Backup Job…") { actions?.newJob() }
                .keyboardShortcut("n")
                .disabled(actions == nil || model.isBusy)
            Button("Restore from File…") { actions?.restoreFromFile() }
                .keyboardShortcut("o")
                .disabled(actions == nil || model.isBusy)
        }

        CommandGroup(before: .sidebar) {
            // Ternario tipado: con literales sueltos sería String y no se traduciría.
            Button(actions?.showsActivity == true ? LocalizedStringKey("Hide Activity") : LocalizedStringKey("Show Activity")) {
                actions?.toggleActivity()
            }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(actions == nil)
            Divider()
        }

        CommandMenu("Backup") {
            Button("Back Up Now") { start(.full) }
                .keyboardShortcut("b")
                .disabled(job == nil || model.isBusy)
            Button("Replace Last Backup") { start(.replaceLatest) }
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(!hasArchives || model.isBusy)
            Button("Back Up Changes") { start(.incremental) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(job?.lastBackupDate == nil || model.isBusy)
            Divider()
            Button("Refresh Backups") {
                if let job { Task { await model.refreshArchives(jobID: job.id) } }
            }
            .keyboardShortcut("r")
            .disabled(job == nil)
        }
    }

    private func start(_ action: AppModel.BackupAction) {
        guard let job else { return }
        model.startBackup(jobID: job.id, action: action)
    }
}
