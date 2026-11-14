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
        var fraction: Double = 0
    }

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var message: String
    }

    private(set) var jobs: [BackupJob] = []
    private(set) var activity: Activity?
    var notice: Notice?

    private let store: JobStore?
    private var runningTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.efjdev.systemback", category: "model")

    init(store: JobStore? = try? JobStore.standard()) {
        self.store = store
        do {
            jobs = try store?.load() ?? []
        } catch {
            log.error("No se pudieron cargar los trabajos: \(error.localizedDescription, privacy: .public)")
            notice = Notice(title: String(localized: "Couldn’t Load Backup Jobs"),
                            message: error.localizedDescription)
        }
    }

    var isBusy: Bool { activity != nil }

    // MARK: - Trabajos

    func addJob(name: String, source: URL, destination: URL) throws {
        let job = BackupJob(name: name, source: try FolderReference.make(from: source),
                            destination: try FolderReference.make(from: destination))
        jobs.append(job)
        persist()
    }

    func removeJob(_ id: BackupJob.ID) {
        jobs.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Backup

    func startBackup(jobID: BackupJob.ID, incremental: Bool) {
        guard !isBusy, let job = jobs.first(where: { $0.id == jobID }) else { return }
        let kind: BackupKind = if incremental, let last = job.lastBackupDate { .incremental(since: last) } else { .full }
        activity = Activity(kind: .backup(jobID: jobID),
                            title: incremental ? String(localized: "Incremental backup of \(job.name)")
                                               : String(localized: "Backing up \(job.name)"))
        let (stream, continuation) = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))

        runningTask = Task {
            await Notifications.requestAuthorizationIfNeeded()
            let progressTask = Task { for await value in stream { activity?.fraction = value } }
            defer {
                progressTask.cancel()
                activity = nil
                runningTask = nil
            }
            do {
                let output = try await BackgroundWork.backup(job, kind: kind, progress: continuation)
                apply(output, to: jobID, kind: kind)
            } catch is CancellationError {
                log.info("Backup cancelado")
            } catch {
                log.error("Backup fallido: \(error.localizedDescription, privacy: .public)")
                notice = Notice(title: String(localized: "Backup Failed"), message: Self.describe(error))
            }
        }
    }

    private func apply(_ output: BackgroundWork.BackupOutput, to jobID: BackupJob.ID, kind: BackupKind) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        if let renewed = output.renewedSource { jobs[index].source = renewed }
        if let renewed = output.renewedDestination { jobs[index].destination = renewed }

        switch output.outcome {
        case .noChanges:
            notice = Notice(title: String(localized: "No Changes"),
                            message: String(localized: "Nothing changed since the last backup."))
        case let .created(result):
            let recordKind: BackupRecord.Kind = if case .incremental = kind { .incremental } else { .full }
            jobs[index].record(BackupRecord(date: .now, kind: recordKind, archiveName: result.archiveURL.lastPathComponent,
                                            fileCount: result.fileCount, contentBytes: result.contentBytes,
                                            archiveBytes: result.archiveBytes))
            Notifications.post(title: String(localized: "Backup Complete"),
                               body: String(localized: "\(jobs[index].name): \(result.fileCount) files saved."))
        }
        persist()
    }

    // MARK: - Restauración

    func startRestore(archive: URL, intoParent parent: URL) {
        guard !isBusy else { return }
        activity = Activity(kind: .restore, title: String(localized: "Restoring \(archive.lastPathComponent)"))
        let (stream, continuation) = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))

        runningTask = Task {
            let progressTask = Task { for await value in stream { activity?.fraction = value } }
            defer {
                progressTask.cancel()
                activity = nil
                runningTask = nil
            }
            do {
                let result = try await BackgroundWork.restore(archive: archive, intoParent: parent, progress: continuation)
                var message = String(localized: "\(result.restoredFiles) files restored to “\(result.destination.lastPathComponent)”.")
                if !result.skippedEntries.isEmpty {
                    message += " " + String(localized: "\(result.skippedEntries.count) links or special items were skipped.")
                }
                notice = Notice(title: String(localized: "Restore Complete"), message: message)
            } catch is CancellationError {
                log.info("Restauración cancelada")
            } catch {
                notice = Notice(title: String(localized: "Restore Failed"), message: Self.describe(error))
            }
        }
    }

    func cancelActivity() {
        runningTask?.cancel()
    }

    // MARK: - Utilidades

    private func persist() {
        do {
            try store?.save(jobs)
        } catch {
            log.error("No se pudieron guardar los trabajos: \(error.localizedDescription, privacy: .public)")
            notice = Notice(title: String(localized: "Couldn’t Save Changes"), message: error.localizedDescription)
        }
    }

    /// Mensaje que dice qué pasó y qué hacer.
    static func describe(_ error: any Error) -> String {
        switch error {
        case BackupError.sourceNotADirectory:
            String(localized: "The source folder is no longer available. Choose it again in the job settings.")
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
