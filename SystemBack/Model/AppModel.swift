import AppKit
import Foundation
import Observation
import OSLog
import SystemBackCore

/// Estado de la app. Vive en el main actor; el trabajo pesado va a `BackgroundWork`.
@Observable
final class AppModel {
    struct Activity: Equatable {
        enum Kind: Equatable { case backup(jobID: BackupJob.ID), restore }
        var kind: Kind
        var title: String
        /// `nil` mientras no se conoce el total (barra indeterminada).
        var fraction: Double?
        var detail: String?
    }

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var message: String
        /// Si existe, el aviso ofrece «Mostrar en Finder».
        var revealURL: URL?
        /// Carpeta con bookmark que da acceso a `revealURL` (el sandbox lo exige para mostrarla en Finder).
        var revealScope: FolderReference?
    }

    /// Línea del panel Actividad (equivalente a la consola de la herramienta original).
    struct LogEntry: Identifiable, Equatable {
        enum Level { case info, success, warning, error }
        let id = UUID()
        let date = Date.now
        var level: Level
        var text: String
    }

    enum BackupAction: Equatable {
        case full, incremental, replaceLatest
    }

    static let logLimit = 500

    private(set) var jobs: [BackupJob] = []
    private(set) var archives: [BackupJob.ID: [ArchiveInfo]] = [:]
    private(set) var activity: Activity?
    private(set) var log: [LogEntry] = []
    var notice: Notice?

    private let store: JobStore?
    private var runningTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.efjdev.systemback", category: "model")

    init(store: JobStore? = try? JobStore.standard()) {
        self.store = store
        do {
            jobs = try store?.load() ?? []
        } catch {
            logger.error("No se pudieron cargar los trabajos: \(error.localizedDescription, privacy: .public)")
            notice = Notice(title: String(localized: "Couldn’t Load Backup Jobs"), message: error.localizedDescription)
        }
    }

    var isBusy: Bool { activity != nil }

    // MARK: - Trabajos

    func addJob(name: String, source: URL, destination: URL) throws {
        let job = BackupJob(name: name, source: try FolderReference.make(from: source),
                            destination: try FolderReference.make(from: destination))
        jobs.append(job)
        persist()
        append(.info, String(localized: "Job “\(name)” created."))
    }

    func removeJob(_ id: BackupJob.ID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        jobs.removeAll { $0.id == id }
        archives[id] = nil
        persist()
        append(.info, String(localized: "Job “\(job.name)” deleted. Its backup files were kept."))
    }

    // MARK: - Catálogo

    func refreshArchives(jobID: BackupJob.ID) async {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        do {
            archives[jobID] = try await BackgroundWork.listArchives(of: job)
        } catch {
            archives[jobID] = []
            append(.warning, String(localized: "Couldn’t read the backups of “\(job.name)”: \(Self.describe(error))"))
        }
    }

    func moveToTrash(_ archive: ArchiveInfo, jobID: BackupJob.ID) {
        guard !isBusy, let job = jobs.first(where: { $0.id == jobID }) else { return }
        Task {
            do {
                let location = try await BackgroundWork.moveToTrash(archive, of: job)
                append(.info, String(localized: "\(archive.name) moved to the Trash."))
                if let location { append(.info, String(localized: "Location: \(location.path)")) }
            } catch {
                append(.error, Self.describe(error))
                notice = Notice(title: String(localized: "Couldn’t Move to Trash"), message: Self.describe(error))
            }
            await refreshArchives(jobID: jobID)
        }
    }

    // MARK: - Backup

    func startBackup(jobID: BackupJob.ID, action: BackupAction) {
        guard !isBusy, let job = jobs.first(where: { $0.id == jobID }) else { return }
        let mode: BackgroundWork.BackupMode
        let title: String
        switch action {
        case .full:
            mode = .full
            title = String(localized: "Backing up “\(job.name)”")
        case .replaceLatest:
            mode = .replaceLatest
            title = String(localized: "Replacing the last backup of “\(job.name)”")
        case .incremental:
            guard let last = job.lastBackupDate else { return }
            mode = .incremental(since: last)
            title = String(localized: "Backing up changes in “\(job.name)”")
        }

        activity = Activity(kind: .backup(jobID: jobID), title: title)
        append(.info, title)
        let (stream, continuation) = AsyncStream<BackupProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))

        runningTask = Task {
            await Notifications.requestAuthorizationIfNeeded()
            let progressTask = Task { for await value in stream { show(value) } }
            defer {
                progressTask.cancel()
                activity = nil
                runningTask = nil
            }
            do {
                let output = try await BackgroundWork.backup(job, mode: mode, progress: continuation)
                apply(output, to: jobID, mode: mode)
            } catch is CancellationError {
                append(.warning, String(localized: "Backup cancelled. No partial file was left."))
            } catch {
                logger.error("Backup fallido: \(error.localizedDescription, privacy: .public)")
                append(.error, Self.describe(error))
                notice = Notice(title: String(localized: "Backup Failed"), message: Self.describe(error))
            }
            await refreshArchives(jobID: jobID)
        }
    }

    private func show(_ progress: BackupProgress) {
        switch progress.phase {
        case .scanning:
            activity?.fraction = nil
            activity?.detail = String(localized: "Scanning files…")
        case .archiving:
            activity?.fraction = progress.fractionCompleted
            activity?.detail = progress.currentPath
        case .finishing:
            activity?.fraction = 1
            activity?.detail = String(localized: "Finishing archive…")
        }
    }

    private func apply(_ output: BackgroundWork.BackupOutput, to jobID: BackupJob.ID, mode: BackgroundWork.BackupMode) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        if let renewed = output.renewedSource { jobs[index].source = renewed }
        if let renewed = output.renewedDestination { jobs[index].destination = renewed }

        switch output.outcome {
        case .noChanges:
            append(.info, String(localized: "No changes since the last backup. No file was created."))
            notice = Notice(title: String(localized: "No Changes"),
                            message: String(localized: "Nothing changed since the last backup."))
        case let .created(result):
            let recordKind: BackupRecord.Kind = if case .incremental = mode { .incremental } else { .full }
            jobs[index].record(BackupRecord(date: .now, kind: recordKind, archiveName: result.archiveURL.lastPathComponent,
                                            fileCount: result.fileCount, contentBytes: result.contentBytes,
                                            archiveBytes: result.archiveBytes))
            let size = Int64(result.archiveBytes).formatted(.byteCount(style: .file))
            append(.success, String(localized: "\(result.archiveURL.lastPathComponent) created: \(result.fileCount) files, \(size)."))
            if let replaced = output.replaced {
                append(.info, String(localized: "Previous backup \(replaced.name) moved to the Trash."))
                if let location = output.replacedTrashLocation {
                    append(.info, String(localized: "Location: \(location.path)"))
                }
            } else if mode == .replaceLatest, output.replaceFailure == nil {
                append(.warning, String(localized: "There was no previous backup to replace."))
            }
            if let failure = output.replaceFailure {
                let message = String(localized: "The new backup was saved, but the previous one couldn’t be moved to the Trash (\(failure)). Delete it from the Backups list or in Finder.")
                append(.warning, message)
                notice = Notice(title: String(localized: "Previous Backup Kept"), message: message)
            }
            Notifications.post(title: String(localized: "Backup Complete"),
                               body: String(localized: "\(jobs[index].name): \(result.fileCount) files saved."))
        }
        persist()
    }

    // MARK: - Restauración

    func startRestore(_ archive: ArchiveInfo, jobID: BackupJob.ID, intoParent parent: URL) {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        runRestore(named: archive.name, cancelled: Self.newFolderCancelled) { continuation in
            Self.summary(of: try await BackgroundWork.restore(archive, of: job, intoParent: parent, progress: continuation))
        }
    }

    func startRestore(archive: URL, intoParent parent: URL) {
        runRestore(named: archive.lastPathComponent, cancelled: Self.newFolderCancelled) { continuation in
            Self.summary(of: try await BackgroundWork.restore(archive: archive, intoParent: parent, progress: continuation))
        }
    }

    /// Restaura sobre la carpeta de origen del trabajo (lo sustituido va a la Papelera).
    func startRestoreInPlace(_ archive: ArchiveInfo, jobID: BackupJob.ID) {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        let cancelled = String(localized: "Restore cancelled. Files already restored were kept; replaced items are in the Trash.")
        runRestore(named: archive.name, cancelled: cancelled) { continuation in
            let result = try await BackgroundWork.restoreInPlace(archive, of: job, progress: continuation)
            var message = String(localized: "\(result.restoredFiles) files restored to “\(result.destination.lastPathComponent)”.")
            message += " " + String(localized: "\(result.unchangedFiles) files were already up to date.")
            if result.replacedItems > 0 {
                message += " " + String(localized: "\(result.replacedItems) replaced items were moved to the Trash.")
            }
            if !result.skippedEntries.isEmpty {
                message += " " + String(localized: "\(result.skippedEntries.count) links or special items were skipped.")
            }
            return RestoreSummary(message: message, location: result.destination, scope: job.source)
        }
    }

    private struct RestoreSummary: Sendable {
        var message: String
        var location: URL
        var scope: FolderReference?
    }

    private static var newFolderCancelled: String {
        String(localized: "Restore cancelled. The partially restored folder was removed.")
    }

    private static func summary(of result: RestoreResult) -> RestoreSummary {
        var message = String(localized: "\(result.restoredFiles) files restored to “\(result.destination.lastPathComponent)”.")
        if !result.skippedEntries.isEmpty {
            message += " " + String(localized: "\(result.skippedEntries.count) links or special items were skipped.")
        }
        return RestoreSummary(message: message, location: result.destination, scope: nil)
    }

    private func runRestore(
        named name: String,
        cancelled: String,
        _ work: @escaping (AsyncStream<Double>.Continuation) async throws -> RestoreSummary
    ) {
        guard !isBusy else { return }
        let title = String(localized: "Restoring \(name)")
        activity = Activity(kind: .restore, title: title, fraction: 0)
        append(.info, title)
        let (stream, continuation) = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))

        runningTask = Task {
            let progressTask = Task { for await value in stream { activity?.fraction = value } }
            defer {
                progressTask.cancel()
                activity = nil
                runningTask = nil
            }
            do {
                let summary = try await work(continuation)
                append(.success, summary.message)
                append(.info, String(localized: "Location: \(summary.location.path)"))
                notice = Notice(title: String(localized: "Restore Complete"), message: summary.message,
                                revealURL: summary.location, revealScope: summary.scope)
            } catch is CancellationError {
                append(.warning, cancelled)
            } catch {
                append(.error, Self.describe(error))
                notice = Notice(title: String(localized: "Restore Failed"), message: Self.describe(error))
            }
        }
    }

    /// «Mostrar en Finder» dentro del sandbox: hay que tener abierto el acceso a la carpeta
    /// para que el sistema pueda pasar la ruta a Finder.
    func reveal(_ url: URL, scope: FolderReference?) {
        guard let scope, let scopeURL = try? scope.resolve().url else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        withSecurityScopedAccess(to: scopeURL) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func cancelActivity() {
        runningTask?.cancel()
    }

    // MARK: - Registro

    func clearLog() {
        log.removeAll()
    }

    private func append(_ level: LogEntry.Level, _ text: String) {
        log.append(LogEntry(level: level, text: text))
        if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
    }

    // MARK: - Utilidades

    private func persist() {
        do {
            try store?.save(jobs)
        } catch {
            logger.error("No se pudieron guardar los trabajos: \(error.localizedDescription, privacy: .public)")
            notice = Notice(title: String(localized: "Couldn’t Save Changes"), message: error.localizedDescription)
        }
    }

    /// Mensaje que dice qué pasó y qué hacer.
    static func describe(_ error: any Error) -> String {
        switch error {
        case BackupError.sourceNotADirectory:
            String(localized: "The source folder is no longer available. Create the job again with the new location.")
        case RestoreError.folderNotFound, BackgroundWork.InPlaceError.sourceInTrash:
            String(localized: "The original folder no longer exists. Use Restore… to restore into a new folder.")
        case RestoreError.destinationNotEmpty:
            String(localized: "The destination folder isn’t empty. Choose another location.")
        case ArchiveError.unsafeEntryPath(let path):
            String(localized: "The archive contains an unsafe path (\(path)). Nothing was restored.")
        case ArchiveError.checksumMismatch, ArchiveError.corrupted, ArchiveError.truncatedTar, ArchiveError.invalidTarHeader:
            String(localized: "The archive is damaged or incomplete. Nothing was restored.")
        case ArchiveError.notGzip:
            String(localized: "This file isn’t a .tar.gz backup.")
        default:
            error.localizedDescription
        }
    }
}
