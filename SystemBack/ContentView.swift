import SwiftUI
import SystemBackCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: BackupJob.ID?
    @State private var isAddingJob = false
    @State private var isRestoring = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(model.jobs, selection: $selection) { job in
                JobRow(job: job)
                    .contextMenu {
                        Button("Delete Job", role: .destructive) { model.removeJob(job.id) }
                    }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .overlay {
                if model.jobs.isEmpty {
                    ContentUnavailableView {
                        Label("No Backup Jobs", systemImage: "externaldrive.badge.plus")
                    } description: {
                        Text("Choose a folder to back up and where to save its backups.")
                    } actions: {
                        Button("New Backup Job…") { isAddingJob = true }
                    }
                }
            }
        } detail: {
            if let job = model.jobs.first(where: { $0.id == selection }) {
                JobDetailView(job: job)
            } else if !model.jobs.isEmpty {
                ContentUnavailableView("Select a Backup Job", systemImage: "sidebar.left")
            }
        }
        .toolbar {
            ToolbarItem {
                Button("New Backup Job…", systemImage: "plus") { isAddingJob = true }
                    .disabled(model.isBusy)
            }
            ToolbarItem {
                Button("Restore…", systemImage: "arrow.uturn.backward") { isRestoring = true }
                    .disabled(model.isBusy)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let activity = model.activity {
                ActivityBar(activity: activity) { model.cancelActivity() }
            }
        }
        .sheet(isPresented: $isAddingJob) { NewJobSheet() }
        .sheet(isPresented: $isRestoring) { RestoreSheet() }
        .alert(item: $model.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message))
        }
        .frame(minWidth: 640, minHeight: 400)
    }
}

private struct JobRow: View {
    let job: BackupJob

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(job.name)
            Group {
                if let date = job.lastBackupDate {
                    Text("Last backup \(date, format: .relative(presentation: .named))")
                } else {
                    Text("Never backed up")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct JobDetailView: View {
    @Environment(AppModel.self) private var model
    let job: BackupJob

    var body: some View {
        Form {
            Section {
                LabeledContent("Source", value: job.source.displayPath)
                LabeledContent("Destination", value: job.destination.displayPath)
            }
            Section {
                HStack {
                    Button("Back Up Now") { model.startBackup(jobID: job.id, incremental: false) }
                        .keyboardShortcut("b", modifiers: [.command])
                    Button("Back Up Changes Only") { model.startBackup(jobID: job.id, incremental: true) }
                        .disabled(job.lastBackupDate == nil)
                        .help("Only files modified since the last backup")
                }
                .disabled(model.isBusy)
            }
            Section("History") {
                if job.history.isEmpty {
                    Text("No backups yet.").foregroundStyle(.secondary)
                }
                ForEach(job.history) { record in
                    HistoryRow(record: record)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(job.name)
    }
}

private struct HistoryRow: View {
    let record: BackupRecord

    var body: some View {
        LabeledContent {
            Text(Int64(record.archiveBytes), format: .byteCount(style: .file))
        } label: {
            Text(record.date, format: .dateTime)
            Text(record.kind == .full ? "Full · \(record.fileCount) files" : "Changes only · \(record.fileCount) files")
        }
        .help(record.archiveName)
    }
}

private struct ActivityBar: View {
    let activity: AppModel.Activity
    let cancel: () -> Void

    var body: some View {
        HStack {
            ProgressView(activity.title, value: activity.fraction)
            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)
        }
        .padding()
        .background(.bar)
    }
}

#Preview {
    ContentView()
        .environment(AppModel(store: nil))
}
