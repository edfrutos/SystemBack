import Compression
import Foundation

/// Contenedor gzip (RFC 1952) sobre el DEFLATE crudo (RFC 1951) del framework Compression.
/// `Algorithm.zlib` de Compression produce/consume DEFLATE sin cabecera; aquí se añaden
/// la cabecera gzip y el trailer (CRC-32 + ISIZE) para que el `.tar.gz` sea estándar.
enum Gzip {
    static let magic: [UInt8] = [0x1F, 0x8B]
    static let methodDeflate: UInt8 = 8

    // Flags de cabecera (RFC 1952 §2.3.1)
    static let flagHeaderCRC: UInt8 = 0x02
    static let flagExtra: UInt8 = 0x04
    static let flagName: UInt8 = 0x08
    static let flagComment: UInt8 = 0x10
}

/// Escribe un fichero `.gz` en streaming.
final class GzipFileWriter {
    private let handle: FileHandle
    private let filter: OutputFilter
    private var crc = CRC32()
    private var uncompressedSize: UInt32 = 0
    private var finished = false

    init(creating url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw ArchiveError.cannotCreate(url)
        }
        let handle = try FileHandle(forWritingTo: url)
        self.handle = handle
        // Cabecera mínima: sin nombre ni mtime; XFL 0; SO 3 (Unix), como gzip/tarfile.
        try handle.write(contentsOf: Gzip.magic + [Gzip.methodDeflate, 0, 0, 0, 0, 0, 0, 3])
        self.filter = try OutputFilter(.compress, using: .zlib) { compressed in
            if let compressed { try handle.write(contentsOf: compressed) }
        }
    }

    func write(_ data: Data) throws {
        crc.update(data)
        uncompressedSize &+= UInt32(truncatingIfNeeded: data.count)
        try filter.write(data)
    }

    func finish() throws {
        guard !finished else { return }
        finished = true
        try filter.finalize()
        try handle.write(contentsOf: littleEndianBytes(crc.value) + littleEndianBytes(uncompressedSize))
        try handle.close()
    }

    /// Cierra sin escribir trailer (p. ej. al cancelar). El llamador borra el fichero.
    func abandon() {
        finished = true
        try? handle.close()
    }
}

/// Lee un fichero `.gz` de un solo miembro y entrega los datos descomprimidos por bloques.
enum GzipFileReader {
    static func decompress(
        _ url: URL,
        chunkSize: Int = 1 << 20,
        onChunk: @escaping (Data) throws -> Void
    ) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        guard fileSize >= 18 else { throw ArchiveError.notGzip(url) }

        let header = try readExactly(handle, 10, url)
        guard Array(header[0..<2]) == Gzip.magic, header[2] == Gzip.methodDeflate else {
            throw ArchiveError.notGzip(url)
        }
        let flags = header[3]
        if flags & Gzip.flagExtra != 0 {
            let lengthBytes = try readExactly(handle, 2, url)
            let extraLength = Int(lengthBytes[0]) | Int(lengthBytes[1]) << 8
            _ = try readExactly(handle, extraLength, url)
        }
        if flags & Gzip.flagName != 0 { try skipZeroTerminated(handle, url) }
        if flags & Gzip.flagComment != 0 { try skipZeroTerminated(handle, url) }
        if flags & Gzip.flagHeaderCRC != 0 { _ = try readExactly(handle, 2, url) }

        let payloadEnd = fileSize - 8
        var crc = CRC32()
        var size: UInt32 = 0
        var deliveryError: (any Error)?

        let filter = try OutputFilter(.decompress, using: .zlib) { output in
            guard let output, deliveryError == nil else { return }
            crc.update(output)
            size &+= UInt32(truncatingIfNeeded: output.count)
            do { try onChunk(output) } catch { deliveryError = error }
        }

        var offset = try handle.offset()
        guard offset <= payloadEnd else { throw ArchiveError.corrupted(url) }
        while offset < payloadEnd {
            try Task.checkCancellation()
            let count = Int(min(UInt64(chunkSize), payloadEnd - offset))
            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else {
                throw ArchiveError.corrupted(url)
            }
            try filter.write(chunk)
            if let deliveryError { throw deliveryError }
            offset += UInt64(chunk.count)
        }
        try filter.finalize()
        if let deliveryError { throw deliveryError }

        let trailer = try readExactly(handle, 8, url)
        let expectedCRC = readLittleEndianUInt32(trailer, at: 0)
        let expectedSize = readLittleEndianUInt32(trailer, at: 4)
        guard expectedCRC == crc.value, expectedSize == size else {
            throw ArchiveError.checksumMismatch(url)
        }
    }

    private static func readExactly(_ handle: FileHandle, _ count: Int, _ url: URL) throws -> [UInt8] {
        guard count > 0 else { return [] }
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw ArchiveError.corrupted(url)
        }
        return Array(data)
    }

    private static func skipZeroTerminated(_ handle: FileHandle, _ url: URL) throws {
        while try readExactly(handle, 1, url)[0] != 0 {}
    }
}

private func littleEndianBytes(_ value: UInt32) -> [UInt8] {
    (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
}

private func readLittleEndianUInt32(_ bytes: [UInt8], at index: Int) -> UInt32 {
    (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[index + $1]) << ($1 * 8) }
}
