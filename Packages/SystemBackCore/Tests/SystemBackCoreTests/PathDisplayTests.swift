import Testing
@testable import SystemBackCore

@Suite struct PathDisplayTests {
    @Test("abrevia la carpeta personal como ~", arguments: [
        ("/Users/ana/Demo/Proyecto Web", "~/Demo/Proyecto Web"),
        ("/Users/ana", "~"),
        ("/Users/ana/", "~/"),
        ("/Users/anabel/Demo", "/Users/anabel/Demo"),   // otro usuario con el mismo prefijo
        ("/Volumes/Disco/Backups", "/Volumes/Disco/Backups"),
        ("/", "/"),
    ])
    func abbreviates(path: String, expected: String) {
        #expect(PathDisplay.abbreviatingHome(path, home: "/Users/ana") == expected)
    }

    @Test("tolera la barra final en la carpeta personal y nunca abrevia la raíz")
    func edgeHomes() {
        #expect(PathDisplay.abbreviatingHome("/Users/ana/Demo", home: "/Users/ana/") == "~/Demo")
        #expect(PathDisplay.abbreviatingHome("/Users/ana/Demo", home: "/") == "/Users/ana/Demo")
        #expect(PathDisplay.abbreviatingHome("/Users/ana/Demo", home: "") == "/Users/ana/Demo")
    }

    @Test("la carpeta personal real no es la del contenedor del sandbox")
    func realHome() {
        #expect(!PathDisplay.userHome.contains("/Library/Containers/"))
        #expect(PathDisplay.userHome.hasPrefix("/"))
    }
}
