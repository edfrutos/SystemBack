import SwiftUI
import SystemBackCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: BackupJob.ID?
    @State private var isAddingJob = false
    @State private var isRestoring = false
    @SceneStorage("showsActivity") private var showsActivity = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(model.jobs, selection: $selection) { job in
                JobRow(job: job)
                    .contextMenu {
                        Button("Delete Job", systemImage: "trash", role: .destructive) { model.removeJob(job.id) }
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
        .inspector(isPresented: $showsActivity) {
            ActivityView()
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .toolbar {
            ToolbarItem {
                Button("New Backup Job…", systemImage: "plus") { isAddingJob = true }
                    .help("Create a backup job: choose a folder and where to save its backups")
                    .disabled(model.isBusy)
            }
            ToolbarItem {
                Button("Restore from File…", systemImage: "doc.zipper") { isRestoring = true }
                    .help("Restore a .tar.gz backup file into a new folder")
                    .disabled(model.isBusy)
            }
            ToolbarItem {
                Button("Activity", systemImage: "list.bullet.rectangle") { showsActivity.toggle() }
                    .help("Show or hide the activity log")
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Con el panel Actividad cerrado, la barra inferior mantiene visible el progreso.
            if let activity = model.activity, !showsActivity {
                ActivityBar(activity: activity) { model.cancelActivity() }
            }
        }
        .sheet(isPresented: $isAddingJob) { NewJobSheet() }
        .sheet(isPresented: $isRestoring) { RestoreSheet() }
        .alert(model.notice?.title ?? "", isPresented: Binding(
            get: { model.notice != nil },
            set: { if !$0 { model.notice = nil } }
        ), presenting: model.notice) { notice in
            if let url = notice.revealURL {
                Button("Show in Finder") { model.reveal(url, scope: notice.revealScope) }
            }
            Button("OK", role: .cancel) {}
        } message: { notice in
            Text(notice.message)
        }
        .onChange(of: model.jobs.count) { oldCount, newCount in
            // Selecciona el trabajo recién creado.
            if newCount > oldCount { selection = model.jobs.last?.id }
        }
        .frame(minWidth: 760, minHeight: 460)
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

private struct ActivityBar: View {
    let activity: AppModel.Activity
    let cancel: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(activity.title, value: activity.fraction)
                if let detail = activity.detail {
                    Text(detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
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
