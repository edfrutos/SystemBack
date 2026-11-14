import Foundation
import zlib

/// CRC-32 (IEEE 802.3) del trailer gzip (RFC 1952), calculado con `crc32` de zlib
/// (librería del sistema en el SDK de macOS, acelerada por hardware).
struct CRC32 {
    private(set) var value: UInt32 = 0

    mutating func update(_ data: Data) {
        data.withUnsafeBytes { update($0) }
    }

    mutating func update(_ bytes: [UInt8]) {
        bytes.withUnsafeBytes { update($0) }
    }

    private mutating func update(_ buffer: UnsafeRawBufferPointer) {
        guard let base = buffer.bindMemory(to: Bytef.self).baseAddress else { return }
        var crc = uLong(value)
        var offset = 0
        // uInt es de 32 bits: se procesa en tramos para buffers enormes.
        while offset < buffer.count {
            let length = min(buffer.count - offset, Int(Int32.max))
            crc = crc32(crc, base + offset, uInt(length))
            offset += length
        }
        value = UInt32(truncatingIfNeeded: crc)
    }
}
