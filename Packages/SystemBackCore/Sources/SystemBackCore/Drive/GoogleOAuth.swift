import CryptoKit
import Foundation

/// Par PKCE (RFC 7636, método S256). El verificador nunca sale del Mac salvo en el canje del código.
public struct PKCE: Sendable, Equatable {
    public let verifier: String
    public let challenge: String

    public init(verifier: String) {
        self.verifier = verifier
        challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// 32 bytes aleatorios (generador criptográfico del sistema) → 43 caracteres base64url.
    public static func random() -> PKCE {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return PKCE(verifier: base64URL(Data(bytes)))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Cliente OAuth de tipo iOS (sin secreto): el redirect usa el client ID invertido como esquema.
public struct GoogleOAuthConfig: Sendable, Equatable {
    public var clientID: String
    public var scopes: [String]

    public init(clientID: String, scopes: [String]) {
        self.clientID = clientID
        self.scopes = scopes
    }

    /// `com.googleusercontent.apps.<id>`
    public var callbackScheme: String {
        let suffix = ".apps.googleusercontent.com"
        let id = clientID.hasSuffix(suffix) ? String(clientID.dropLast(suffix.count)) : clientID
        return "com.googleusercontent.apps." + id
    }

    public var redirectURI: String { callbackScheme + ":/oauth2redirect" }

    public func authorizationURL(pkce: PKCE, state: String) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }
}

public struct OAuthTokens: Sendable, Equatable, Decodable {
    public var accessToken: String
    public var expiresIn: Int
    /// Solo llega en el primer canje (y no en las renovaciones).
    public var refreshToken: String?
    public var scope: String?

    public init(accessToken: String, expiresIn: Int, refreshToken: String? = nil, scope: String? = nil) {
        self.accessToken = accessToken
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.scope = scope
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

public enum GoogleAPIError: Error, Equatable, Sendable {
    /// No hay cuenta conectada (sin token de renovación en el Llavero).
    case notConnected
    /// El usuario retiró el acceso o el token caducó (`invalid_grant`): hay que volver a conectar.
    case authorizationRevoked
    /// El `state` devuelto no coincide (posible respuesta ajena) o falta el código.
    case invalidCallback
    case invalidResponse
    case http(status: Int, message: String)
}

/// Canje, renovación y revocación de tokens contra los endpoints de Google.
public struct GoogleOAuthClient: Sendable {
    public let config: GoogleOAuthConfig
    let session: URLSession

    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!

    public init(config: GoogleOAuthConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// Extrae el código del redirect comprobando el `state` (protección CSRF).
    public func code(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == expectedState else { throw GoogleAPIError.invalidCallback }
        if let error = value("error") { throw GoogleAPIError.http(status: 400, message: error) }
        guard let code = value("code"), !code.isEmpty else { throw GoogleAPIError.invalidCallback }
        return code
    }

    public func exchange(code: String, pkce: PKCE) async throws -> OAuthTokens {
        try await token([
            "code": code,
            "client_id": config.clientID,
            "redirect_uri": config.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": pkce.verifier,
        ])
    }

    public func refresh(_ refreshToken: String) async throws -> OAuthTokens {
        try await token([
            "refresh_token": refreshToken,
            "client_id": config.clientID,
            "grant_type": "refresh_token",
        ])
    }

    public func revoke(_ token: String) async throws {
        _ = try await GoogleHTTP.send(Self.formRequest(Self.revokeEndpoint, ["token": token]), session: session)
    }

    private func token(_ fields: [String: String]) async throws -> OAuthTokens {
        let data = try await GoogleHTTP.send(Self.formRequest(Self.tokenEndpoint, fields), session: session)
        do {
            return try JSONDecoder().decode(OAuthTokens.self, from: data)
        } catch {
            throw GoogleAPIError.invalidResponse
        }
    }

    static func formRequest(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncode(fields).utf8)
        return request
    }

    /// `application/x-www-form-urlencoded` estricto (solo sin reservar de RFC 3986 queda sin codificar).
    static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
    }
}

/// Envío común: 2xx devuelve el cuerpo; el resto se traduce a `GoogleAPIError`.
enum GoogleHTTP {
    static func send(_ request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try check(response, data: data)
        return data
    }

    static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw GoogleAPIError.invalidResponse }
        guard !(200..<300).contains(http.statusCode) else { return }
        throw error(status: http.statusCode, data: data)
    }

    /// Formatos de error de Google: OAuth `{"error": "...", "error_description": "..."}`
    /// y APIs `{"error": {"code": 403, "message": "..."}}`.
    static func error(status: Int, data: Data) -> GoogleAPIError {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let code = json?["error"] as? String {
            if code == "invalid_grant" { return .authorizationRevoked }
            return .http(status: status, message: (json?["error_description"] as? String) ?? code)
        }
        if let detail = json?["error"] as? [String: Any], let message = detail["message"] as? String {
            return .http(status: status, message: message)
        }
        return .http(status: status, message: HTTPURLResponse.localizedString(forStatusCode: status))
    }
}
