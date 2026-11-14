import Foundation
import Testing
@testable import SystemBackCore

/// Medición manual (criterio F2: 1 GiB). Se activa con SYSTEMBACK_BENCH=1 y en Release:
/// `SYSTEMBACK_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter PerformanceTests`
@Suite("Rendimiento", .enabled(if: ProcessInfo.processInfo.environment["SYSTEMBACK_BENCH"] != nil))
struct PerformanceTests {
    @Test func `backup y restauración de 1 GiB`() throws {
        let sandbox = TemporaryDirectory()
        let source = sandbox.url.appending(path: "origen")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        // 16 ficheros × 64 MiB, mitad aleatorio y mitad repetitivo (compresión realista).
        var generator = SystemRandomNumberGenerator()
        for index in 0..<16 {
            var data = Data(count: 64 << 20)
            data.withUnsafeMutableBytes { buffer in
                let words = buffer.bindMemory(to: UInt64.self)
                for position in words.indices {
                    words[position] = index.isMultiple(of: 2) ? generator.next() : UInt64(position % 4096)
                }
            }
            try data.write(to: source.appending(path: "f\(index).bin"))
        }

        let clock = ContinuousClock()
        var outcome: BackupOutcome = .noChanges
        let backupTime = try clock.measure {
            outcome = try BackupEngine().run(BackupRequest(source: source, destinationRoot: sandbox.url.appending(path: "dst")))
        }
        let result = try #require(outcome.created)
        let restoreTime = try clock.measure {
            _ = try RestoreEngine().restore(archive: result.archiveURL, into: sandbox.url.appending(path: "rst"))
        }
        print("BENCH backup 1 GiB: \(backupTime) · archivo \(result.archiveBytes >> 20) MiB · restauración: \(restoreTime)")
    }
}
