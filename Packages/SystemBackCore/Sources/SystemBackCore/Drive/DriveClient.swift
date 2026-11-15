import Foundation
import os

public struct DriveFile: Sendable, Hashable, Identifiable, Decodable {
    public var id: String
    public var name: String
    public var size: UInt64?
    public var createdTime: Date?

    public init(id: String, name: String, size: UInt64? = nil, createdTime: Date? = nil) {
        self.id = id
        self.name = name
        self.size = size
        self.createdTime = createdTime
    }

    enum CodingKeys: String, CodingKey { case id, name, size, createdTime }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        // Drive devuelve `size` como cadena (int64 en JSON).
        size = (try container.decodeIfPresent(String.self, forKey: .size)).flatMap(UInt64.init)
        createdTime = (try container.decodeIfPresent(String.self, forKey: .createdTime))
            .flatMap { try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse($0) }
    }
}

/// Cliente REST mínimo de Google Drive v3 con el scope `drive.file`
/// (solo ve y gestiona los archivos que crea la propia app).
public struct DriveClient: Sendable {
    public typealias TokenProvider = @Sendable () async throws -> String

    static let folderMimeType = "application/vnd.google-apps.folder"
    static let api = URL(string: "https://www.googleapis.com/drive/v3/")!
    static let uploadAPI = URL(string: "https://www.googleapis.com/upload/drive/v3/files")!
    static let fileFields = "id,name,size,createdTime"
    static let log = Logger(subsystem: "com.edefrutos.systemback", category: "Drive")

    let session: URLSession
    let token: TokenProvider

    public init(session: URLSession = .shared, token: @escaping TokenProvider) {
        self.session = session
        self.token = token
    }

    /// Busca la carpeta por nombre (dentro de `parent`, o en la raíz) y la crea si no existe.
    public func findOrCreateFolder(named name: String, parent: String?) async throws -> String {
        var query = "name = '\(Self.escape(name))' and mimeType = '\(Self.folderMimeType)' and trashed = false"
        query += parent.map { " and '\(Self.escape($0))' in parents" } ?? " and 'root' in parents"
        if let existing = try await files(matching: query).first { return existing.id }

        var request = try await authorized(URL(string: "files?fields=id", relativeTo: Self.api)!)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        var metadata: [String: Any] = ["name": name, "mimeType": Self.folderMimeType]
        if let parent { metadata["parents"] = [parent] }
        request.httpBody = try JSONSerialization.data(withJSONObject: metadata)
        // Con `fields=id` la respuesta solo trae el identificador.
        struct Created: Decodable { var id: String }
        return try decode(Created.self, from: try await GoogleHTTP.send(request, session: session)).id
    }

    /// Archivos (no carpetas) de una carpeta, sin los de la papelera.
    public func list(inFolder folderID: String) async throws -> [DriveFile] {
        try await files(matching: "'\(Self.escape(folderID))' in parents and trashed = false and mimeType != '\(Self.folderMimeType)'")
    }

    /// Subida reanudable: se inicia la sesión y se envía el archivo desde disco (sin cargarlo en memoria).
    public func upload(
        fileAt url: URL,
        name: String,
        parent: String,
        mimeType: String = "application/gzip",
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> DriveFile {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        var components = URLComponents(url: Self.uploadAPI, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "uploadType", value: "resumable"),
                                 URLQueryItem(name: "fields", value: Self.fileFields)]
        var start = try await authorized(components.url!)
        start.httpMethod = "POST"
        start.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        start.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        start.setValue(String(size), forHTTPHeaderField: "X-Upload-Content-Length")
        start.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "parents": [parent]])

        let (startData, startResponse) = try await session.data(for: start)
        try GoogleHTTP.check(startResponse, data: startData)
        guard let location = (startResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: location) else { throw GoogleAPIError.invalidResponse }

        var put = URLRequest(url: uploadURL)
        put.httpMethod = "PUT"
        put.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: put, fromFile: url, delegate: UploadProgress(progress))
        try GoogleHTTP.check(response, data: data)
        progress(1)
        return try decode(DriveFile.self, from: data)
    }

    /// A la papelera de Drive (recuperable 30 días), no borrado definitivo.
    public func trash(_ fileID: String) async throws {
        var request = try await authorized(URL(string: "files/\(fileID)", relativeTo: Self.api)!)
        request.httpMethod = "PATCH"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["trashed": true])
        _ = try await GoogleHTTP.send(request, session: session)
    }

    /// Descarga el contenido a `destination` (se sobrescribe si existe).
    /// Sin indicador de progreso: la API async de descarga no informa de los bytes recibidos.
    public func download(_ fileID: String, to destination: URL) async throws {
        let request = try await authorized(URL(string: "files/\(fileID)?alt=media", relativeTo: Self.api)!)
        let (temporary, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let data = (try? Data(contentsOf: temporary)) ?? Data()
            throw GoogleHTTP.error(status: http.statusCode, data: data)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    /// Correo de la cuenta conectada, para mostrarlo en Ajustes (opcional).
    public func accountEmail() async throws -> String? {
        let request = try await authorized(URL(string: "about?fields=user(emailAddress)", relativeTo: Self.api)!)
        let data = try await GoogleHTTP.send(request, session: session)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["user"] as? [String: Any])?["emailAddress"] as? String
    }

    // MARK: - Utilidades

    private func files(matching query: String) async throws -> [DriveFile] {
        struct Page: Decodable {
            // Con `fields`, Google omite la clave si la lista está vacía.
            var files: [DriveFile]?
            var nextPageToken: String?
        }
        var result: [DriveFile] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(url: URL(string: "files", relativeTo: Self.api)!.absoluteURL,
                                           resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "fields", value: "nextPageToken,files(\(Self.fileFields))"),
                URLQueryItem(name: "pageSize", value: "1000"),
                URLQueryItem(name: "spaces", value: "drive"),
            ]
            if let pageToken { components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page = try decode(Page.self, from: try await GoogleHTTP.send(try await authorized(components.url!), session: session))
            result += page.files ?? []
            pageToken = page.nextPageToken
        } while pageToken != nil
        return result
    }

    private func authorized(_ url: URL) async throws -> URLRequest {
        var request = URLRequest(url: url.absoluteURL)
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Self.log.error("Respuesta de Drive no decodificable (\(String(describing: type), privacy: .public)): \(String(describing: error), privacy: .public) — \(String(decoding: data.prefix(500), as: UTF8.self), privacy: .private)")
            throw GoogleAPIError.invalidResponse
        }
    }

    /// Escapa comillas y barras invertidas dentro de un literal de consulta de Drive.
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    }
}

/// Progreso de envío de una tarea concreta (delegado por tarea de URLSession).
private final class UploadProgress: NSObject, URLSessionTaskDelegate, Sendable {
    let handler: @Sendable (Double) -> Void

    init(_ handler: @escaping @Sendable (Double) -> Void) {
        self.handler = handler
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        handler(min(Double(totalBytesSent) / Double(totalBytesExpectedToSend), 0.99))
    }
}
