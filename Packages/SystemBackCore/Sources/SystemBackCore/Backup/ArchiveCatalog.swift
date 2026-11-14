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
