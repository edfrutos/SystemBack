import AppKit
import AuthenticationServices
import Foundation
import Security
import SystemBackCore

/// Cliente OAuth de tipo iOS (sin secreto: el ID de cliente es público).
nonisolated enum GoogleConfig {
    static let oauth = GoogleOAuthConfig(
        clientID: "784383135948-i33ibsesd5b104itlhem007vthbbkab8.apps.googleusercontent.com",
        scopes: ["https://www.googleapis.com/auth/drive.file"]
    )
    /// Carpeta raíz en Drive; dentro, una subcarpeta por carpeta de origen.
    static let rootFolderName = "SystemBack"
}

/// Token de renovación en el Llavero del usuario (nunca en ficheros ni en UserDefaults).
nonisolated enum Keychain {
    struct Failure: Error, Equatable { let status: OSStatus }

    private static let service = "com.edefrutos.systemback.google"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read(_ account: String) -> String? {
        var item: CFTypeRef?
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(account)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure(status: added) }
        } else if status != errSecSuccess {
            throw Failure(status: status)
        }
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

/// Tokens de Google: el de renovación en el Llavero; el de acceso solo en memoria, renovado al caducar.
actor GoogleSession {
    static let shared = GoogleSession()

    private static let refreshAccount = "drive.refresh_token"
    private let oauth = GoogleOAuthClient(config: GoogleConfig.oauth)
    private var accessToken: String?
    private var expiry = Date.distantPast

    nonisolated static var isConnected: Bool { Keychain.read(refreshAccount) != nil }

    /// Cliente de Drive que pide un token válido en cada petición.
    nonisolated static var drive: DriveClient {
        DriveClient { try await GoogleSession.shared.validAccessToken() }
    }

    func store(_ tokens: OAuthTokens) throws {
        guard let refresh = tokens.refreshToken else { throw GoogleAPIError.invalidResponse }
        try Keychain.save(refresh, account: Self.refreshAccount)
        remember(tokens)
    }

    func validAccessToken() async throws -> String {
        if let accessToken, expiry > .now.addingTimeInterval(60) { return accessToken }
        guard let refresh = Keychain.read(Self.refreshAccount) else { throw GoogleAPIError.notConnected }
        do {
            let tokens = try await oauth.refresh(refresh)
            remember(tokens)
            return tokens.accessToken
        } catch GoogleAPIError.authorizationRevoked {
            forget()
            throw GoogleAPIError.authorizationRevoked
        }
    }

    /// Revoca en Google (si hay red) y borra el token local en cualquier caso.
    func disconnect() async {
        if let refresh = Keychain.read(Self.refreshAccount) {
            try? await oauth.revoke(refresh)
        }
        forget()
    }

    private func remember(_ tokens: OAuthTokens) {
        accessToken = tokens.accessToken
        expiry = .now.addingTimeInterval(TimeInterval(tokens.expiresIn))
    }

    private func forget() {
        Keychain.delete(Self.refreshAccount)
        accessToken = nil
        expiry = .distantPast
    }
}

/// Inicio de sesión con ASWebAuthenticationSession + PKCE (sin servidor local ni secreto).
final class GoogleSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func signIn() async throws -> OAuthTokens {
        let config = GoogleConfig.oauth
        let pkce = PKCE.random()
        let state = UUID().uuidString
        let url = config.authorizationURL(pkce: pkce, state: state)

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            // @Sendable: el sistema puede llamar al cierre fuera del hilo principal.
            let completion: @Sendable (URL?, (any Error)?) -> Void = { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: error ?? GoogleAPIError.invalidCallback)
                }
            }
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: config.callbackScheme,
                                                     completionHandler: completion)
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                continuation.resume(throwing: GoogleAPIError.invalidCallback)
            }
        }
        session = nil
        let client = GoogleOAuthClient(config: config)
        return try await client.exchange(code: try client.code(from: callback, expectedState: state), pkce: pkce)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}
