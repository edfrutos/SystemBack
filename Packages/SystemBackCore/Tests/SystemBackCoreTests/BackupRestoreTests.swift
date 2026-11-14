import Foundation
import Testing
@testable import SystemBackCore

/// Casos portados de `test_backup_interface.py` (TestBackupFlow, TestSafePath, restauración).
@Suite("Backup y restauración")
struct BackupRestoreTests {
    let sandbox = TemporaryDirectory()

    var source: URL { sandbox.url.appending(path: "proyecto") }
    var destination: URL { sandbox.url.appending(path: "backups") }

    init() throws {
        try sandbox.write("contenido 1", to: "proyecto/file1.txt")
        try sandbox.write("print(\"hola\")", to: "proyecto/file2.py")
        try sandbox.write("{\"key\": \"value\"}", to: "proyecto/subdir/data.json")
        try sandbox.write("basura", to: "proyecto/.DS_Store")
    }

    @Test func `backup completo crea archivo con nombre y timestamp`() throws {
        let date = try #require(Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 11, day: 14, hour: 9, minute: 5, second: 7)))
        let outcome = try BackupEngine().run(BackupRequest(source: source, destinationRoot: destination, date: date))
        let result = try #require(outcome.created)

        #expect(result.archiveURL.lastPathComponent == "backup_proyecto_20261114_090507.tar.gz")
        #expect(result.archiveURL.deletingLastPathComponent().lastPathComponent == "proyecto")
        #expect(result.fileCount == 3)
        #expect(result.archiveBytes > 0)
        #expect(!FileManager.default.fileExists(atPath: result.archiveURL.path + ".partial"))
    }

    @Test func `dos backups en el mismo segundo no se pisan`() throws {
        let date = Date.now
        let first = try #require(try BackupEngine().run(BackupRequest(source: source, destinationRoot: destination, date: date)).created)
        let second = try #require(try BackupEngine().run(BackupRequest(source: source, destinationRoot: destination, date: date)).created)
        #expect(first.archiveURL != second.archiveURL)
    }

    @Test func `ida y vuelta conserva contenido, fechas y excluye .DS_Store`() throws {
        let original = source.appending(path: "subdir/data.json")
        let mtime = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: original.path)

        let result = try #require(try BackupEngine().run(BackupRequest(source: source, destinationRoot: destination)).created)
        let restored = sandbox.url.appending(path: "restaurado")
        let restore = try RestoreEngine().restore(archive: result.archiveURL, into: restored)

        #expect(restore.restoredFiles == 3)
        #expect(restore.skippedEntries.isEmpty)
        #expect(try String(contentsOf: restored.appending(path: "subdir/data.json"), encoding: .utf8) == "{\"key\": \"value\"}")
        #expect(!FileManager.default.fileExists(atPath: restored.appending(path: ".DS_Store").path))
        let restoredDate = try FileManager.default.attributesOfItem(atPath: restored.appending(path: "subdir/data.json").path)[.modificationDate] as? Date
        #expect(restoredDate == mtime)
    }

    @Test func `incremental solo incluye ficheros modificados`() throws {
        let cutoff = Date.now.addingTimeInterval(-60)
        for name in ["file1.txt", "file2.py", "subdir/data.json"] {
            try FileManager.default.setAttributes([.modificationDate: cutoff.addingTimeInterval(-3600)],
                                                  ofItemAtPath: source.appending(path: name).path)
        }
        #expect(try BackupEngine().run(BackupRequest(source: source, destinationRoot: destination,
                                                     kind: .incremental(since: cutoff))) == .noChanges)

        try sandbox.write("cambiado", to: "proyecto/file1.txt")
        let result = try #require(try BackupEngine().run(BackupRequest(source: source, destinationRoot: destination,
                                                                       kind: .incremental(since: cutoff))).created)
        #expect(result.fileCount == 1)
        #expect(result.archiveURL.lastPathComponent.hasPrefix("incr_proyecto_"))
    }

    @Test func `destino dentro del origen no se archiva a sí mismo`() throws {
        let inside = source.appending(path: "backups")
        let result = try #require(try BackupEngine().run(BackupRequest(source: source, destinationRoot: inside)).created)
        let listing = String(decoding: try run("/usr/bin/tar", ["-tzf", result.archiveURL.path]), as: UTF8.self)
        #expect(!listing.contains("backups/"))
        #expect(result.fileCount == 3)
    }

    @Test func `origen inexistente da error tipado`() {
        let missing = sandbox.url.appending(path: "no_existe")
        #expect(throws: BackupError.sourceNotADirectory(missing.standardizedFileURL)) {
            try BackupEngine().run(BackupRequest(source: missing, destinationRoot: destination))
        }
    }

    @Test func `restaurar sobre carpeta con datos se rechaza`() throws {
        let result = try #require(try BackupEngine().run(BackupRequest(source: source, destinationRoot: destination)).created)
        try sandbox.write("mío", to: "ocupado/importante.txt")
        let occupied = sandbox.url.appending(path: "ocupado").standardizedFileURL
        #expect(throws: RestoreError.destinationNotEmpty(occupied)) {
            try RestoreEngine().restore(archive: result.archiveURL, into: occupied)
        }
        #expect(try String(contentsOf: occupied.appending(path: "importante.txt"), encoding: .utf8) == "mío")
    }

    // MARK: - Path traversal (TestSafePath y validación de rutas del tar)

    @Test(arguments: ["../fuera.txt", "/etc/passwd", "a/../../fuera.txt", "..", "./../x"])
    func `rutas inseguras se rechazan`(path: String) {
        #expect(throws: ArchiveError.unsafeEntryPath(path)) {
            try RestoreEngine.resolve(path, in: URL(filePath: "/tmp/destino"))
        }
    }

    @Test(arguments: ["a.txt", "./a.txt", "dir/sub/a.txt", "dir//a.txt"])
    func `rutas seguras se resuelven dentro del destino`(path: String) throws {
        let target = try RestoreEngine.resolve(path, in: URL(filePath: "/tmp/destino"))
        #expect(target.path.hasPrefix("/tmp/destino/"))
    }

    @Test func `archivo con entrada maliciosa no deja nada restaurado`() throws {
        // Tar hecho a mano: un fichero legítimo seguido de "../evil.txt".
        let archive = sandbox.url.appending(path: "malicioso.tar.gz")
        let gzip = try GzipFileWriter(creating: archive)
        var tar = TarWriter { try gzip.write($0) }
        let good = sandbox.url.appending(path: "proyecto/file1.txt")
        try tar.addFile(path: "bueno.txt", contentsOf: good, size: 11, modificationDate: .now)
        try tar.addFile(path: "../evil.txt", contentsOf: good, size: 11, modificationDate: .now)
        try tar.finish()
        try gzip.finish()

        let restored = sandbox.url.appending(path: "restaurado")
        #expect(throws: ArchiveError.unsafeEntryPath("../evil.txt")) {
            try RestoreEngine().restore(archive: archive, into: restored)
        }
        #expect(!FileManager.default.fileExists(atPath: restored.path))
        #expect(!FileManager.default.fileExists(atPath: sandbox.url.appending(path: "evil.txt").path))
    }

    @Test func `enlaces simbólicos del archivo se omiten`() throws {
        try sandbox.write("dato", to: "conlink/real.txt")
        try FileManager.default.createSymbolicLink(atPath: sandbox.url.appending(path: "conlink/enlace").path,
                                                   withDestinationPath: "/etc")
        let archive = sandbox.url.appending(path: "conlink.tar.gz")
        _ = try run("/usr/bin/tar", ["-czf", archive.path, "-C", sandbox.url.appending(path: "conlink").path, "."])

        let restored = sandbox.url.appending(path: "restaurado")
        let result = try RestoreEngine().restore(archive: archive, into: restored)
        #expect(result.restoredFiles == 1)
        #expect(result.skippedEntries.contains { $0.hasSuffix("enlace") })
        #expect(!FileManager.default.fileExists(atPath: restored.appending(path: "enlace").path))
    }

    @Test func `nombres de carpeta de restauración únicos`() throws {
        try sandbox.write("x", to: "restaurar/backup_a/f.txt")
        let parent = sandbox.url.appending(path: "restaurar")
        let unique = RestoreEngine.uniqueDestination(in: parent, baseName: "backup_a")
        #expect(unique.lastPathComponent == "backup_a 2")
        #expect(RestoreEngine.baseName(of: URL(filePath: "/x/backup_a_20261114_090507.tar.gz")) == "backup_a_20261114_090507")
    }

    @Test func `backup cancelado no deja archivo parcial`() async throws {
        for index in 0..<200 { try sandbox.write(String(repeating: "x", count: 10_000), to: "proyecto/carga/f\(index).txt") }
        let (source, destination) = (source, destination)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try BackupEngine().run(BackupRequest(source: source, destinationRoot: destination))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        let leftovers = (try? FileManager.default.subpathsOfDirectory(atPath: destination.path)) ?? []
        #expect(leftovers.allSatisfy { !$0.hasSuffix(".tar.gz") && !$0.hasSuffix(".partial") })
    }
}

extension BackupOutcome {
    var created: BackupResult? {
        if case let .created(result) = self { result } else { nil }
    }
}
