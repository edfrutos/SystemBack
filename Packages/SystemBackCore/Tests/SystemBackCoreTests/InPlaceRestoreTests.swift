import Foundation
import Testing
@testable import SystemBackCore

/// Restaurar sobre la carpeta de origen: solo lo que falta o cambió, y lo sustituido se aparta (Papelera en la app).
@Suite("Restaurar en origen")
struct InPlaceRestoreTests {
    let sandbox = TemporaryDirectory()

    var source: URL { sandbox.url.appending(path: "proyecto").standardizedFileURL }
    var destination: URL { sandbox.url.appending(path: "backups") }
    var aside: URL { sandbox.url.appending(path: "apartado") }

    init() throws {
        try sandbox.write("contenido 1", to: "proyecto/file1.txt")
        try sandbox.write("print(\"hola\")", to: "proyecto/file2.py")
        try sandbox.write("{\"key\": \"value\"}", to: "proyecto/subdir/data.json")
    }

    /// Aparta a `apartado/` y anota qué se apartó.
    final class Mover {
        var moved: [String] = []
        let target: URL
        init(target: URL) { self.target = target }
        func callAsFunction(_ url: URL) throws {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            moved.append(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target.appending(path: "\(moved.count)-\(url.lastPathComponent)"))
        }
    }

    private func backup() throws -> URL {
        try #require(try BackupEngine().run(BackupRequest(source: source, destinationRoot: destination)).created).archiveURL
    }

    private func text(_ relative: String) throws -> String {
        try String(contentsOf: source.appending(path: relative), encoding: .utf8)
    }

    @Test func `recupera lo borrado, sustituye lo cambiado y no toca lo demás`() throws {
        let archive = try backup()
        let fm = FileManager.default
        try fm.removeItem(at: source.appending(path: "subdir"))          // borrado
        try sandbox.write("editado después", to: "proyecto/file2.py")    // cambiado
        try sandbox.write("nuevo", to: "proyecto/nuevo.txt")             // no está en el backup

        let mover = Mover(target: aside)
        let result = try RestoreEngine().restoreInPlace(archive: archive, into: source, moveAside: { try mover($0) })

        #expect(try text("subdir/data.json") == "{\"key\": \"value\"}")
        #expect(try text("file2.py") == "print(\"hola\")")
        #expect(try text("file1.txt") == "contenido 1")
        #expect(try text("nuevo.txt") == "nuevo")
        #expect(mover.moved == ["file2.py"])
        #expect(try String(contentsOf: aside.appending(path: "1-file2.py"), encoding: .utf8) == "editado después")
        #expect(result.restoredFiles == 2)
        #expect(result.unchangedFiles == 1)
        #expect(result.replacedItems == 1)
    }

    @Test func `restaurar dos veces seguidas no cambia nada`() throws {
        let archive = try backup()
        try FileManager.default.removeItem(at: source.appending(path: "file1.txt"))
        _ = try RestoreEngine().restoreInPlace(archive: archive, into: source, moveAside: { _ in })
        let mover = Mover(target: aside)
        let second = try RestoreEngine().restoreInPlace(archive: archive, into: source, moveAside: { try mover($0) })
        #expect(second.restoredFiles == 0)
        #expect(second.unchangedFiles == 3)
        #expect(mover.moved.isEmpty)
    }

    @Test func `si no se puede apartar, no se escribe encima`() throws {
        struct NoTrash: Error {}
        let archive = try backup()
        try sandbox.write("mío", to: "proyecto/file1.txt")
        #expect(throws: NoTrash.self) {
            try RestoreEngine().restoreInPlace(archive: archive, into: source, moveAside: { _ in throw NoTrash() })
        }
        #expect(try text("file1.txt") == "mío")
    }

    @Test func `enlace dentro del origen que apunta fuera se rechaza`() throws {
        let archive = try backup()
        let fm = FileManager.default
        let outside = sandbox.url.appending(path: "fuera")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.removeItem(at: source.appending(path: "subdir"))
        try fm.createSymbolicLink(at: source.appending(path: "subdir"), withDestinationURL: outside)

        #expect(throws: ArchiveError.self) {
            try RestoreEngine().restoreInPlace(archive: archive, into: source, moveAside: { _ in })
        }
        #expect(try fm.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test func `carpeta de origen inexistente da error tipado`() throws {
        let archive = try backup()
        let missing = sandbox.url.appending(path: "no_existe").standardizedFileURL
        #expect(throws: RestoreError.folderNotFound(missing)) {
            try RestoreEngine().restoreInPlace(archive: archive, into: missing, moveAside: { _ in })
        }
    }
}
