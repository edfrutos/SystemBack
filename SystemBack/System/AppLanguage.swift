import AppKit
import Foundation

/// Idioma de la interfaz. Español por defecto; inglés opcional en Ajustes.
/// Se aplica con `AppleLanguages` (dominio de la app) antes de cargar la interfaz, por eso
/// el cambio necesita reiniciar la app. Es el mismo ajuste que macOS usa para el idioma por app.
enum AppLanguage: String, CaseIterable, Identifiable {
    case spanish = "es"
    case english = "en"

    static let defaultsKey = "SBInterfaceLanguage"
    static let `default`: AppLanguage = .spanish

    var id: String { rawValue }

    /// Nombre en su propio idioma, como en los selectores del sistema.
    var displayName: String {
        switch self {
        case .spanish: "Español"
        case .english: "English"
        }
    }

    static var selected: AppLanguage {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(AppLanguage.init(rawValue:)) ?? .default
    }

    /// Idioma con el que arrancó la sesión actual.
    private(set) static var atLaunch: AppLanguage = .default

    static func select(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: defaultsKey)
        apply(language)
    }

    /// Llamar antes de crear la app SwiftUI.
    static func applyAtLaunch() {
        atLaunch = selected
        apply(atLaunch)
    }

    private static func apply(_ language: AppLanguage) {
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
    }

    /// Abre una instancia nueva y cierra esta (sin procesos auxiliares).
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
