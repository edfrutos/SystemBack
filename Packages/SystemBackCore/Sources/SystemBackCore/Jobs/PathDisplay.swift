import Foundation

/// Rutas para mostrar en la interfaz: la carpeta personal se abrevia como `~`.
public enum PathDisplay {
    /// Carpeta personal real del usuario. En sandbox, `NSHomeDirectory()` devuelve el contenedor
    /// de la app, así que se lee de la base de datos de usuarios.
    public static let userHome: String = {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return String(cString: directory)
        }
        return NSHomeDirectory()
    }()

    /// `/Users/ana/Demo` → `~/Demo`. Las rutas fuera de la carpeta personal no cambian.
    public static func abbreviatingHome(_ path: String, home: String = userHome) -> String {
        var home = home
        while home.count > 1, home.hasSuffix("/") { home.removeLast() }
        guard home.count > 1 else { return path }
        if path == home { return "~" }
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

extension FolderReference {
    /// Ruta para mostrar, con la carpeta personal abreviada como `~`.
    public var shortPath: String { PathDisplay.abbreviatingHome(displayPath) }
}
