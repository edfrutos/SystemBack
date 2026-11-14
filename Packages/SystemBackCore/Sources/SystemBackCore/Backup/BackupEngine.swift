import Foundation

/// Qué ficheros no se copian. Por defecto solo metadatos de Finder.
public struct ExclusionRules: Sendable, Codable, Hashable {
    /// Nombres exactos de fichero o carpeta (en cualquier nivel).
    public var names: Set<String>
    /// Extensiones sin punto, en minúsculas.
    public var extensions: Set<String>

    public init(names: Set<String> = [".DS_Store"], extensions: Set<String> = []) {
        self.names = names
        self.extensions = extensions
    }

    public static let `default` = ExclusionRules()

    func excludes(components: [String]) -> Bool {
        if components.contains(where: names.contains) { return true }
        guard let last = components.last, let dot = last.lastIndex(of: "."), dot != last.startIndex else {
            return false
        }
        return extensions.contains(last[last.index(after: dot)...].lowercased())
    }
}

public enum BackupKind: Sendable, Equatable {
    case full
    /// Solo ficheros con fecha de modificación posterior a `since`.
    case incremental(since: Date)

    var filePrefix: String {
        switch self {
        case .full: "backup"
        case .incremental: "incr"
        }
    }
}

public struct BackupRequest: Sendable {
    public var source: URL
    /// Carpeta raíz de destino; el archivo se crea en `<destinationRoot>/<nombre origen>/`.
    public var destinationRoot: URL
    public var kind: BackupKind
    public var exclusions: ExclusionRules
    public var date: Date

    public init(
        source: URL,
        destinationRoot: URL,
        kind: BackupKind = .full,
        exclusions: ExclusionRules = .default,
        date: Date = .now
    ) {
        self.source = source
        self.destinationRoot = destinationRoot
        self.kind = kind
        self.exclusions = exclusions
        self.date = date
    }
}

public struct BackupProgress: Sendable, Equatable {
    public var processedFiles: Int
    public var totalFiles: Int
    public var processedBytes: UInt64
    public var totalBytes: UInt64

    public var fractionCompleted: Double {
        totalBytes == 0 ? (totalFiles == 0 ? 1 : Double(processedFiles) / Double(totalFiles))
            : Double(processedBytes) / Double(totalBytes)
    }
}

public struct BackupResult: Sendable, Equatable {
    public var archiveURL: URL
    public var fileCount: Int
    /// Bytes sin comprimir copiados.
    public var contentBytes: UInt64
    public var archiveBytes: UInt64
}

public enum BackupOutcome: Sendable, Equatable {
    case created(BackupResult)
    /// Incremental sin cambios desde la fecha indicada: no se crea archivo.
    case noChanges
}

public enum BackupError: Error, Equatable, Sendable {
    case sourceNotADirectory(URL)
}

/// Crea backups `.tar.gz` de una carpeta. Síncrono y cancelable (`Task.checkCancellation`):
/// el llamador decide en qué contexto se ejecuta (p. ej. una función `@concurrent`).
public struct BackupEngine: Sendable {
    public init() {}

    public func run(
        _ request: BackupRequest,
        progress: @Sendable (BackupProgress) -> Void = { _ in }
    ) throws -> BackupOutcome {
        let fileManager = FileManager.default
        let source = request.source.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BackupError.sourceNotADirectory(source)
        }

        let destinationDirectory = request.destinationRoot.standardizedFileURL
            .appending(path: source.lastPathComponent, directoryHint: .isDirectory)
        let items = try scan(source: source, request: request, skipping: request.destinationRoot)

        let files = items.filter { !$0.isDirectory }
        if case .incremental = request.kind, files.isEmpty { return .noChanges }

        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let finalURL = Self.uniqueArchiveURL(
            in: destinationDirectory, prefix: request.kind.filePrefix,
            sourceName: source.lastPathComponent, date: request.date
        )
        let partialURL = finalURL.appendingPathExtension("partial")

        let totalBytes = files.reduce(UInt64(0)) { $0 + $1.size }
        var state = BackupProgress(processedFiles: 0, totalFiles: files.count, processedBytes: 0, totalBytes: totalBytes)
        progress(state)

        let gzip = try GzipFileWriter(creating: partialURL)
        do {
            var tar = TarWriter { try gzip.write($0) }
            for item in items {
                try Task.checkCancellation()
                if item.isDirectory {
                    try tar.addDirectory(path: item.archivePath, modificationDate: item.modificationDate)
                    continue
                }
                try tar.addFile(
                    path: item.archivePath, contentsOf: item.url, size: item.size,
                    modificationDate: item.modificationDate, mode: item.mode
                ) { bytes in
                    state.processedBytes += UInt64(bytes)
                    progress(state)
                }
                state.processedFiles += 1
                progress(state)
            }
            try tar.finish()
            try gzip.finish()
            try fileManager.moveItem(at: partialURL, to: finalURL)
        } catch {
            gzip.abandon()
            try? fileManager.removeItem(at: partialURL)
            throw error
        }

        let archiveBytes = (try? fileManager.attributesOfItem(atPath: finalURL.path)[.size] as? UInt64) ?? 0
        return .created(BackupResult(
            archiveURL: finalURL, fileCount: files.count,
            contentBytes: totalBytes, archiveBytes: archiveBytes
        ))
    }

    // MARK: - Recorrido

    struct Item {
        var url: URL
        var archivePath: String
        var isDirectory: Bool
        var size: UInt64
        var modificationDate: Date
        var mode: UInt32
    }

    func scan(source: URL, request: BackupRequest, skipping excludedRoot: URL) throws -> [Item] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: source, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return [] }

        // Rutas canónicas (p. ej. /var → /private/var) para comparar sin depender de enlaces.
        let sourceComponents = source.resolvingSymlinksInPath().pathComponents
        let excludedPath = excludedRoot.resolvingSymlinksInPath().path
        let since: Date? = if case let .incremental(date) = request.kind { date } else { nil }
        var items: [Item] = []

        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: Set(keys))
            // Los enlaces simbólicos no se siguen ni se archivan.
            if values.isSymbolicLink == true { continue }
            // Se canoniza el padre, nunca el propio elemento.
            let standardized = url.deletingLastPathComponent().resolvingSymlinksInPath()
                .appending(path: url.lastPathComponent)
            // Nunca meter el propio destino si está dentro del origen.
            if standardized.path == excludedPath || standardized.path.hasPrefix(excludedPath + "/") {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            let components = Array(standardized.pathComponents.dropFirst(sourceComponents.count))
            guard !components.isEmpty else { continue }
            if request.exclusions.excludes(components: components) {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }

            let modificationDate = values.contentModificationDate ?? .distantPast
            let archivePath = components.joined(separator: "/")

            if values.isDirectory == true {
                // En incrementales solo se registran ficheros cambiados.
                if since == nil {
                    items.append(Item(url: url, archivePath: archivePath, isDirectory: true,
                                      size: 0, modificationDate: modificationDate, mode: 0o755))
                }
            } else if values.isRegularFile == true {
                if let since, modificationDate <= since { continue }
                let permissions = (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
                    as? NSNumber)?.uint32Value ?? 0o644
                items.append(Item(url: url, archivePath: archivePath, isDirectory: false,
                                  size: UInt64(values.fileSize ?? 0), modificationDate: modificationDate,
                                  mode: permissions & 0o777))
            }
        }
        return items
    }

    // MARK: - Nombres

    static func timestamp(_ date: Date) -> String {
        date.formatted(Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)_\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: .current,
            calendar: Calendar(identifier: .gregorian)
        ))
    }

    /// `<prefijo>_<origen>_<yyyyMMdd_HHmmss>.tar.gz`, igual que la herramienta Python.
    static func uniqueArchiveURL(in directory: URL, prefix: String, sourceName: String, date: Date) -> URL {
        let base = "\(prefix)_\(sourceName)_\(timestamp(date))"
        var candidate = directory.appending(path: base + ".tar.gz")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(base)_\(counter).tar.gz")
            counter += 1
        }
        return candidate
    }
}
