import Foundation
import SystemBackCore

/// Trabajo pesado fuera del hilo principal. Todo lo demás vive en el main actor (ajuste del target).
nonisolated enum BackgroundWork {
    struct BackupOutput: Sendable {
        var outcome: BackupOutcome
        var renewedSource: FolderReference?
        var renewedDestination: FolderReference?
    }

    @concurrent
    static func backup(
        _ job: BackupJob,
        kind: BackupKind,
        progress: AsyncStream<Double>.Continuation
    ) async throws -> BackupOutput {
        defer { progress.finish() }
        let (sourceURL, renewedSource) = try job.source.resolve()
        let (destinationURL, renewedDestination) = try job.destination.resolve()

        let outcome = try withSecurityScopedAccess(to: sourceURL) {
            try withSecurityScopedAccess(to: destinationURL) {
                try BackupEngine().run(
                    BackupRequest(source: sourceURL, destinationRoot: destinationURL,
                                  kind: kind, exclusions: job.exclusions)
                ) { progress.yield($0.fractionCompleted) }
            }
        }
        return BackupOutput(outcome: outcome, renewedSource: renewedSource, renewedDestination: renewedDestination)
    }

    @concurrent
    static func restore(
        archive: URL,
        intoParent parent: URL,
        progress: AsyncStream<Double>.Continuation
    ) async throws -> RestoreResult {
        defer { progress.finish() }
        return try withSecurityScopedAccess(to: archive) {
            try withSecurityScopedAccess(to: parent) {
                let total = (try? FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? UInt64) ?? 0
                let destination = RestoreEngine.uniqueDestination(in: parent, baseName: RestoreEngine.baseName(of: archive))
                // El progreso de restauración se mide en bytes descomprimidos; el total real se desconoce,
                // así que se usa una estimación acotada (ratio típico 1:3) solo para la barra.
                let estimate = max(Double(total) * 3, 1)
                return try RestoreEngine().restore(archive: archive, into: destination) { bytes in
                    progress.yield(min(Double(bytes) / estimate, 0.99))
                }
            }
        }
    }
}
