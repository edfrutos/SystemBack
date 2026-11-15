import Foundation

/// Referencia persistente a una carpeta elegida por el usuario (security-scoped bookmark).
public struct FolderReference: Codable, Hashable, Sendable {
    public var bookmark: Data
    /// Ruta para mostrar; nunca se usa para acceder (no tiene security scope).
    public var displayPath: String

    public init(bookmark: Data, displayPath: String) {
        self.bookmark = bookmark
        self.displayPath = displayPath
    }

    /// Crea la bookmark a partir de una URL obtenida de NSOpenPanel / fileImporter.
    public static func make(from url: URL) throws -> FolderReference {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        return FolderReference(bookmark: data, displayPath: url.path)
    }

    /// Resuelve la bookmark. Si estaba obsoleta, devuelve también la referencia renovada para guardarla.
    public func resolve() throws -> (url: URL, renewed: FolderReference?) {
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                          relativeTo: nil, bookmarkDataIsStale: &isStale)
        guard isStale else { return (url, nil) }
        return (url, try? FolderReference.make(from: url))
    }
}

/// Ejecuta `body` con acceso a la carpeta, equilibrando start/stop (evita fugas de recursos del kernel).
public func withSecurityScopedAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T {
    let didStart = url.startAccessingSecurityScopedResource()
    defer { if didStart { url.stopAccessingSecurityScopedResource() } }
    return try body()
}

/// Una ejecución terminada, para el historial.
public struct BackupRecord: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case full, incremental }

    public var id: UUID
    public var date: Date
    public var kind: Kind
    public var archiveName: String
    public var fileCount: Int
    public var contentBytes: UInt64
    public var archiveBytes: UInt64

    public init(id: UUID = UUID(), date: Date, kind: Kind, archiveName: String,
                fileCount: Int, contentBytes: UInt64, archiveBytes: UInt64) {
        self.id = id
        self.date = date
        self.kind = kind
        self.archiveName = archiveName
        self.fileCount = fileCount
        self.contentBytes = contentBytes
        self.archiveBytes = archiveBytes
    }
}

/// Trabajo de backup configurado por el usuario: origen → destino.
public struct BackupJob: Codable, Hashable, Sendable, Identifiable {
    public static let historyLimit = 200

    public var id: UUID
    public var name: String
    public var source: FolderReference
    public var destination: FolderReference
    public var exclusions: ExclusionRules
    public var history: [BackupRecord]
    /// Subir cada backup nuevo a Google Drive (opcional; requiere cuenta conectada).
    public var uploadsToDrive: Bool

    public init(id: UUID = UUID(), name: String, source: FolderReference, destination: FolderReference,
                exclusions: ExclusionRules = .default, history: [BackupRecord] = [], uploadsToDrive: Bool = false) {
        self.id = id
        self.name = name
        self.source = source
        self.destination = destination
        self.exclusions = exclusions
        self.history = history
        self.uploadsToDrive = uploadsToDrive
    }

    /// Lee también los `jobs.json` anteriores a `uploadsToDrive`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        source = try container.decode(FolderReference.self, forKey: .source)
        destination = try container.decode(FolderReference.self, forKey: .destination)
        exclusions = try container.decode(ExclusionRules.self, forKey: .exclusions)
        history = try container.decode([BackupRecord].self, forKey: .history)
        uploadsToDrive = try container.decodeIfPresent(Bool.self, forKey: .uploadsToDrive) ?? false
    }

    public var lastBackupDate: Date? { history.first?.date }

    /// Más reciente primero, con límite (igual que el registro de la herramienta Python).
    public mutating func record(_ entry: BackupRecord) {
        history.insert(entry, at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
    }
}

/// Persistencia en JSON (D11) dentro de Application Support del contenedor.
public struct JobStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/SystemBack/jobs.json`; en sandbox, dentro del contenedor.
    public static func standard() throws -> JobStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return JobStore(fileURL: base.appending(path: "SystemBack/jobs.json"))
    }

    public func load() throws -> [BackupJob] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoredJobs.self, from: Data(contentsOf: fileURL)).jobs
    }

    public func save(_ jobs: [BackupJob]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(StoredJobs(jobs: jobs)).write(to: fileURL, options: .atomic)
    }

    /// Envoltorio versionado para poder migrar el formato.
    private struct StoredJobs: Codable {
        var version = 1
        var jobs: [BackupJob]
    }
}
