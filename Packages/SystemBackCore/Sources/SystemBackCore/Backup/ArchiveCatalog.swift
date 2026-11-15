import Foundation

/// Un archivo de backup encontrado en disco.
public struct ArchiveInfo: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Codable {
        case full
        case incremental
        /// `.tar.gz` sin el esquema de nombres de SystemBack (p. ej. copiado a mano).
        case other
    }

    public var url: URL
    public var kind: Kind
    /// Fecha del nombre (`yyyyMMdd_HHmmss`) o, si no la tiene, la de modificación.
    public var date: Date
    public var bytes: UInt64

    public var id: URL { url }
    public var name: String { url.lastPathComponent }
}

/// Un backup guardado en Google Drive (carpeta `SystemBack/<origen>/`).
public struct RemoteArchive: Sendable, Hashable, Identifiable {
    public var file: DriveFile
    public var kind: ArchiveInfo.Kind
    /// Fecha del nombre o, si no la tiene, la de creación en Drive.
    public var date: Date

    public var id: String { file.id }
    public var name: String { file.name }
    public var bytes: UInt64 { file.size ?? 0 }
}

/// Lista y gestiona los backups de un origen dentro de su carpeta de destino.
/// Las funciones esperan que el llamador ya tenga acceso (security scope) al destino.
public enum ArchiveCatalog {
    /// Carpeta donde `BackupEngine` deja los archivos de `sourceName`.
    public static func directory(destinationRoot: URL, sourceName: String) -> URL {
        destinationRoot.standardizedFileURL.appending(path: sourceName, directoryHint: .isDirectory)
    }

    /// Backups `.tar.gz` / `.tgz` de la carpeta, del más reciente al más antiguo. Ignora `.partial`.
    public static func list(destinationRoot: URL, sourceName: String) throws -> [ArchiveInfo] {
        let folder = directory(destinationRoot: destinationRoot, sourceName: sourceName)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )
        return try urls.compactMap { url -> ArchiveInfo? in
            let name = url.lastPathComponent.lowercased()
            guard name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") else { return nil }
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { return nil }
            let parsed = parse(name: url.lastPathComponent, sourceName: sourceName)
            return ArchiveInfo(
                url: url, kind: parsed.kind,
                date: parsed.date ?? values.contentModificationDate ?? .distantPast,
                bytes: UInt64(values.fileSize ?? 0)
            )
        }
        .sorted { $0.date > $1.date }
    }

    /// Mueve el archivo a la Papelera (recuperable) y devuelve su nueva ubicación si el sistema la da.
    @discardableResult
    public static func moveToTrash(_ archive: URL) throws -> URL? {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: archive, resultingItemURL: &resulting)
        return resulting as URL?
    }

    /// Backups de Drive con nombre válido, del más reciente al más antiguo.
    /// Se descartan los nombres que no podrían guardarse con seguridad en la carpeta de destino.
    public static func remote(_ files: [DriveFile], sourceName: String) -> [RemoteArchive] {
        files.compactMap { file -> RemoteArchive? in
            guard isSafeArchiveName(file.name) else { return nil }
            let parsed = parse(name: file.name, sourceName: sourceName)
            return RemoteArchive(file: file, kind: parsed.kind,
                                 date: parsed.date ?? file.createdTime ?? .distantPast)
        }
        .sorted { $0.date > $1.date }
    }

    /// Nombre de archivo simple `.tar.gz` / `.tgz`: sin rutas, sin ocultos, sin caracteres de control.
    public static func isSafeArchiveName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return !name.isEmpty && name.count <= 255
            && !name.hasPrefix(".")
            && !name.contains("/") && !name.contains(":")
            && !name.unicodeScalars.contains { $0.properties.generalCategory == .control }
            && (lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz"))
    }

    /// Mueve un archivo descargado a la carpeta de backups del origen sin sobrescribir nada.
    /// Devuelve su ubicación final.
    public static func adopt(_ file: URL, named name: String, destinationRoot: URL, sourceName: String) throws -> URL {
        guard isSafeArchiveName(name) else { throw CocoaError(.fileWriteInvalidFileName) }
        let folder = directory(destinationRoot: destinationRoot, sourceName: sourceName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appending(path: name, directoryHint: .notDirectory)
        guard !FileManager.default.fileExists(atPath: target.path) else { throw CocoaError(.fileWriteFileExists) }
        try FileManager.default.moveItem(at: file, to: target)
        return target
    }

    /// `backup_<origen>_<yyyyMMdd_HHmmss>[_n].tar.gz` / `incr_…`.
    static func parse(name: String, sourceName: String) -> (kind: ArchiveInfo.Kind, date: Date?) {
        let kinds: [(String, ArchiveInfo.Kind)] = [("backup_", .full), ("incr_", .incremental)]
        for (prefix, kind) in kinds where name.hasPrefix(prefix + sourceName + "_") {
            let rest = name.dropFirst(prefix.count + sourceName.count + 1)
            let stamp = String(rest.prefix(15))   // yyyyMMdd_HHmmss
            return (kind, parseTimestamp(stamp))
        }
        return (.other, nil)
    }

    /// `yyyyMMdd_HHmmss` en hora local (como lo escribe `BackupEngine.timestamp`).
    static func parseTimestamp(_ stamp: String) -> Date? {
        let digits = stamp.replacingOccurrences(of: "_", with: "")
        guard stamp.count == 15, digits.count == 14, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else {
            return nil
        }
        func field(_ offset: Int, _ length: Int) -> Int? {
            let start = digits.index(digits.startIndex, offsetBy: offset)
            return Int(digits[start..<digits.index(start, offsetBy: length)])
        }
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian), timeZone: .current,
            year: field(0, 4), month: field(4, 2), day: field(6, 2),
            hour: field(8, 2), minute: field(10, 2), second: field(12, 2)
        )
        return components.isValidDate ? components.date : nil
    }
}
