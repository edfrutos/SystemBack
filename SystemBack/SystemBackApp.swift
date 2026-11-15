import SwiftUI

/// Punto de entrada: fija el idioma antes de que SwiftUI cargue ningún texto.
@main
enum Launcher {
    static func main() {
        AppLanguage.applyAtLaunch()
        SystemBackApp.main()
    }
}

struct SystemBackApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("SystemBack", id: "main") {
            ContentView()
                .environment(model)
        }
        .commands {
            CommandGroup(replacing: .help) {
                Link("SystemBack Privacy Policy", destination: AppLinks.privacyPolicy)
                Link("SystemBack Support", destination: AppLinks.support)
            }
        }

        Settings {
            SettingsView().environment(model)
        }
    }
}
