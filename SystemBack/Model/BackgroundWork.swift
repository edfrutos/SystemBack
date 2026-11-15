import Foundation
import SystemBackCore

/// Trabajo pesado fuera del hilo principal. Todo lo demás vive en el main actor (ajuste del target).
/// Cada función resuelve las bookmarks y abre el acceso con security scope solo mientras trabaja.
nonisolated enum BackgroundWork {
    enum BackupMode: Sendable, Equatable {
        case full
        case incremental(since: Date)
        /// Backup completo nuevo y el anterior más reciente a la Papelera ("Actualizar backup").
        case replaceLatest
    }

    struct BackupOutput: Sendable {
        var outcome: BackupOutcome
        /// Backup anterior movido a la Papelera (solo en `.replaceLatest`).
        var replaced: ArchiveInfo?
        /// Dónde quedó el anterior tras moverlo a la Papelera (lo indica el sistema).
        var replacedTrashLocation: URL?
        /// El backup nuevo se creó, pero el anterior no se pudo mover a la Papelera.
        var replaceFailure: String?
        var renewedSource: FolderReference?
        var renewedDestination: FolderReference?
    }

    @concurrent
    static func backup(
        _ job: BackupJob,
        mode: BackupMode,
        progress: AsyncStream<BackupProgress>.Continuation
    ) async throws -> BackupOutput {
        defer { progress.finish() }
        let (sourceURL, renewedSource) = try job.source.resolve()
        let (destinationURL, renewedDestination) = try job.destination.resolve()

        return try withSecurityScopedAccess(to: sourceURL) {
            try withSecurityScopedAccess(to: destinationURL) {
                let sourceName = sourceURL.standardizedFileURL.lastPathComponent
                let previous = mode == .replaceLatest
                    ? try ArchiveCatalog.list(destinationRoot: destinationURL, sourceName: sourceName).first
                    : nil
                let kind: BackupKind = if case let .incremental(since) = mode { .incremental(since: since) } else { .full }

                let outcome = try BackupEngine().run(
                    BackupRequest(source: sourceURL, destinationRoot: destinationURL,
                                  kind: kind, exclusions: job.exclusions)
                ) { progress.yield($0) }

                // Solo se retira el anterior cuando el nuevo ya existe completo.
                // Si falla (volumen sin Papelera), el backup nuevo sigue siendo válido: se avisa, no se da por fallido.
                var replaced: ArchiveInfo?
                var trashLocation: URL?
                var replaceFailure: String?
                if case .created = outcome, let previous {
                    do {
                        trashLocation = try ArchiveCatalog.moveToTrash(previous.url)
                        replaced = previous
                    } catch {
                        replaceFailure = error.localizedDescription
                    }
                }
                return BackupOutput(outcome: outcome, replaced: replaced, replacedTrashLocation: trashLocation,
                                    replaceFailure: replaceFailure,
                                    renewedSource: renewedSource, renewedDestination: renewedDestination)
            }
        }
    }

    @concurrent
    static func listArchives(of job: BackupJob) async throws -> [ArchiveInfo] {
        let (destinationURL, _) = try job.destination.resolve()
        return try withSecurityScopedAccess(to: destinationURL) {
            try ArchiveCatalog.list(destinationRoot: destinationURL, sourceName: try sourceName(of: job))
        }
    }

    /// Devuelve la ubicación en la Papelera si el sistema la informa.
    @concurrent
    static func moveToTrash(_ archive: ArchiveInfo, of job: BackupJob) async throws -> URL? {
        let (destinationURL, _) = try job.destination.resolve()
        return try withSecurityScopedAccess(to: destinationURL) {
            try ArchiveCatalog.moveToTrash(archive.url)
        }
    }

    /// Restaura un backup del destino de un trabajo.
    @concurrent
    static func restore(
        _ archive: ArchiveInfo,
        of job: BackupJob,
        intoParent parent: URL,
        progress: AsyncStream<Double>.Continuation
    ) async throws -> RestoreResult {
        let (destinationURL, _) = try job.destination.resolve()
        return try withSecurityScopedAccess(to: destinationURL) {
            try restoreSync(archive: archive.url, bytes: archive.bytes, intoParent: parent, progress: progress)
        }
    }

    /// Restaura un fichero `.tar.gz` elegido por el usuario.
    @concurrent
    static func restore(
        archive: URL,
        intoParent parent: URL,
        progress: AsyncStream<Double>.Continuation
    ) async throws -> RestoreResult {
        try withSecurityScopedAccess(to: archive) {
            let bytes = (try? FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? UInt64) ?? 0
            return try restoreSync(archive: archive, bytes: bytes, intoParent: parent, progress: progress)
        }
    }

    enum InPlaceError: Error, Equatable {
        /// La carpeta de origen está en la Papelera (la bookmark la sigue hasta allí).
        case sourceInTrash
    }

    /// Restaura un backup sobre la carpeta de origen del trabajo.
    /// Lo que se sustituye va a la Papelera; si no se puede mover, se aborta sin escribir encima.
    @concurrent
    static func restoreInPlace(
        _ archive: ArchiveInfo,
        of job: BackupJob,
        progress: AsyncStream<Double>.Continuation
    ) async throws -> InPlaceRestoreResult {
        defer { progress.finish() }
        let (destinationURL, _) = try job.destination.resolve()
        let (sourceURL, _) = try job.source.resolve()
        guard !sourceURL.pathComponents.contains(".Trash") else { throw InPlaceError.sourceInTrash }
        return try withSecurityScopedAccess(to: destinationURL) {
            try withSecurityScopedAccess(to: sourceURL) {
                let estimate = max(Double(archive.bytes) * 3, 1)
                return try RestoreEngine().restoreInPlace(
                    archive: archive.url, into: sourceURL,
                    moveAside: { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
                ) { processed in
                    progress.yield(min(Double(processed) / estimate, 0.99))
                }
            }
        }
    }

    private static func restoreSync(
        archive: URL, bytes: UInt64, intoParent parent: URL,
        progress: AsyncStream<Double>.Continuation
    ) throws -> RestoreResult {
        defer { progress.finish() }
        return try withSecurityScopedAccess(to: parent) {
            let destination = RestoreEngine.uniqueDestination(in: parent, baseName: RestoreEngine.baseName(of: archive))
            // El total descomprimido no se conoce de antemano: estimación acotada (ratio ~1:3) solo para la barra.
            let estimate = max(Double(bytes) * 3, 1)
            return try RestoreEngine().restore(archive: archive, into: destination) { restored in
                progress.yield(min(Double(restored) / estimate, 0.99))
            }
        }
    }

    // MARK: - Google Drive

    /// Carpeta del trabajo en Drive: `SystemBack/<carpeta de origen>/` (se crea si falta).
    private static func driveFolder(for job: BackupJob, _ drive: DriveClient) async throws -> String {
        let root = try await drive.findOrCreateFolder(named: GoogleConfig.rootFolderName, parent: nil)
        return try await drive.findOrCreateFolder(named: try sourceName(of: job), parent: root)
    }

    @concurrent
    static func listDrive(of job: BackupJob) async throws -> [RemoteArchive] {
        let drive = GoogleSession.drive
        let files = try await drive.list(inFolder: try await driveFolder(for: job, drive))
        return ArchiveCatalog.remote(files, sourceName: try sourceName(of: job))
    }

    /// Descarga un backup de Drive a la carpeta de destino del trabajo (sin sobrescribir).
    /// Primero a un temporal del contenedor: si falla o se cancela, no queda nada a medias en el destino.
    @concurrent
    static func downloadFromDrive(_ remote: RemoteArchive, of job: BackupJob) async throws -> URL {
        let temporary = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString + ".tar.gz", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await GoogleSession.drive.download(remote.file.id, to: temporary)
        try Task.checkCancellation()
        let (destinationURL, _) = try job.destination.resolve()
        return try withSecurityScopedAccess(to: destinationURL) {
            try ArchiveCatalog.adopt(temporary, named: remote.name,
                                     destinationRoot: destinationURL, sourceName: try sourceName(of: job))
        }
    }

    /// A la papelera de Drive (recuperable 30 días desde drive.google.com).
    @concurrent
    static func trashInDrive(_ remote: RemoteArchive) async throws {
        try await GoogleSession.drive.trash(remote.file.id)
    }

    @concurrent
    static func uploadToDrive(
        _ archive: ArchiveInfo,
        of job: BackupJob,
        progress: AsyncStream<Double>.Continuation
    ) async throws -> DriveFile {
        defer { progress.finish() }
        let drive = GoogleSession.drive
        let folder = try await driveFolder(for: job, drive)
        let (destinationURL, _) = try job.destination.resolve()
        let didStart = destinationURL.startAccessingSecurityScopedResource()
        defer { if didStart { destinationURL.stopAccessingSecurityScopedResource() } }
        return try await drive.upload(fileAt: archive.url, name: archive.name, parent: folder) { progress.yield($0) }
    }

    /// Nombre actual de la carpeta de origen (la bookmark sigue a la carpeta si se renombra).
    private static func sourceName(of job: BackupJob) throws -> String {
        try job.source.resolve().url.standardizedFileURL.lastPathComponent
    }
}
