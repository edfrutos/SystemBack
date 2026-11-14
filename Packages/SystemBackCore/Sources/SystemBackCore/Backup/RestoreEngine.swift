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
    /// La carpeta de restauración en origen no existe o no es una carpeta.
    case folderNotFound(URL)
}

/// Resultado de restaurar sobre la carpeta original.
public struct InPlaceRestoreResult: Sendable, Equatable {
    public var destination: URL
    /// Ficheros escritos (nuevos o con contenido distinto).
    public var restoredFiles: Int
    /// Ficheros que ya eran idénticos (mismo tamaño y fecha): no se tocan.
    public var unchangedFiles: Int
    /// Elementos existentes apartados (`moveAside`) antes de escribir encima.
    public var replacedItems: Int
    public var skippedEntries: [String]
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

    /// Restaura sobre una carpeta existente (la de origen del trabajo).
    /// - Los ficheros idénticos (mismo tamaño y misma fecha en segundos) no se tocan.
    /// - Todo elemento existente que haya que sustituir pasa antes por `moveAside` (la app lo manda a la Papelera),
    ///   así la operación se puede deshacer. Si `moveAside` falla, se aborta sin escribir encima.
    /// - Lo que no está en el archivo no se toca.
    /// - Además de validar cada ruta, comprueba que su carpeta real (resolviendo enlaces) siga dentro de `folder`.
    /// Ante un error no se deshace lo ya restaurado; solo se borra el fichero que estuviera a medio escribir.
    public func restoreInPlace(
        archive: URL,
        into folder: URL,
        moveAside: @escaping (URL) throws -> Void,
        progress: @escaping @Sendable (_ processedBytes: UInt64) -> Void = { _ in }
    ) throws -> InPlaceRestoreResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: archive.path) else { throw RestoreError.archiveNotFound(archive) }
        let root = folder.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RestoreError.folderNotFound(root)
        }
        let realRoot = root.resolvingSymlinksInPath().path

        var result = InPlaceRestoreResult(destination: root, restoredFiles: 0, unchangedFiles: 0,
                                          replacedItems: 0, skippedEntries: [])
        var processed: UInt64 = 0
        var fileInProgress: URL?

        func existingType(_ url: URL) -> FileAttributeType? {
            // attributesOfItem no sigue enlaces: un enlace se ve como enlace.
            (try? fileManager.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
        }
        /// La carpeta real (primer ancestro existente, con enlaces resueltos) debe seguir dentro de `root`.
        /// Lo que aún no existe no puede contener enlaces, así que basta con comprobar el ancestro.
        func checkInside(_ target: URL, entryPath: String) throws {
            var ancestor = target.deletingLastPathComponent()
            while existingType(ancestor) == nil, ancestor.path.count > root.path.count {
                ancestor = ancestor.deletingLastPathComponent()
            }
            let real = ancestor.resolvingSymlinksInPath().path
            guard real == realRoot || real.hasPrefix(realRoot + "/") else {
                throw ArchiveError.unsafeEntryPath(entryPath)
            }
        }

        do {
            let parser = TarStreamParser { entry in
                try Task.checkCancellation()
                if entry.kind == .directory, Self.isRoot(entry.path) { return nil }
                let target = try Self.resolve(entry.path, in: root)
                if entry.kind == .file, target.lastPathComponent.hasPrefix("._") { return nil }
                switch entry.kind {
                case .directory:
                    try checkInside(target, entryPath: entry.path)
                    switch existingType(target) {
                    case .typeDirectory?:
                        return nil
                    case nil:
                        break
                    default:
                        try moveAside(target)
                        result.replacedItems += 1
                    }
                    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                    return nil
                case .file:
                    try checkInside(target, entryPath: entry.path)
                    try fileManager.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
                    if let type = existingType(target) {
                        if type == .typeRegular, Self.isSame(target, size: entry.size, date: entry.modificationDate) {
                            result.unchangedFiles += 1
                            processed += entry.size
                            progress(processed)
                            return nil
                        }
                        try moveAside(target)
                        result.replacedItems += 1
                    }
                    result.restoredFiles += 1
                    fileInProgress = target
                    return try FileContentSink(url: target, mode: entry.mode, modificationDate: entry.modificationDate,
                                               onFinish: { fileInProgress = nil }) {
                        processed += UInt64($0)
                        progress(processed)
                    }
                case .symbolicLink, .hardLink, .other:
                    result.skippedEntries.append(entry.path)
                    return nil
                }
            }
            try GzipFileReader.decompress(archive) { try parser.consume($0) }
            try parser.finish()
        } catch {
            if let partial = fileInProgress { try? fileManager.removeItem(at: partial) }
            throw error
        }
        return result
    }

    /// Mismo tamaño y misma fecha de modificación en segundos (tar guarda segundos enteros).
    static func isSame(_ url: URL, size: UInt64, date: Date) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let existingSize = (attributes[.size] as? NSNumber)?.uint64Value,
              let existingDate = attributes[.modificationDate] as? Date else { return false }
        return existingSize == size
            && existingDate.timeIntervalSince1970.rounded(.down) == date.timeIntervalSince1970.rounded(.down)
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
    private let onFinish: () -> Void

    init(url: URL, mode: UInt32, modificationDate: Date, onFinish: @escaping () -> Void = {},
         onBytes: @escaping (Int) -> Void) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw ArchiveError.cannotCreate(url)
        }
        self.url = url
        self.handle = try FileHandle(forWritingTo: url)
        self.mode = mode
        self.modificationDate = modificationDate
        self.onBytes = onBytes
        self.onFinish = onFinish
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
        onFinish()
    }
}
