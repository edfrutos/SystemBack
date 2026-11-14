import Foundation
import Testing
@testable import SystemBackCore

@Suite("Formato tar.gz")
struct ArchiveFormatTests {
    let sandbox = TemporaryDirectory()

    @Test func `CRC-32 coincide con el vector de referencia`() {
        var crc = CRC32()
        crc.update(Array("123456789".utf8))
        #expect(crc.value == 0xCBF4_3926)
    }

    @Test(arguments: [
        ("path", "a"),
        ("path", String(repeating: "x", count: 200)),
        ("size", "9999999999"),
    ])
    func `registro PAX incluye su propia longitud`(key: String, value: String) {
        let record = TarWriter.paxRecord((key, value))
        let declared = Int(record.prefix { $0 != " " })
        #expect(declared == record.utf8.count)
        #expect(record.hasSuffix("\(key)=\(value)\n"))
    }

    @Test func `cabecera tar con checksum válido`() {
        let block = TarWriter.header(
            name: Array("dir/file.txt".utf8), size: 1234,
            modificationDate: Date(timeIntervalSince1970: 1_700_000_000), mode: 0o644, type: "0"
        )
        let bytes = Array(block)
        #expect(bytes.count == 512)
        #expect(TarStreamParser.checksumMatches(bytes))
        #expect(TarStreamParser.headerPath(bytes) == "dir/file.txt")
        #expect(TarStreamParser.parseNumber(bytes[124..<136]) == 1234)
    }

    @Test func `gzip propio se descomprime con gunzip del sistema`() throws {
        let gz = sandbox.url.appending(path: "datos.gz")
        let payload = Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let writer = try GzipFileWriter(creating: gz)
        try writer.write(payload)
        try writer.finish()

        let output = try run("/usr/bin/gunzip", ["-c", gz.path])
        #expect(output == payload)
    }

    @Test func `tar.gz propio se lista con bsdtar del sistema, incluida ruta larga`() throws {
        let source = sandbox.url.appending(path: "origen")
        let longName = String(repeating: "nombre_largo_", count: 12) + ".txt"
        try sandbox.write("hola", to: "origen/a.txt")
        try sandbox.write("anidado", to: "origen/sub/\(longName)")

        let outcome = try BackupEngine().run(BackupRequest(source: source, destinationRoot: sandbox.url.appending(path: "destino")))
        guard case let .created(result) = outcome else { Issue.record("sin archivo"); return }

        let listing = String(decoding: try run("/usr/bin/tar", ["-tzf", result.archiveURL.path]), as: UTF8.self)
        #expect(listing.contains("a.txt"))
        #expect(listing.contains("sub/\(longName)"))
    }

    @Test func `lee un tar.gz creado por tar del sistema`() throws {
        try sandbox.write("uno", to: "externo/x/uno.txt")
        try sandbox.write("dos", to: "externo/dos.txt")
        let archive = sandbox.url.appending(path: "externo.tar.gz")
        _ = try run("/usr/bin/tar", ["-czf", archive.path, "-C", sandbox.url.appending(path: "externo").path, "."])

        let restored = sandbox.url.appending(path: "restaurado")
        let result = try RestoreEngine().restore(archive: archive, into: restored)
        #expect(result.restoredFiles == 2)
        #expect(try String(contentsOf: restored.appending(path: "x/uno.txt"), encoding: .utf8) == "uno")
    }

    @Test func `gzip corrupto se detecta`() throws {
        let gz = sandbox.url.appending(path: "roto.gz")
        let writer = try GzipFileWriter(creating: gz)
        try writer.write(Data(repeating: 7, count: 10_000))
        try writer.finish()
        var bytes = try Data(contentsOf: gz)
        bytes[bytes.count - 6] ^= 0xFF          // altera el CRC del trailer
        try bytes.write(to: gz)

        #expect(throws: ArchiveError.checksumMismatch(gz)) {
            try GzipFileReader.decompress(gz) { _ in }
        }
    }
}

/// Ejecuta una herramienta del sistema y devuelve su salida estándar (solo tests).
func run(_ tool: String, _ arguments: [String]) throws -> Data {
    let process = Process()
    process.executableURL = URL(filePath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CocoaError(.executableLoad, userInfo: [NSLocalizedDescriptionKey: "\(tool) terminó con \(process.terminationStatus)"])
    }
    return data
}

@Suite("Compatibilidad con la herramienta Python")
struct PythonCompatibilityTests {
    let sandbox = TemporaryDirectory()

    /// `Fixtures/python_tarfile.tar.gz`: creado con `tarfile` (formato PAX por defecto), igual que
    /// `tools/test_simple_backup.py`; incluye una ruta de más de 100 bytes.
    @Test func `restaura un backup creado por tarfile de Python`() throws {
        let fixture = try #require(Bundle.module.url(forResource: "python_tarfile", withExtension: "tar.gz",
                                                     subdirectory: "Fixtures"))
        let restored = sandbox.url.appending(path: "restaurado")
        let result = try RestoreEngine().restore(archive: fixture, into: restored)

        #expect(result.restoredFiles == 3)
        #expect(try String(contentsOf: restored.appending(path: "a.txt"), encoding: .utf8) == "hola\n")
        let longName = String(repeating: "n", count: 150) + ".txt"
        #expect(try String(contentsOf: restored.appending(path: "sub/\(longName)"), encoding: .utf8) == "largo\n")
    }
}
