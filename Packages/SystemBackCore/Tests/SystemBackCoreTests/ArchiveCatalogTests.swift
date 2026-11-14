import Foundation
import Testing
@testable import SystemBackCore

@Suite("Catálogo de backups")
struct ArchiveCatalogTests {
    let sandbox = TemporaryDirectory()

    @Test func `interpreta nombres de SystemBack y de la herramienta Python`() throws {
        let full = ArchiveCatalog.parse(name: "backup_proyecto_20261114_090507.tar.gz", sourceName: "proyecto")
        #expect(full.kind == .full)
        let expected = try #require(Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 11, day: 14, hour: 9, minute: 5, second: 7)))
        #expect(full.date == expected)

        #expect(ArchiveCatalog.parse(name: "incr_proyecto_20261114_090507_2.tar.gz", sourceName: "proyecto").kind == .incremental)
        #expect(ArchiveCatalog.parse(name: "copia_manual.tar.gz", sourceName: "proyecto").kind == .other)
        #expect(ArchiveCatalog.parse(name: "backup_proyecto_2026111_x.tar.gz", sourceName: "proyecto").date == nil)
    }

    @Test func `lista los backups del más reciente al más antiguo e ignora parciales`() throws {
        try sandbox.write("x", to: "proyecto/f.txt")
        let source = sandbox.url.appending(path: "proyecto")
        let destination = sandbox.url.appending(path: "dst")
        let engine = BackupEngine()
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = older.addingTimeInterval(3600)
        _ = try engine.run(BackupRequest(source: source, destinationRoot: destination, date: older))
        _ = try engine.run(BackupRequest(source: source, destinationRoot: destination, kind: .incremental(since: .distantPast), date: newer))
        try sandbox.write("basura", to: "dst/proyecto/backup_proyecto_20990101_000000.tar.gz.partial")

        let archives = try ArchiveCatalog.list(destinationRoot: destination, sourceName: "proyecto")
        #expect(archives.map(\.kind) == [.incremental, .full])
        #expect(archives.allSatisfy { $0.bytes > 0 })
        #expect(archives.first?.date == newer)
    }

    @Test func `destino sin backups devuelve lista vacía`() throws {
        #expect(try ArchiveCatalog.list(destinationRoot: sandbox.url, sourceName: "nada").isEmpty)
    }

    @Test func `el progreso informa de fase y fichero en curso`() throws {
        try sandbox.write("x", to: "p/a.txt")
        let phases = Recorder()
        _ = try BackupEngine().run(BackupRequest(source: sandbox.url.appending(path: "p"),
                                                 destinationRoot: sandbox.url.appending(path: "d"))) { phases.add($0) }
        let seen = phases.values
        #expect(seen.first?.phase == .scanning)
        #expect(seen.contains { $0.currentPath == "a.txt" })
        #expect(seen.last?.phase == .finishing)
    }
}

/// Acumulador seguro para callbacks @Sendable en tests.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [BackupProgress] = []
    func add(_ value: BackupProgress) { lock.withLock { storage.append(value) } }
    var values: [BackupProgress] { lock.withLock { storage } }
}
