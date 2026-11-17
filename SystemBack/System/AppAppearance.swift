import AppKit
import SwiftUI

/// Aspecto de la app: automático (el del sistema, por defecto), claro u oscuro.
///
/// Se aplica con `NSApp.appearance`, que afecta a todas las ventanas (también a Ajustes)
/// sin reiniciar. Con `.automatic` se quita el valor y la app vuelve a seguir al sistema,
/// incluido el cambio automático de día y noche.
enum AppAppearance: String, CaseIterable, Identifiable {
    case automatic
    case light
    case dark

    static let defaultsKey = "SBAppearance"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .automatic: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    static var selected: AppAppearance {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(AppAppearance.init(rawValue:)) ?? .automatic
    }

    static func select(_ appearance: AppAppearance) {
        if appearance == .automatic {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            UserDefaults.standard.set(appearance.rawValue, forKey: defaultsKey)
        }
        apply(appearance)
    }

    static func apply(_ appearance: AppAppearance) {
        NSApp.appearance = switch appearance {
        case .automatic: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Aplica el aspecto guardado antes de que se muestre ninguna ventana.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppAppearance.apply(.selected)
    }
}
