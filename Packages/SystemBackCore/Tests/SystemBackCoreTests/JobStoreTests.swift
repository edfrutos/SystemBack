import Foundation
import Testing
@testable import SystemBackCore

@Suite("Persistencia de trabajos")
struct JobStoreTests {
    let sandbox = TemporaryDirectory()

    func job(history: [BackupRecord] = []) -> BackupJob {
        let folder = FolderReference(bookmark: Data([1, 2, 3]), displayPath: "/Users/x/Documentos")
        return BackupJob(name: "Documentos", source: folder, destination: folder, history: history)
    }

    @Test func `guardar y cargar conserva los trabajos`() throws {
        let store = JobStore(fileURL: sandbox.url.appending(path: "a/jobs.json"))
        #expect(try store.load().isEmpty)

        var original = job()
        original.record(BackupRecord(date: Date(timeIntervalSince1970: 1_700_000_000), kind: .full,
                                     archiveName: "backup_x.tar.gz", fileCount: 3, contentBytes: 10, archiveBytes: 5))
        try store.save([original])
        #expect(try store.load() == [original])
    }

    @Test func `un jobs.json sin uploadsToDrive se lee con la opción desactivada`() throws {
        let file = sandbox.url.appending(path: "old/jobs.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacy = #"{"version":1,"jobs":[{"id":"6F1C2A44-2B4B-4B47-9B0E-3C8D7B1E0A11","name":"Docs","source":{"bookmark":"AQID","displayPath":"/a"},"destination":{"bookmark":"AQID","displayPath":"/b"},"exclusions":{"names":[".DS_Store"],"extensions":[]},"history":[]}]}"#
        try Data(legacy.utf8).write(to: file)
        let jobs = try JobStore(fileURL: file).load()
        #expect(jobs.count == 1)
        #expect(jobs.first?.uploadsToDrive == false)

        var changed = try #require(jobs.first)
        changed.uploadsToDrive = true
        try JobStore(fileURL: file).save([changed])
        #expect(try JobStore(fileURL: file).load().first?.uploadsToDrive == true)
    }

    @Test func `el historial se limita y el más reciente va primero`() {
        var item = job()
        for index in 0..<(BackupJob.historyLimit + 5) {
            item.record(BackupRecord(date: Date(timeIntervalSince1970: Double(index)), kind: .full,
                                     archiveName: "\(index)", fileCount: 0, contentBytes: 0, archiveBytes: 0))
        }
        #expect(item.history.count == BackupJob.historyLimit)
        #expect(item.history.first?.archiveName == "\(BackupJob.historyLimit + 4)")
    }

    @Test func `bookmark de carpeta real se resuelve fuera del sandbox`() throws {
        let reference = try FolderReference.make(from: sandbox.url)
        let resolved = try reference.resolve()
        #expect(resolved.url.resolvingSymlinksInPath() == sandbox.url.resolvingSymlinksInPath())
    }
}
