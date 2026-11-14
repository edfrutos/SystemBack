import SwiftUI

/// Panel "Actividad": registro en vivo de la sesión (equivalente a la consola de la app original).
struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if let activity = model.activity {
                VStack(alignment: .leading, spacing: 6) {
                    Text(activity.title).font(.headline)
                    // Misma barra en ambas fases: indeterminada al escanear, determinada después (HIG).
                    ProgressView(value: activity.fraction)
                    if let detail = activity.detail {
                        Text(detail)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button("Cancel") { model.cancelActivity() }
                        .keyboardShortcut(.cancelAction)
                }
                .padding()
                Divider()
            }

            if model.log.isEmpty {
                ContentUnavailableView("No Activity", systemImage: "list.bullet.rectangle",
                                       description: Text("Backups and restores you run appear here."))
            } else {
                ScrollViewReader { proxy in
                    List(model.log) { entry in
                        LogRow(entry: entry).id(entry.id)
                    }
                    .listStyle(.plain)
                    .onChange(of: model.log.last?.id) { _, last in
                        if let last { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Clear Activity", systemImage: "trash") { model.clearLog() }
                    .help("Clear the activity log")
                    .disabled(model.log.isEmpty)
            }
        }
    }
}

private struct LogRow: View {
    let entry: AppModel.LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityLabel(levelName)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.text)
                    .font(.callout)
                    .textSelection(.enabled)
                Text(entry.date, format: .dateTime.hour().minute().second())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var symbol: String {
        switch entry.level {
        case .info: "info.circle"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch entry.level {
        case .info: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }

    private var levelName: LocalizedStringKey {
        switch entry.level {
        case .info: "Information"
        case .success: "Success"
        case .warning: "Warning"
        case .error: "Error"
        }
    }
}
