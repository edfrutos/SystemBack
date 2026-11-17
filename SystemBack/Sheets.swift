import SwiftUI
import SystemBackCore
import UniformTypeIdentifiers

/// Fila "etiqueta · ruta · Elegir…" con su propio selector de carpeta o fichero.
private struct LocationPicker: View {
    let title: LocalizedStringKey
    let types: [UTType]
    @Binding var url: URL?
    @State private var isPicking = false

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(url.map { PathDisplay.abbreviatingHome($0.path) } ?? String(localized: "Not selected"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(url == nil ? .secondary : .primary)
                Button("Choose…") { isPicking = true }
            }
        }
        .fileImporter(isPresented: $isPicking, allowedContentTypes: types) { result in
            if case let .success(picked) = result { url = picked }
        }
    }
}

struct NewJobSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var source: URL?
    @State private var destination: URL?
    @State private var errorMessage: String?

    private var canSave: Bool {
        source != nil && destination != nil && source != destination
    }

    var body: some View {
        Form {
            LocationPicker(title: "Folder to back up", types: [.folder], url: $source)
            LocationPicker(title: "Save backups in", types: [.folder], url: $destination)
            TextField("Name", text: $name, prompt: Text(source?.lastPathComponent ?? ""))
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create Job") { save() }
                    .disabled(!canSave)
            }
        }
    }

    private func save() {
        guard let source, let destination else { return }
        let finalName = name.trimmingCharacters(in: .whitespaces).isEmpty ? source.lastPathComponent : name
        do {
            try model.addJob(name: finalName, source: source, destination: destination)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RestoreSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var archive: URL?
    @State private var parent: URL?

    var body: some View {
        Form {
            LocationPicker(title: "Backup file", types: [.gzip], url: $archive)
            LocationPicker(title: "Restore into", types: [.folder], url: $parent)
            Text("Files are restored into a new folder. Existing files are never overwritten.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Restore") {
                    guard let archive, let parent else { return }
                    model.startRestore(archive: archive, intoParent: parent)
                    dismiss()
                }
                .disabled(archive == nil || parent == nil)
            }
        }
    }
}
