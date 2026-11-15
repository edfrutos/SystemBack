import SwiftUI
import SystemBackCore

struct JobDetailView: View {
    @Environment(AppModel.self) private var model
    let job: BackupJob
    /// Backup pendiente de confirmar para restaurar en la carpeta de origen.
    @State private var pendingInPlace: BackupEntry?

    private var archives: [ArchiveInfo]? { model.archives[job.id] }

    /// Backups locales (con su copia en Drive, si la hay) y los que solo están en Drive, por fecha.
    private var entries: [BackupEntry]? {
        guard let archives else { return nil }
        let local = archives.map { BackupEntry.local($0, driveCopy: model.driveCopy(of: $0, jobID: job.id)) }
        let remote = model.driveOnlyArchives(jobID: job.id).map(BackupEntry.remote)
        return (local + remote).sorted { $0.date > $1.date }
    }

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
                Toggle(isOn: Binding(
                    get: { job.uploadsToDrive && model.isDriveConnected },
                    set: { model.setUploadsToDrive($0, jobID: job.id) }
                )) {
                    Label("Upload New Backups to Google Drive", systemImage: "icloud.and.arrow.up")
                }
                .disabled(!model.isDriveConnected)
                .help(model.isDriveConnected
                      ? Text("After each backup, upload a copy to Google Drive")
                      : Text("Connect Google Drive in Settings to use this option"))
            }

            Section("Actions") {
                HStack(alignment: .top, spacing: 12) {
                    ActionCard(title: "Back Up Now",
                               detail: "Save a complete copy of the folder.",
                               symbol: "externaldrive.fill.badge.plus", tint: Theme.full) {
                        model.startBackup(jobID: job.id, action: .full)
                    }
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
                if let entries {
                    if entries.isEmpty {
                        Text("No backups in the destination folder yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(entries) { entry in
                        switch entry {
                        case let .local(archive, driveCopy):
                            ArchiveRow(
                                archive: archive,
                                driveCopy: driveCopy,
                                canUpload: model.isDriveConnected,
                                upload: { model.startUpload(archive, jobID: job.id) },
                                trashDriveCopy: { if let driveCopy { model.trashInDrive(driveCopy, jobID: job.id) } },
                                restoreInPlace: { pendingInPlace = entry },
                                restore: { Task { await restore(entry) } },
                                reveal: { model.reveal(archive.url, scope: job.destination) },
                                trash: { model.moveToTrash(archive, jobID: job.id) }
                            )
                        case let .remote(remote):
                            DriveArchiveRow(
                                archive: remote,
                                download: { model.startDownload(remote, jobID: job.id) },
                                restoreInPlace: { pendingInPlace = entry },
                                restore: { Task { await restore(entry) } },
                                trash: { model.trashInDrive(remote, jobID: job.id) }
                            )
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
                if let issue = model.driveIssues[job.id] {
                    HStack {
                        Label(issue, systemImage: "exclamationmark.icloud")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Try Again") { Task { await model.refreshDrive(jobID: job.id) } }
                    }
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
        ) { entry in
            Button("Restore to Original Folder") {
                switch entry {
                case let .local(archive, _): model.startRestoreInPlace(archive, jobID: job.id)
                case let .remote(remote): model.startRestoreInPlaceFromDrive(remote, jobID: job.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            if case .remote = entry {
                Text("The backup is downloaded to the destination folder first. Files from \(entry.name) will be copied into \(job.source.displayPath). Files with different content are moved to the Trash first. Files that aren’t in the backup are left as they are.")
            } else {
                Text("Files from \(entry.name) will be copied into \(job.source.displayPath). Files with different content are moved to the Trash first. Files that aren’t in the backup are left as they are.")
            }
        }
    }

    private func restore(_ entry: BackupEntry) async {
        let parent = await FolderPicker.chooseFolder(
            message: String(localized: "Choose where to restore. A new folder will be created there."),
            prompt: String(localized: "Restore Here")
        )
        guard let parent else { return }
        switch entry {
        case let .local(archive, _): model.startRestore(archive, jobID: job.id, intoParent: parent)
        case let .remote(remote): model.startRestoreFromDrive(remote, jobID: job.id, intoParent: parent)
        }
    }

    private var lastBackupText: String {
        if let date = job.lastBackupDate {
            String(localized: "Last backup \(date.formatted(.relative(presentation: .named)))")
        } else {
            String(localized: "Never backed up")
        }
    }
}

/// Fila de la lista de backups: archivo local (con o sin copia en Drive) o solo en Drive.
private enum BackupEntry: Identifiable {
    case local(ArchiveInfo, driveCopy: RemoteArchive?)
    case remote(RemoteArchive)

    var id: String {
        switch self {
        case let .local(archive, _): "local:" + archive.url.path
        case let .remote(remote): "drive:" + remote.id
        }
    }

    var date: Date {
        switch self {
        case let .local(archive, _): archive.date
        case let .remote(remote): remote.date
        }
    }

    var name: String {
        switch self {
        case let .local(archive, _): archive.name
        case let .remote(remote): remote.name
        }
    }
}

private struct ArchiveRow: View {
    @Environment(AppModel.self) private var model
    let archive: ArchiveInfo
    let driveCopy: RemoteArchive?
    let canUpload: Bool
    let upload: () -> Void
    let trashDriveCopy: () -> Void
    let restoreInPlace: () -> Void
    let restore: () -> Void
    let reveal: () -> Void
    let trash: () -> Void

    private var inDrive: Bool { driveCopy != nil }

    var body: some View {
        HStack(spacing: 10) {
            ArchiveSummary(kind: archive.kind, date: archive.date, name: archive.name)
            Spacer()
            Badge(title: "Local", symbol: "internaldrive", tint: .blue)
                .help("Saved in the destination folder on this Mac")
            if inDrive {
                Badge(title: "Drive", symbol: "icloud", tint: .indigo)
                    .help("A copy is in your Google Drive")
            }
            SizeText(bytes: archive.bytes)
            // Acciones visibles (también en el menú contextual), sin depender de un menú desplegable.
            HStack(spacing: 2) {
                if canUpload && !inDrive {
                    Button("Upload to Google Drive", systemImage: "icloud.and.arrow.up", action: upload)
                        .help("Upload a copy of this backup to Google Drive")
                }
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
        if canUpload && !inDrive {
            Button("Upload to Google Drive", systemImage: "icloud.and.arrow.up", action: upload)
            Divider()
        }
        Button("Restore to Original Folder…", systemImage: "arrow.uturn.backward", action: restoreInPlace)
        Button("Restore…", systemImage: "folder.badge.plus", action: restore)
        Button("Show in Finder", systemImage: "magnifyingglass", action: reveal)
        Divider()
        Button("Move to Trash", systemImage: "trash", role: .destructive, action: trash)
        if inDrive {
            Button("Move Drive Copy to the Google Drive Trash", systemImage: "icloud.slash", role: .destructive,
                   action: trashDriveCopy)
        }
    }
}

/// Backup que solo está en Google Drive: se descarga a la carpeta de destino para restaurarlo.
private struct DriveArchiveRow: View {
    @Environment(AppModel.self) private var model
    let archive: RemoteArchive
    let download: () -> Void
    let restoreInPlace: () -> Void
    let restore: () -> Void
    let trash: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ArchiveSummary(kind: archive.kind, date: archive.date, name: archive.name)
            Spacer()
            Badge(title: "Drive", symbol: "icloud", tint: .indigo)
                .help("Only in your Google Drive. It isn’t in the destination folder on this Mac")
            SizeText(bytes: archive.bytes)
            HStack(spacing: 2) {
                Button("Download to This Mac", systemImage: "icloud.and.arrow.down", action: download)
                    .help("Download this backup to the destination folder")
                Button("Restore to Original Folder…", systemImage: "arrow.uturn.backward", action: restoreInPlace)
                    .help("Download, then restore missing or changed files into the original folder")
                Button("Restore…", systemImage: "folder.badge.plus", action: restore)
                    .help("Download, then restore this backup into a new folder")
                Button("Move to the Google Drive Trash", systemImage: "trash", action: trash)
                    .help("Move this backup to the Google Drive trash")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(model.isBusy)
        }
        .contextMenu {
            Button("Download to This Mac", systemImage: "icloud.and.arrow.down", action: download)
            Divider()
            Button("Restore to Original Folder…", systemImage: "arrow.uturn.backward", action: restoreInPlace)
            Button("Restore…", systemImage: "folder.badge.plus", action: restore)
            Divider()
            Button("Move to the Google Drive Trash", systemImage: "trash", role: .destructive, action: trash)
        }
    }
}

/// Tipo, fecha y nombre de un backup (común a las filas locales y de Drive).
private struct ArchiveSummary: View {
    let kind: ArchiveInfo.Kind
    let date: Date
    let name: String

    var body: some View {
        Badge(title: Theme.label(for: kind), symbol: Theme.symbol(for: kind), tint: Theme.tint(for: kind))
            .help(Theme.help(for: kind))
            .frame(width: 96, alignment: .leading)
        VStack(alignment: .leading, spacing: 2) {
            Text(date, format: .dateTime.day().month().year().hour().minute())
            Text(name)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct SizeText: View {
    let bytes: UInt64

    var body: some View {
        Text(Int64(bytes), format: .byteCount(style: .file))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(minWidth: 70, alignment: .trailing)
    }
}
