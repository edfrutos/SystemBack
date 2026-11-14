import AppKit

/// Selector de carpeta con NSOpenPanel (Powerbox del sandbox).
/// Se usa en lugar de `.fileImporter` cuando la acción sale de un menú: el panel se abre
/// por su cuenta y no depende del estado de presentación de SwiftUI mientras el menú se cierra.
enum FolderPicker {
    static func chooseFolder(message: String, prompt: String) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = prompt
        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}
