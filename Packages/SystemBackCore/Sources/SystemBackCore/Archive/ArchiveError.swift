import Foundation

/// Errores del formato de archivo. Llevan el contexto necesario para mostrar un mensaje útil.
public enum ArchiveError: Error, Equatable, Sendable {
    case cannotCreate(URL)
    case notGzip(URL)
    case corrupted(URL)
    case checksumMismatch(URL)
    case invalidTarHeader(offset: UInt64)
    case truncatedTar
    /// Ruta absoluta, con `..`, o que sale del destino. Nunca se extrae.
    case unsafeEntryPath(String)
}
