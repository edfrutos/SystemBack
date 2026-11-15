import Foundation
import Testing
@testable import SystemBackCore

/// Servidor simulado: cada test fija `handler`. La suite va en serie porque el handler es global.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (status, headers, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite("Google Drive", .serialized)
struct GoogleDriveTests {
    let config = GoogleOAuthConfig(
        clientID: "123-abc.apps.googleusercontent.com",
        scopes: ["https://www.googleapis.com/auth/drive.file"]
    )

    init() {
        MockURLProtocol.handler = nil
        MockURLProtocol.requests = []
    }

    @Test func `PKCE coincide con el vector de RFC 7636`() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(PKCE.random().verifier.count == 43)
        #expect(PKCE.random() != PKCE.random())
    }

    @Test func `URL de autorización y esquema de vuelta del cliente iOS`() throws {
        #expect(config.callbackScheme == "com.googleusercontent.apps.123-abc")
        #expect(config.redirectURI == "com.googleusercontent.apps.123-abc:/oauth2redirect")
        let pkce = PKCE(verifier: "v")
        let url = config.authorizationURL(pkce: pkce, state: "s1")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(query["client_id"] == config.clientID)
        #expect(query["code_challenge"] == pkce.challenge)
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["scope"] == "https://www.googleapis.com/auth/drive.file")
        #expect(query["state"] == "s1")
    }

    @Test func `el código solo se acepta con el state esperado`() throws {
        let client = GoogleOAuthClient(config: config)
        let callback = URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?state=s1&code=4/xyz")!
        #expect(try client.code(from: callback, expectedState: "s1") == "4/xyz")
        #expect(throws: GoogleAPIError.invalidCallback) { try client.code(from: callback, expectedState: "otro") }
    }

    @Test func `canje envía verificador y decodifica tokens`() async throws {
        MockURLProtocol.handler = { request in
            (200, ["Content-Type": "application/json"],
             Data(#"{"access_token":"at","expires_in":3599,"refresh_token":"rt","scope":"drive.file"}"#.utf8))
        }
        let client = GoogleOAuthClient(config: config, session: MockURLProtocol.session())
        let tokens = try await client.exchange(code: "4/xyz", pkce: PKCE(verifier: "ver+ifier"))
        #expect(tokens == OAuthTokens(accessToken: "at", expiresIn: 3599, refreshToken: "rt", scope: "drive.file"))
        let sent = try #require(MockURLProtocol.requests.first)
        #expect(sent.url == GoogleOAuthClient.tokenEndpoint)
        let body = try #require(sent.httpBodyStream.map(Self.read) ?? sent.httpBody)
        let form = String(decoding: body, as: UTF8.self)
        #expect(form.contains("code_verifier=ver%2Bifier"))
        #expect(form.contains("grant_type=authorization_code"))
        #expect(!form.contains("client_secret"))
    }

    @Test func `invalid_grant se traduce en acceso retirado`() async {
        MockURLProtocol.handler = { _ in (400, [:], Data(#"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#.utf8)) }
        let client = GoogleOAuthClient(config: config, session: MockURLProtocol.session())
        await #expect(throws: GoogleAPIError.authorizationRevoked) { try await client.refresh("rt") }
    }

    @Test func `subida reanudable: inicia sesión y envía el archivo`() async throws {
        let sandbox = TemporaryDirectory()
        try sandbox.write("contenido", to: "backup.tar.gz")
        let file = sandbox.url.appending(path: "backup.tar.gz")
        MockURLProtocol.handler = { request in
            if request.httpMethod == "POST" {
                return (200, ["Location": "https://upload.example/session/1"], Data())
            }
            return (200, [:], Data(#"{"id":"f1","name":"backup.tar.gz","size":"9","createdTime":"2026-11-14T17:00:00.123Z"}"#.utf8))
        }
        let drive = DriveClient(session: MockURLProtocol.session(), token: { "tok" })
        let uploaded = try await drive.upload(fileAt: file, name: "backup.tar.gz", parent: "folder1")

        #expect(uploaded.id == "f1")
        #expect(uploaded.size == 9)
        #expect(uploaded.createdTime != nil)
        let start = try #require(MockURLProtocol.requests.first)
        #expect(start.url?.query?.contains("uploadType=resumable") == true)
        #expect(start.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(start.value(forHTTPHeaderField: "X-Upload-Content-Length") == "9")
        let put = try #require(MockURLProtocol.requests.last)
        #expect(put.httpMethod == "PUT")
        #expect(put.url?.absoluteString == "https://upload.example/session/1")
    }

    @Test func `lista por páginas y error de la API con mensaje`() async throws {
        MockURLProtocol.handler = { request in
            let query = request.url?.query ?? ""
            if query.contains("pageToken=p2") {
                return (200, [:], Data(#"{"files":[{"id":"b","name":"b.tar.gz"}]}"#.utf8))
            }
            return (200, [:], Data(#"{"nextPageToken":"p2","files":[{"id":"a","name":"a.tar.gz","size":"5"}]}"#.utf8))
        }
        let drive = DriveClient(session: MockURLProtocol.session(), token: { "tok" })
        let files = try await drive.list(inFolder: "folder1")
        #expect(files.map(\.id) == ["a", "b"])

        MockURLProtocol.handler = { _ in (403, [:], Data(#"{"error":{"code":403,"message":"Rate limit"}}"#.utf8)) }
        await #expect(throws: GoogleAPIError.http(status: 403, message: "Rate limit")) {
            try await drive.list(inFolder: "folder1")
        }
    }

    @Test func `carpeta vacía: Google omite la clave files`() async throws {
        MockURLProtocol.handler = { _ in (200, [:], Data("{}".utf8)) }
        let drive = DriveClient(session: MockURLProtocol.session(), token: { "tok" })
        #expect(try await drive.list(inFolder: "folder1").isEmpty)
    }

    @Test func `crea la carpeta si no existe (la respuesta solo trae id)`() async throws {
        MockURLProtocol.handler = { request in
            request.httpMethod == "POST"
                ? (200, [:], Data(#"{"id":"new1"}"#.utf8))
                : (200, [:], Data("{}".utf8))
        }
        let drive = DriveClient(session: MockURLProtocol.session(), token: { "tok" })
        #expect(try await drive.findOrCreateFolder(named: "SystemBack", parent: nil) == "new1")
    }

    @Test func `comillas en nombres se escapan en las consultas`() {
        #expect(DriveClient.escape("Fotos d'Ana") == "Fotos d\\'Ana")
        #expect(DriveClient.escape(#"a\b"#) == #"a\\b"#)
    }

    static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
