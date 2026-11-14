import SwiftUI

@main
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
            SettingsView()
        }
    }
}
