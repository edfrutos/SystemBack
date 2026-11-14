import SwiftUI
import SystemBackCore

struct JobDetailView: View {
    @Environment(AppModel.self) private var model
    let job: BackupJob
    /// Backup pendiente de confirmar para restaurar en la carpeta de origen.
    @State private var pendingInPlace: ArchiveInfo?

    private var archives: [ArchiveInfo]? { model.archives[job.id] }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(job.source.displayPath).textSelection(.enabled)
                } label: {
                    Label("Source", systemImage: "folder")
                }
                LabeledContent {
                    Text(job.destination.displayPath).textSelection(.enabled)
                } label: {
                    Label("Destination", systemImage: "externaldrive")
                }
            }

            Section("Actions") {
                HStack(alignment: .top, spacing: 12) {
                    ActionCard(title: "Back Up Now",
                               detail: "Save a complete copy of the folder.",
                               symbol: "externaldrive.fill.badge.plus", tint: Theme.full) {
                        model.startBackup(jobID: job.id, action: .full)
                    }
                    .keyboardShortcut("b", modifiers: .command)
                    .help("Save a complete copy of the folder (⌘B)")

                    ActionCard(title: "Replace Last Backup",
                               detail: "Save a complete copy and move the previous one to the Trash.",
                               symbol: "arrow.triangle.2.circlepath", tint: Theme.replace) {
                        model.startBackup(jobID: job.id, action: .replaceLatest)
                    }
                    .disabled(archives?.isEmpty ?? true)
                    .help(archives?.isEmpty ?? true
                          ? Text("Available after the first backup")
                          : Text("Save a complete copy and move the previous one to the Trash."))

                    ActionCard(title: "Back Up Changes",
                               detail: "Save only files modified since the last backup.",
                               symbol: "plus.square.on.square", tint: Theme.incremental) {
                        model.startBackup(jobID: job.id, action: .incremental)
                    }
                    .disabled(job.lastBackupDate == nil)
                    .help(job.lastBackupDate == nil
                          ? Text("Available after the first backup")
                          : Text("Save only files modified since the last backup."))
                }
                .disabled(model.isBusy)
                .padding(.vertical, 4)
            }

            Section {
                if let archives {
                    if archives.isEmpty {
                        Text("No backups in the destination folder yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(archives) { archive in
                        ArchiveRow(
                            archive: archive,
                            restoreInPlace: { pendingInPlace = archive },
                            restore: { Task { await restore(archive) } },
                            reveal: { model.reveal(archive.url, scope: job.destination) },
                            trash: { model.moveToTrash(archive, jobID: job.id) }
                        )
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } header: {
                HStack {
                    Text("Backups")
                    Spacer()
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await model.refreshArchives(jobID: job.id) }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Refresh the list of backups")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(job.name)
        .navigationSubtitle(lastBackupText)
        .task(id: job.id) { await model.refreshArchives(jobID: job.id) }
        .confirmationDialog(
            "Restore to the Original Folder?",
            isPresented: Binding(get: { pendingInPlace != nil }, set: { if !$0 { pendingInPlace = nil } }),
            presenting: pendingInPlace
        ) { archive in
            Button("Restore to Original Folder") { model.startRestoreInPlace(archive, jobID: job.id) }
            Button("Cancel", role: .cancel) {}
        } message: { archive in
            Text("Files from \(archive.name) will be copied into \(job.source.displayPath). Files with different content are moved to the Trash first. Files that aren’t in the backup are left as they are.")
        }
    }

    private func restore(_ archive: ArchiveInfo) async {
        let parent = await FolderPicker.chooseFolder(
            message: String(localized: "Choose where to restore. A new folder will be created there."),
            prompt: String(localized: "Restore Here")
        )
        guard let parent else { return }
        model.startRestore(archive, jobID: job.id, intoParent: parent)
    }

    private var lastBackupText: String {
        if let date = job.lastBackupDate {
            String(localized: "Last backup \(date.formatted(.relative(presentation: .named)))")
        } else {
            String(localized: "Never backed up")
        }
    }
}

private struct ArchiveRow: View {
    @Environment(AppModel.self) private var model
    let archive: ArchiveInfo
    let restoreInPlace: () -> Void
    let restore: () -> Void
    let reveal: () -> Void
    let trash: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Badge(title: Theme.label(for: archive.kind), symbol: Theme.symbol(for: archive.kind),
                  tint: Theme.tint(for: archive.kind))
                .help(Theme.help(for: archive.kind))
                .frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(archive.date, format: .dateTime.day().month().year().hour().minute())
                Text(archive.name)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Badge(title: "Local", symbol: "internaldrive", tint: .blue)
                .help("Saved in the destination folder on this Mac")
            Text(Int64(archive.bytes), format: .byteCount(style: .file))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .trailing)
            // Acciones visibles (también en el menú contextual), sin depender de un menú desplegable.
            HStack(spacing: 2) {
                Button("Restore to Original Folder…", systemImage: "arrow.uturn.backward", action: restoreInPlace)
                    .help("Restore missing or changed files into the original folder")
                Button("Restore…", systemImage: "folder.badge.plus", action: restore)
                    .help("Restore this backup into a new folder")
                Button("Show in Finder", systemImage: "magnifyingglass", action: reveal)
                    .help("Show in Finder")
                Button("Move to Trash", systemImage: "trash", action: trash)
                    .help("Move this backup to the Trash")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(model.isBusy)
        }
        .contextMenu { actions }
    }

    @ViewBuilder private var actions: some View {
        Button("Restore to Original Folder…", systemImage: "arrow.uturn.backward", action: restoreInPlace)
        Button("Restore…", systemImage: "folder.badge.plus", action: restore)
        Button("Show in Finder", systemImage: "magnifyingglass", action: reveal)
        Divider()
        Button("Move to Trash", systemImage: "trash", role: .destructive, action: trash)
    }
}
