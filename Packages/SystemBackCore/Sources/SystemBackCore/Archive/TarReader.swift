import Foundation

/// Entrada de un archivo tar ya resuelta (PAX / GNU longname aplicados).
struct TarEntry: Equatable {
    enum Kind: Equatable {
        case file
        case directory
        case symbolicLink
        case hardLink
        case other(UInt8)
    }

    var path: String
    var kind: Kind
    var size: UInt64
    var mode: UInt32
    var modificationDate: Date
}

/// Destino del contenido de una entrada de tipo fichero.
protocol TarEntryContentSink: AnyObject {
    func write(_ data: Data) throws
    func finish() throws
}

/// Parser tar incremental: se alimenta con bloques de datos de cualquier tamaño
/// (los que entrega el descompresor) sin cargar el archivo entero en memoria.
/// Soporta ustar, PAX (`x`, `g`) y GNU longname/longlink (`L`, `K`).
final class TarStreamParser {
    /// Devuelve un sink para recibir el contenido, o `nil` para descartarlo.
    typealias EntryHandler = (TarEntry) throws -> (any TarEntryContentSink)?

    private enum State {
        case header
        case content(remaining: UInt64, padding: Int, sink: (any TarEntryContentSink)?)
        case metadata(kind: UInt8, remaining: Int, padding: Int, collected: [UInt8])
        case finished
    }

    private let onEntry: EntryHandler
    private var state: State = .header
    private var buffer: [UInt8] = []
    private var cursor = 0
    private var offset: UInt64 = 0
    private var zeroBlocks = 0

    // Metadatos pendientes para la siguiente entrada
    private var pendingPax: [String: String] = [:]
    private var globalPax: [String: String] = [:]
    private var pendingLongName: String?
    private var pendingLongLink: String?

    private(set) var isFinished = false

    init(onEntry: @escaping EntryHandler) {
        self.onEntry = onEntry
    }

    func consume(_ data: Data) throws {
        if case .finished = state { return }
        compactBuffer()
        buffer.append(contentsOf: data)
        try process()
    }

    /// Comprueba que el flujo terminó en un límite de entrada.
    func finish() throws {
        switch state {
        case .finished:
            break
        case .header:
            // Sin bloques finales: tolerado (algunos generadores los omiten),
            // salvo que quede una cabecera a medias.
            guard available == 0 else { throw ArchiveError.truncatedTar }
        case .content, .metadata:
            throw ArchiveError.truncatedTar
        }
        isFinished = true
    }

    // MARK: - Máquina de estados

    private var available: Int { buffer.count - cursor }

    private func process() throws {
        while true {
            switch state {
            case .finished:
                return

            case .header:
                guard available >= TarWriter.blockSize else { return }
                let block = Array(buffer[cursor..<cursor + TarWriter.blockSize])
                let blockOffset = offset
                advance(TarWriter.blockSize)
                if block.allSatisfy({ $0 == 0 }) {
                    zeroBlocks += 1
                    if zeroBlocks == 2 { state = .finished; isFinished = true }
                    continue
                }
                zeroBlocks = 0
                try handleHeader(block, at: blockOffset)

            case let .content(remaining, padding, sink):
                if remaining == 0 {
                    guard available >= padding else { return }
                    advance(padding)
                    try sink?.finish()
                    state = .header
                    continue
                }
                guard available > 0 else { return }
                let count = Int(min(UInt64(available), remaining))
                if let sink {
                    try sink.write(Data(buffer[cursor..<cursor + count]))
                }
                advance(count)
                state = .content(remaining: remaining - UInt64(count), padding: padding, sink: sink)

            case let .metadata(kind, remaining, padding, collected):
                guard available >= remaining + padding else { return }
                let body = collected + buffer[cursor..<cursor + remaining]
                advance(remaining + padding)
                applyMetadata(kind: kind, body: body)
                state = .header
            }
        }
    }

    private func handleHeader(_ block: [UInt8], at blockOffset: UInt64) throws {
        guard Self.checksumMatches(block) else {
            throw ArchiveError.invalidTarHeader(offset: blockOffset)
        }
        let type = block[156]
        guard let headerSize = Self.parseNumber(block[124..<136]) else {
            throw ArchiveError.invalidTarHeader(offset: blockOffset)
        }

        // Cabeceras de metadatos: afectan a la entrada siguiente.
        if type == UInt8(ascii: "x") || type == UInt8(ascii: "g")
            || type == UInt8(ascii: "L") || type == UInt8(ascii: "K") {
            guard headerSize <= 1 << 20 else { throw ArchiveError.invalidTarHeader(offset: blockOffset) }
            let size = Int(headerSize)
            state = .metadata(kind: type, remaining: size, padding: Self.padding(for: UInt64(size)), collected: [])
            return
        }

        var path = pendingLongName ?? Self.headerPath(block)
        var size = headerSize
        if let paxPath = pendingPax["path"] ?? globalPax["path"] { path = paxPath }
        if let paxSize = (pendingPax["size"] ?? globalPax["size"]).flatMap(UInt64.init) { size = paxSize }
        let mode = UInt32(Self.parseNumber(block[100..<108]) ?? 0o644)
        let mtimeSeconds = pendingPax["mtime"].flatMap(Double.init)
            ?? Double(Self.parseNumber(block[136..<148]) ?? 0)
        pendingPax = [:]
        pendingLongName = nil
        pendingLongLink = nil

        let kind: TarEntry.Kind = switch type {
        case 0, UInt8(ascii: "0"), UInt8(ascii: "7"): path.hasSuffix("/") ? .directory : .file
        case UInt8(ascii: "5"): .directory
        case UInt8(ascii: "2"): .symbolicLink
        case UInt8(ascii: "1"): .hardLink
        default: .other(type)
        }
        // Directorios y enlaces no llevan datos; ficheros y tipos desconocidos sí (se consumen).
        let dataSize: UInt64 = switch kind {
        case .directory, .symbolicLink, .hardLink: 0
        case .file, .other: size
        }

        let entry = TarEntry(
            path: path, kind: kind, size: dataSize, mode: mode,
            modificationDate: Date(timeIntervalSince1970: mtimeSeconds)
        )
        let sink = try onEntry(entry)
        state = .content(remaining: dataSize, padding: Self.padding(for: dataSize), sink: kind == .file ? sink : nil)
    }

    private func applyMetadata(kind: UInt8, body: [UInt8]) {
        switch kind {
        case UInt8(ascii: "L"):
            pendingLongName = Self.cString(body[...])
        case UInt8(ascii: "K"):
            pendingLongLink = Self.cString(body[...])
        default:
            let records = Self.parsePax(body)
            if kind == UInt8(ascii: "g") {
                globalPax.merge(records) { $1 }
            } else {
                pendingPax.merge(records) { $1 }
            }
        }
    }

    private func advance(_ count: Int) {
        cursor += count
        offset += UInt64(count)
    }

    private func compactBuffer() {
        if cursor > 0 {
            buffer.removeFirst(cursor)
            cursor = 0
        }
    }

    // MARK: - Utilidades de formato

    static func padding(for size: UInt64) -> Int {
        let remainder = Int(size % UInt64(TarWriter.blockSize))
        return remainder == 0 ? 0 : TarWriter.blockSize - remainder
    }

    static func checksumMatches(_ block: [UInt8]) -> Bool {
        guard let stored = parseNumber(block[148..<156]) else { return false }
        var unsigned: UInt64 = 0
        var signed: Int64 = 0
        for (index, byte) in block.enumerated() {
            let value: UInt8 = (148..<156).contains(index) ? 0x20 : byte
            unsigned += UInt64(value)
            signed += Int64(Int8(bitPattern: value))
        }
        return stored == unsigned || Int64(stored) == signed
    }

    /// Octal ASCII (con espacios/NUL) o base-256 (bit alto del primer byte, extensión GNU).
    static func parseNumber(_ field: ArraySlice<UInt8>) -> UInt64? {
        guard let first = field.first else { return nil }
        if first & 0x80 != 0 {
            var value: UInt64 = UInt64(first & 0x7F)
            for byte in field.dropFirst() {
                guard value <= (UInt64.max >> 8) else { return nil }
                value = (value << 8) | UInt64(byte)
            }
            return value
        }
        let text = String(decoding: field.prefix { $0 != 0 }, as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return 0 }
        return UInt64(text, radix: 8)
    }

    static func headerPath(_ block: [UInt8]) -> String {
        let name = cString(block[0..<100])
        let isUstar = block[257..<262].elementsEqual("ustar".utf8)
        let prefix = isUstar ? cString(block[345..<500]) : ""
        return prefix.isEmpty ? name : prefix + "/" + name
    }

    static func cString(_ bytes: ArraySlice<UInt8>) -> String {
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }

    static func parsePax(_ body: [UInt8]) -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < body.count {
            guard let space = body[index...].firstIndex(of: 0x20),
                  let length = Int(String(decoding: body[index..<space], as: UTF8.self)),
                  length > 0, index + length <= body.count
            else { break }
            let record = body[(space + 1)..<(index + length)]
            let trimmed = record.last == 0x0A ? record.dropLast() : record
            if let equals = trimmed.firstIndex(of: UInt8(ascii: "=")) {
                let key = String(decoding: trimmed[trimmed.startIndex..<equals], as: UTF8.self)
                let value = String(decoding: trimmed[(equals + 1)...], as: UTF8.self)
                result[key] = value
            }
            index += length
        }
        return result
    }
}
