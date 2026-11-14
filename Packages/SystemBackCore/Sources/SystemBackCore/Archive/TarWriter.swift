import Foundation

/// Escribe un flujo tar POSIX (ustar + cabeceras PAX `x` para rutas largas o tamaños > 8 GiB).
/// Compatible con `tar` de macOS/Linux y con `tarfile` de Python (formato PAX por defecto).
struct TarWriter {
    static let blockSize = 512
    /// Tamaño de registro de `tarfile`/GNU tar; el final se rellena hasta un múltiplo.
    static let recordSize = 10_240
    private static let maxOctalSize: UInt64 = 0o77_777_777_777

    private let sink: (Data) throws -> Void
    private(set) var bytesWritten: UInt64 = 0

    init(sink: @escaping (Data) throws -> Void) {
        self.sink = sink
    }

    mutating func addDirectory(path: String, modificationDate: Date, mode: UInt32 = 0o755) throws {
        let name = path.hasSuffix("/") ? path : path + "/"
        try writeHeader(name: name, size: 0, modificationDate: modificationDate, mode: mode, type: "5")
    }

    /// Añade el contenido de `fileURL` con la ruta `path` dentro del archivo, leyendo por bloques.
    mutating func addFile(
        path: String,
        contentsOf fileURL: URL,
        size: UInt64,
        modificationDate: Date,
        mode: UInt32 = 0o644,
        onBytes: (Int) -> Void = { _ in }
    ) throws {
        try writeHeader(name: path, size: size, modificationDate: modificationDate, mode: mode, type: "0")

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var remaining = size
        while remaining > 0 {
            try Task.checkCancellation()
            let count = Int(min(remaining, 1 << 20))
            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else {
                // El fichero encogió mientras se leía: el tar quedaría inconsistente.
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: fileURL.path])
            }
            try emit(chunk)
            remaining -= UInt64(chunk.count)
            onBytes(chunk.count)
        }
        try padToBlock(size)
    }

    /// Dos bloques a cero y relleno hasta el tamaño de registro.
    mutating func finish() throws {
        try emit(Data(count: Self.blockSize * 2))
        let remainder = Int(bytesWritten % UInt64(Self.recordSize))
        if remainder != 0 { try emit(Data(count: Self.recordSize - remainder)) }
    }

    // MARK: - Cabeceras

    private mutating func writeHeader(
        name: String, size: UInt64, modificationDate: Date, mode: UInt32, type: Character
    ) throws {
        let nameBytes = Array(name.utf8)
        var pax: [(String, String)] = []
        if nameBytes.count > 100 { pax.append(("path", name)) }
        if size > Self.maxOctalSize { pax.append(("size", String(size))) }

        if !pax.isEmpty {
            let body = Data(pax.map(Self.paxRecord).joined().utf8)
            let paxName = "PaxHeader/" + String(decoding: nameBytes.suffix(80), as: UTF8.self)
            try emit(Self.header(
                name: Array(paxName.utf8.prefix(100)), size: UInt64(body.count),
                modificationDate: modificationDate, mode: 0o644, type: "x"
            ))
            try emit(body)
            try padToBlock(UInt64(body.count))
        }

        let storedName = nameBytes.count > 100 ? Array(nameBytes.suffix(100)) : nameBytes
        try emit(Self.header(
            name: storedName, size: min(size, Self.maxOctalSize),
            modificationDate: modificationDate, mode: mode, type: type
        ))
    }

    /// Registro PAX "<longitud> clave=valor\n", donde la longitud se incluye a sí misma.
    static func paxRecord(_ pair: (String, String)) -> String {
        let payload = " \(pair.0)=\(pair.1)\n"
        let payloadLength = payload.utf8.count
        var length = payloadLength + 1
        while String(length).count + payloadLength != length {
            length = String(length).count + payloadLength
        }
        return "\(length)\(payload)"
    }

    static func header(
        name: [UInt8], size: UInt64, modificationDate: Date, mode: UInt32, type: Character
    ) -> Data {
        var block = [UInt8](repeating: 0, count: blockSize)
        func put(_ bytes: [UInt8], at offset: Int, length: Int) {
            for (index, byte) in bytes.prefix(length).enumerated() { block[offset + index] = byte }
        }
        func octal(_ value: UInt64, width: Int) -> [UInt8] {
            let digits = String(value, radix: 8)
            return Array((String(repeating: "0", count: max(0, width - 1 - digits.count)) + digits).utf8) + [0]
        }

        put(name, at: 0, length: 100)
        put(octal(UInt64(mode & 0o7777), width: 8), at: 100, length: 8)
        put(octal(0, width: 8), at: 108, length: 8)                     // uid
        put(octal(0, width: 8), at: 116, length: 8)                     // gid
        put(octal(size, width: 12), at: 124, length: 12)
        let seconds = UInt64(max(0, modificationDate.timeIntervalSince1970.rounded(.down)))
        put(octal(seconds, width: 12), at: 136, length: 12)
        put(Array(repeating: 0x20, count: 8), at: 148, length: 8)       // checksum provisional
        block[156] = type.asciiValue ?? 0x30
        put(Array("ustar".utf8) + [0], at: 257, length: 6)
        put(Array("00".utf8), at: 263, length: 2)

        let checksum = block.reduce(0) { $0 + UInt64($1) }
        let digits = String(checksum, radix: 8)
        put(Array((String(repeating: "0", count: max(0, 6 - digits.count)) + digits).utf8) + [0, 0x20],
            at: 148, length: 8)
        return Data(block)
    }

    // MARK: - Salida

    private mutating func padToBlock(_ length: UInt64) throws {
        let remainder = Int(length % UInt64(Self.blockSize))
        if remainder != 0 { try emit(Data(count: Self.blockSize - remainder)) }
    }

    private mutating func emit(_ data: Data) throws {
        try sink(data)
        bytesWritten += UInt64(data.count)
    }
}
