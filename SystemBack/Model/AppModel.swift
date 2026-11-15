import AppKit
import Foundation
import Observation
import OSLog
import SystemBackCore

/// Estado de la app. Vive en el main actor; el trabajo pesado va a `BackgroundWork`.
@Observable
final class AppModel {
    struct Activity: Equatable {
        enum Kind: Equatable { case backup(jobID: BackupJob.ID), restore, upload, download }
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

    /// Google Drive: estado de la conexión y backups de cada trabajo en su carpeta de Drive.
    private(set) var isDriveConnected = GoogleSession.isConnected
    private(set) var driveEmail: String?
    private(set) var isConnectingDrive = false
    private(set) var driveArchives: [BackupJob.ID: [RemoteArchive]] = [:]

    private let store: JobStore?
    private var runningTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.edefrutos.systemback", category: "model")

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
        await refreshDrive(jobID: jobID)
    }

    func refreshDrive(jobID: BackupJob.ID) async {
        guard isDriveConnected, let job = jobs.first(where: { $0.id == jobID }) else {
            driveArchives[jobID] = nil
            return
        }
        do {
            driveArchives[jobID] = try await BackgroundWork.listDrive(of: job)
        } catch {
            driveArchives[jobID] = nil
            handleDriveError(error, context: String(localized: "Couldn’t read Google Drive"))
        }
    }

    /// Copia en Drive del backup local (mismo nombre), si existe.
    func driveCopy(of archive: ArchiveInfo, jobID: BackupJob.ID) -> RemoteArchive? {
        driveArchives[jobID]?.first { $0.name == archive.name }
    }

    /// Backups que están en Drive pero no en la carpeta de destino.
    func driveOnlyArchives(jobID: BackupJob.ID) -> [RemoteArchive] {
        let local = Set((archives[jobID] ?? []).map(\.name))
        return (driveArchives[jobID] ?? []).filter { !local.contains($0.name) }
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
                let created = apply(output, to: jobID, mode: mode)
                if let created, let current = jobs.first(where: { $0.id == jobID }),
                   current.uploadsToDrive, isDriveConnected {
                    await refreshArchives(jobID: jobID)
                    if let archive = archives[jobID]?.first(where: { $0.url == created }) {
                        await upload(archive, of: current)
                    }
                }
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

    /// Devuelve la URL del backup creado (si se creó).
    @discardableResult
    private func apply(_ output: BackgroundWork.BackupOutput, to jobID: BackupJob.ID, mode: BackgroundWork.BackupMode) -> URL? {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return nil }
        var createdURL: URL?
        if let renewed = output.renewedSource { jobs[index].source = renewed }
        if let renewed = output.renewedDestination { jobs[index].destination = renewed }

        switch output.outcome {
        case .noChanges:
            append(.info, String(localized: "No changes since the last backup. No file was created."))
            notice = Notice(title: String(localized: "No Changes"),
                            message: String(localized: "Nothing changed since the last backup."))
        case let .created(result):
            createdURL = result.archiveURL
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
        return createdURL
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

    // MARK: - Google Drive

    func connectDrive() {
        guard !isConnectingDrive else { return }
        isConnectingDrive = true
        Task {
            defer { isConnectingDrive = false }
            do {
                let tokens = try await GoogleSignIn().signIn()
                try await GoogleSession.shared.store(tokens)
                isDriveConnected = true
                driveEmail = try? await GoogleSession.drive.accountEmail()
                append(.success, String(localized: "Google Drive connected."))
                for job in jobs { await refreshDrive(jobID: job.id) }
            } catch is CancellationError {
                // El usuario cerró la ventana de Google: no es un error.
            } catch {
                append(.error, Self.describe(error))
                notice = Notice(title: String(localized: "Couldn’t Connect Google Drive"), message: Self.describe(error))
            }
        }
    }

    func disconnectDrive() {
        Task {
            await GoogleSession.shared.disconnect()
            isDriveConnected = false
            driveEmail = nil
            driveArchives.removeAll()
            for index in jobs.indices { jobs[index].uploadsToDrive = false }
            persist()
            append(.info, String(localized: "Google Drive disconnected. Backups already in Drive were kept."))
        }
    }

    /// Carga el correo de la cuenta al abrir Ajustes (no se guarda en disco).
    func loadDriveAccount() async {
        guard isDriveConnected, driveEmail == nil else { return }
        driveEmail = try? await GoogleSession.drive.accountEmail()
    }

    func setUploadsToDrive(_ enabled: Bool, jobID: BackupJob.ID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].uploadsToDrive = enabled
        persist()
    }

    func startUpload(_ archive: ArchiveInfo, jobID: BackupJob.ID) {
        guard !isBusy, let job = jobs.first(where: { $0.id == jobID }) else { return }
        runningTask = Task {
            defer { runningTask = nil }
            await upload(archive, of: job)
        }
    }

    /// Sube un backup mostrando el progreso en Actividad. Los errores se informan, no se propagan:
    /// el backup local ya está guardado.
    private func upload(_ archive: ArchiveInfo, of job: BackupJob) async {
        let title = String(localized: "Uploading \(archive.name) to Google Drive")
        activity = Activity(kind: .upload, title: title, fraction: 0)
        append(.info, title)
        let (stream, continuation) = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let progressTask = Task { for await value in stream { activity?.fraction = value } }
        defer {
            progressTask.cancel()
            activity = nil
        }
        do {
            _ = try await BackgroundWork.uploadToDrive(archive, of: job, progress: continuation)
            append(.success, String(localized: "\(archive.name) uploaded to Google Drive."))
        } catch is CancellationError {
            append(.warning, String(localized: "Upload cancelled. The backup is still saved on this Mac."))
        } catch let error as URLError where error.code == .cancelled {
            append(.warning, String(localized: "Upload cancelled. The backup is still saved on this Mac."))
        } catch {
            handleDriveError(error, context: String(localized: "Upload to Google Drive Failed"))
        }
        await refreshDrive(jobID: job.id)
    }

    func startDownload(_ remote: RemoteArchive, jobID: BackupJob.ID) {
        guard !isBusy else { return }
        runningTask = Task {
            defer { runningTask = nil }
            _ = await download(remote, jobID: jobID)
        }
    }

    /// Descarga el backup al destino y lo restaura en una carpeta nueva.
    func startRestoreFromDrive(_ remote: RemoteArchive, jobID: BackupJob.ID, intoParent parent: URL) {
        guard !isBusy else { return }
        runningTask = Task {
            // Cancelar durante la descarga cancela esta tarea; la restauración se registra como tarea propia.
            guard let archive = await download(remote, jobID: jobID) else {
                runningTask = nil
                return
            }
            startRestore(archive, jobID: jobID, intoParent: parent)
        }
    }

    /// Descarga el backup al destino y lo restaura en la carpeta de origen.
    func startRestoreInPlaceFromDrive(_ remote: RemoteArchive, jobID: BackupJob.ID) {
        guard !isBusy else { return }
        runningTask = Task {
            // Cancelar durante la descarga cancela esta tarea; la restauración se registra como tarea propia.
            guard let archive = await download(remote, jobID: jobID) else {
                runningTask = nil
                return
            }
            startRestoreInPlace(archive, jobID: jobID)
        }
    }

    /// Descarga a la carpeta de destino (queda como backup local) y devuelve el backup ya listado.
    private func download(_ remote: RemoteArchive, jobID: BackupJob.ID) async -> ArchiveInfo? {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return nil }
        let title = String(localized: "Downloading \(remote.name) from Google Drive")
        activity = Activity(kind: .download, title: title)
        append(.info, title)
        defer { activity = nil }
        do {
            let url = try await BackgroundWork.downloadFromDrive(remote, of: job)
            append(.success, String(localized: "\(remote.name) downloaded to the destination folder."))
            await refreshArchives(jobID: jobID)
            return archives[jobID]?.first { $0.url.standardizedFileURL == url.standardizedFileURL }
                ?? archives[jobID]?.first { $0.name == remote.name }
        } catch is CancellationError {
            append(.warning, String(localized: "Download cancelled. Nothing was saved."))
        } catch let error as URLError where error.code == .cancelled {
            append(.warning, String(localized: "Download cancelled. Nothing was saved."))
        } catch CocoaError.fileWriteFileExists {
            let message = String(localized: "A backup with that name is already in the destination folder.")
            append(.error, message)
            notice = Notice(title: String(localized: "Download from Google Drive Failed"), message: message)
        } catch {
            handleDriveError(error, context: String(localized: "Download from Google Drive Failed"))
        }
        return nil
    }

    /// A la papelera de Drive. El backup local, si existe, no se toca.
    func trashInDrive(_ remote: RemoteArchive, jobID: BackupJob.ID) {
        guard !isBusy else { return }
        Task {
            do {
                try await BackgroundWork.trashInDrive(remote)
                append(.info, String(localized: "\(remote.name) moved to the Google Drive trash."))
            } catch {
                handleDriveError(error, context: String(localized: "Couldn’t Move to the Google Drive Trash"))
            }
            await refreshDrive(jobID: jobID)
        }
    }

    private func handleDriveError(_ error: any Error, context: String) {
        if case GoogleAPIError.authorizationRevoked = error {
            isDriveConnected = false
            driveEmail = nil
            driveArchives.removeAll()
        }
        append(.error, "\(context): \(Self.describe(error))")
        notice = Notice(title: context, message: Self.describe(error))
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
        case GoogleAPIError.notConnected:
            String(localized: "Google Drive isn’t connected. Connect it in Settings.")
        case GoogleAPIError.authorizationRevoked:
            String(localized: "Google no longer allows SystemBack to access your Drive. Connect it again in Settings.")
        case GoogleAPIError.http(let status, let message):
            String(localized: "Google Drive returned an error (\(status)): \(message)")
        case GoogleAPIError.invalidResponse, GoogleAPIError.invalidCallback:
            String(localized: "Google returned an unexpected response. Try again.")
        case let error as URLError where error.code == .notConnectedToInternet:
            String(localized: "There’s no internet connection. The backup is still saved on this Mac.")
        case ArchiveError.notGzip:
            String(localized: "This file isn’t a .tar.gz backup.")
        default:
            error.localizedDescription
        }
    }
}
