import Foundation

public struct RestoreResult: Sendable, Equatable {
    public var destination: URL
    public var restoredFiles: Int
    public var restoredBytes: UInt64
    /// Entradas no restauradas por seguridad (enlaces, dispositivos…), con su ruta en el archivo.
    public var skippedEntries: [String]
}

public enum RestoreError: Error, Equatable, Sendable {
    case archiveNotFound(URL)
    /// El destino existe y no está vacío: nunca se sobrescriben datos del usuario.
    case destinationNotEmpty(URL)
}

/// Restaura un `.tar.gz` en una carpeta nueva o vacía.
/// Toda ruta se valida antes de escribir (absolutas, `..`, salida del destino): ante la primera
/// ruta insegura se aborta y se borra lo restaurado, igual que la validación previa de la herramienta Python.
public struct RestoreEngine: Sendable {
    public init() {}

    public func restore(
        archive: URL,
        into destination: URL,
        progress: @escaping @Sendable (_ restoredBytes: UInt64) -> Void = { _ in }
    ) throws -> RestoreResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: archive.path) else { throw RestoreError.archiveNotFound(archive) }

        let root = destination.standardizedFileURL
        let createdRoot: Bool
        if fileManager.fileExists(atPath: root.path) {
            let contents = try fileManager.contentsOfDirectory(atPath: root.path)
            guard contents.isEmpty else { throw RestoreError.destinationNotEmpty(root) }
            createdRoot = false
        } else {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            createdRoot = true
        }

        var result = RestoreResult(destination: root, restoredFiles: 0, restoredBytes: 0, skippedEntries: [])
        var pendingDirectoryDates: [(URL, Date)] = []

        do {
            let parser = TarStreamParser { entry in
                try Task.checkCancellation()
                // "./" (tar -C dir .) es la propia raíz: no hay nada que crear.
                if entry.kind == .directory, Self.isRoot(entry.path) { return nil }
                let target = try Self.resolve(entry.path, in: root)
                // "._nombre": metadatos AppleDouble que añade `tar` de macOS; no son datos del usuario.
                if entry.kind == .file, target.lastPathComponent.hasPrefix("._") { return nil }
                switch entry.kind {
                case .directory:
                    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                    pendingDirectoryDates.append((target, entry.modificationDate))
                    return nil
                case .file:
                    try fileManager.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
                    result.restoredFiles += 1
                    return try FileContentSink(url: target, mode: entry.mode, modificationDate: entry.modificationDate) {
                        result.restoredBytes += UInt64($0)
                        progress(result.restoredBytes)
                    }
                case .symbolicLink, .hardLink, .other:
                    result.skippedEntries.append(entry.path)
                    return nil
                }
            }
            try GzipFileReader.decompress(archive) { try parser.consume($0) }
            try parser.finish()
            // Las fechas de carpeta al final: crear ficheros dentro las modifica.
            for (url, date) in pendingDirectoryDates.reversed() {
                try? fileManager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            }
        } catch {
            if createdRoot {
                try? fileManager.removeItem(at: root)
            } else if let leftovers = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                for item in leftovers { try? fileManager.removeItem(at: item) }
            }
            throw error
        }
        return result
    }

    static func isRoot(_ entryPath: String) -> Bool {
        !entryPath.hasPrefix("/")
            && entryPath.split(separator: "/").allSatisfy { $0 == "." }
    }

    /// Ruta relativa segura dentro de `root`, o `ArchiveError.unsafeEntryPath`.
    static func resolve(_ entryPath: String, in root: URL) throws -> URL {
        guard !entryPath.hasPrefix("/"), !entryPath.contains("\0") else {
            throw ArchiveError.unsafeEntryPath(entryPath)
        }
        let components = entryPath.split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0 != "." }
        guard !components.isEmpty, !components.contains("..") else {
            throw ArchiveError.unsafeEntryPath(entryPath)
        }
        let target = components.reduce(root) { $0.appending(path: $1) }.standardizedFileURL
        guard target.path.hasPrefix(root.path + "/") else {
            throw ArchiveError.unsafeEntryPath(entryPath)
        }
        return target
    }

    /// Carpeta de restauración libre: `<padre>/<nombre>`, `<nombre> 2`, `<nombre> 3`…
    public static func uniqueDestination(in parent: URL, baseName: String) -> URL {
        var candidate = parent.appending(path: baseName, directoryHint: .isDirectory)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appending(path: "\(baseName) \(counter)", directoryHint: .isDirectory)
            counter += 1
        }
        return candidate
    }

    /// Nombre base de un archivo de backup sin `.tar.gz`.
    public static func baseName(of archive: URL) -> String {
        let name = archive.lastPathComponent
        for suffix in [".tar.gz", ".tgz"] where name.lowercased().hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return archive.deletingPathExtension().lastPathComponent
    }
}

private final class FileContentSink: TarEntryContentSink {
    private let url: URL
    private let handle: FileHandle
    private let mode: UInt32
    private let modificationDate: Date
    private let onBytes: (Int) -> Void

    init(url: URL, mode: UInt32, modificationDate: Date, onBytes: @escaping (Int) -> Void) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw ArchiveError.cannotCreate(url)
        }
        self.url = url
        self.handle = try FileHandle(forWritingTo: url)
        self.mode = mode
        self.modificationDate = modificationDate
        self.onBytes = onBytes
    }

    func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
        onBytes(data.count)
    }

    func finish() throws {
        try handle.close()
        // Sin setuid/setgid/sticky; siempre legible y escribible por el propietario.
        let permissions = (mode & 0o777) | 0o600
        try FileManager.default.setAttributes(
            [.modificationDate: modificationDate, .posixPermissions: NSNumber(value: permissions)],
            ofItemAtPath: url.path
        )
    }
}
