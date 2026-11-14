# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Qué es

**SystemBack** (`com.efjdev.systemback`): app nativa macOS (Swift 6 / SwiftUI, macOS 14+) para la **Mac App Store**. Hace backup `.tar.gz` de las carpetas que elige el usuario, en local (y en Google Drive, pendiente), y las restaura. Es la reescritura de la herramienta Python `../000.-EDF_Sistema_de_Backups`, que **no se modifica** desde aquí: sirve solo como referencia funcional (sus tests son la especificación portada).

Plan, decisiones (D1–D12) y estado: `docs/appstore/PLAN_APP_STORE.md` y `docs/appstore/SEGUIMIENTO_APP_STORE.md`. Actualiza el seguimiento (checklist + bitácora) en cada sesión.

## Comandos

```bash
# Núcleo (rápido, sin Xcode)
cd Packages/SystemBackCore && swift test
swift test --filter BackupRestoreTests                       # una suite
swift test --filter "BackupRestoreTests/incremental"         # tests cuyo id contiene el texto

# Medición 1 GiB (Release)
SYSTEMBACK_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter PerformanceTests

# App
xcodebuild -project SystemBack.xcodeproj -scheme SystemBack -configuration Debug -destination 'platform=macOS' build
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/SystemBack-*/Build/Products/Debug/SystemBack.app | head -1)
codesign -d --entitlements - --xml "$APP" | plutil -p -    # comprobar entitlements reales
```

También se puede usar el MCP de Xcode (`XcodeOpenWorkspace`, `BuildProject`, `RunProject`…). **Ojo**: `UpdateTargetBuildSetting`/`AddInfoPlist` modifican el proyecto en memoria; si se cierra el workspace sin guardar desde Xcode, se pierden. Tras cambiar ajustes, verifica `project.pbxproj` o el binario.

No hay linter configurado.

## Arquitectura

- `Packages/SystemBackCore/` (paquete Swift local, **sin dependencias**, APIs `nonisolated`, síncronas y cancelables con `Task.checkCancellation`):
  - `Archive/`: formato propio `.tar.gz` (D9). `TarWriter` (ustar + cabeceras PAX para rutas > 100 bytes o tamaños > 8 GiB), `TarStreamParser` incremental (ustar, PAX `x`/`g`, GNU `L`/`K`), `Gzip` (RFC 1952) sobre `Compression` `.zlib` (DEFLATE crudo) + `crc32` de zlib. Debe seguir siendo legible por `tar`/`gunzip` del sistema y por `tarfile` de Python (hay tests que lo comprueban, incluido el fixture `Tests/.../Fixtures/python_tarfile.tar.gz`).
  - `Backup/BackupEngine`: completo o incremental (por `contentModificationDate`), nombre `<backup|incr>_<origen>_<yyyyMMdd_HHmmss>.tar.gz` en `<destino>/<origen>/` (mismo esquema que la herramienta Python), escritura a `.partial` y `move` al final; nunca archiva el propio destino ni sigue enlaces simbólicos.
  - `Backup/ArchiveCatalog`: lista los `.tar.gz` de `<destino>/<origen>/` (tipo y fecha a partir del nombre; si no, fecha de modificación), ignora `.partial`; `moveToTrash` (borrado recuperable: sin diálogo de confirmación, HIG `alerts.md`).
  - `Backup/RestoreEngine`: solo a carpeta **nueva o vacía**; valida cada ruta (`resolve`: sin absolutas, sin `..`, dentro del destino) y ante la primera insegura aborta y borra lo restaurado. Omite enlaces, dispositivos y metadatos AppleDouble `._*`.
  - `Jobs/`: `FolderReference` (security-scoped bookmarks), `withSecurityScopedAccess` (start/stop equilibrados), `BackupJob` + historial (máx. 200), `JobStore` (JSON versionado en Application Support del contenedor, D11).
- `SystemBack/` (app, grupo sincronizado de Xcode: los ficheros nuevos se incluyen solos):
  - Ajustes del target: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Approachable Concurrency, Swift 6.
  - `Model/AppModel` (`@Observable`, main actor): trabajos, actividad en curso, avisos con mensaje + qué hacer.
  - `Model/BackgroundWork` (`nonisolated`, funciones `@concurrent`): resuelve bookmarks, abre el acceso con security scope y llama al núcleo; el progreso llega por `AsyncStream` (`bufferingNewest(1)`).
  - `System/SystemServices`: notificaciones (permiso pedido en contexto, nunca al arrancar), `LoginItem` (SMAppService), enlaces de privacidad y soporte.
  - Vistas: `ContentView` (NavigationSplitView + inspector «Actividad»), `Views/JobDetailView` (tarjetas de acción: completo, actualizar = completo + anterior a la Papelera, incremental; lista de backups con restaurar / mostrar en Finder / Papelera), `Views/ActivityView` (registro de la sesión, máx. 500 líneas), `Views/Theme` (identidad heredada: verde completo, naranja actualizar, morado incremental; siempre con icono + texto), `Sheets`, `SettingsView` (escena Settings ⌘,).

## Reglas de la App Store (no romperlas)

- Un solo proceso: nada de `Process`, scripts, AppleScript ni procesos que sigan vivos al salir (2.4.5(iii), 2.5.2). `Process` solo aparece en los tests.
- Acceso a ficheros solo por selección del usuario + bookmarks; siempre dentro de `withSecurityScopedAccess`. Datos propios solo en el contenedor.
- Entitlements esperados: `app-sandbox`, `files.user-selected.read-write`, `network.client`. Añadir otro exige justificarlo en el seguimiento.
- `SystemBack/PrivacyInfo.xcprivacy`: declara solo las required reason API que el código usa de verdad (hoy FileTimestamp). Si se añade `UserDefaults`/`@AppStorage` o espacio en disco, actualízalo.
- Permisos en contexto, login item solo con toggle explícito, enlace a la política de privacidad en el menú Ayuda (5.1.1(i)).
- Idioma: **español por defecto**, inglés opcional en Ajustes (`System/AppLanguage`: guarda `SBInterfaceLanguage` y fija `AppleLanguages` en `Launcher.main()` antes de crear la app; el cambio pide reiniciar). Región de desarrollo `es`. Textos con clave en inglés y traducción en `SystemBack/Localizable.xcstrings`, que lleva entradas `es` **y** `en` explícitas (sin `en` no se genera `en.lproj` y el inglés caería al español). Toda cadena nueva necesita su traducción `es`.
- Selectores de carpeta lanzados desde menús o botones de fila: usar `FolderPicker` (NSOpenPanel), no `.fileImporter` (se pierde al cerrarse el menú).
- Revisión de diseño con la skill `apple-design`.
- Secretos (tokens de Google): Llavero, nunca en ficheros ni en el repositorio.
