import Foundation
import OSLog
import ServiceManagement
import UserNotifications

/// Notificaciones locales. El permiso se pide en contexto (primer backup), nunca al arrancar.
enum Notifications {
    // Logger es Sendable: se puede usar desde el callback de UNUserNotificationCenter.
    private nonisolated static let log = Logger(subsystem: "com.efjdev.systemback", category: "notifications")

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            log.error("Permiso de notificaciones: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { log.error("Notificación: \(error.localizedDescription, privacy: .public)") }
        }
    }
}

/// "Abrir al iniciar sesión" con SMAppService (2.4.5(iii): solo con consentimiento explícito).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Requiere aprobación del usuario en Ajustes del Sistema si el estado queda en `.requiresApproval`.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum AppLinks {
    static let privacyPolicy = URL(string: "https://systemback.efjdev.com/privacy")!
    static let support = URL(string: "https://systemback.efjdev.com/support")!
}
