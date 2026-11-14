# Plan de actuación — SystemBack en Mac App Store

> Documento de preparación. v2 del plan: **2026-11-14**. Las decisiones D1–D7 están cerradas: reescritura nativa en Swift/SwiftUI.
> Seguimiento operativo en [`SEGUIMIENTO_APP_STORE.md`](SEGUIMIENTO_APP_STORE.md).
> Configuración real en el proyecto Xcode (ajustes de build) y en `SystemBack/PrivacyInfo.xcprivacy`.

---

## 1. Resumen ejecutivo

El producto de App Store es **SystemBack**, una app nativa nueva en **Swift/SwiftUI** (D2). Hace backup de las carpetas que elige el usuario, en local y en Google Drive, y las restaura. Se distribuye gratis (D5) en español e inglés (D7).

La app Python actual (Flask + pywebview + py2app) **no se publica**. Tiene dos papeles:

1. **Herramienta personal**: se sigue usando tal cual para el entorno EDF, incluidos los backups de MongoDB Atlas y los scripts de mantenimiento.
2. **Especificación funcional**: su comportamiento y sus tests sirven de referencia para el núcleo Swift. Esto abarca el backup simple, el incremental y la actualización, el registro, la restauración con validación de rutas y el flujo de Drive.

Con Swift desaparecen los bloqueantes estructurales del diagnóstico (§3). Ya no hay servidor HTTP, ni subprocesos, ni AppleScript, ni intérprete embebido que firmar. Sandbox, Llavero, NSOpenPanel, security-scoped bookmarks, UserNotifications, SMAppService y el privacy manifest son APIs nativas de un proyecto Xcode normal (D3). El riesgo se desplaza al **coste de la reescritura** y a **dos incógnitas técnicas** que el spike de la Fase 2 debe cerrar:

- el OAuth de Google en una app macOS con sandbox;
- el formato de archivo del backup (compatibilidad con los `.tar.gz` existentes).

Entorno disponible (verificado 2026-11-14): Xcode 27.0, Swift 6.4, macOS 27.3.

---

## 2. Requisitos de Apple aplicables (texto vigente)

Citas literales de las App Review Guidelines, consultadas el 2026-11-13:

| Guía | Texto | Impacto en SystemBack (y motivo en el código Python) |
| --- | --- | --- |
| 2.4.5(i) | "They must be appropriately sandboxed, and follow macOS File System Documentation" | Sandbox obligatorio. Nada de escribir en el bundle ni en rutas arbitrarias. |
| 2.4.5(ii) | "They must also be self-contained, single app installation bundles and cannot install code or resources in shared locations." | Nada de `.venv`, LaunchAgents ni instalación de dependencias fuera del bundle. |
| 2.4.5(iii) | "They may not auto-launch or have other code run automatically at startup or login without consent nor spawn processes that continue to run without consent after a user has quit the app." | Sustituir `install_launchagent.sh` por `SMAppService.mainApp`, con un *toggle* explícito del usuario. Ningún subproceso debe sobrevivir al cierre. |
| 2.4.5(iv) | "They may not download or install standalone apps, kexts, additional code, or resources to add functionality…" | Eliminar `main.py --install` (que hace `pip install` en runtime). |
| 2.4.5(v) | "They may not request escalation to root privileges or use setuid attributes." | Hoy no aplica; mantenerlo así. |
| 2.4.5(vii) | "They must use the Mac App Store to distribute updates; other update mechanisms are not allowed." | No añadir actualizador propio. |
| 2.4.5(viii) | "Apps should run on the currently shipping OS and may not use deprecated or optionally installed technologies" | Probar en la versión de macOS vigente. No depender de `python3` ni de Terminal del sistema. |
| 2.4.5(ix) | "Apps must contain all language and localization support in a single app bundle." | Las localizaciones van dentro del bundle. |
| 2.5.2 | "…may not read or write data outside the designated container area, nor may they download, install, or execute code which introduces or changes features or functionality of the app…" | **Crítico**: hoy la app ejecuta cualquier script `.py`/`.sh` del árbol y abre scripts interactivos en Terminal. Solo debe ejecutar su propia lógica empaquetada. |
| 5.1.1(i) | "All apps must include a link to their privacy policy in the App Store Connect metadata field and within the app in an easily accessible manner." | Hace falta una política de privacidad publicada y enlazada desde la app (menú Ayuda o Ajustes). |

HIG relevantes (skill `apple-design`):

- `the-menu-bar.md › Menu bar extras`: "Let people — not your app — decide whether to put your menu bar extra in the menu bar." El icono `rumps` debe ser opcional y configurable en Ajustes.
- `the-menu-bar.md › Menu bar extras`: "Display a menu — not a popover — when people click your menu bar extra." El menú actual de `rumps` ya lo cumple.
- `settings.md`: los ajustes van en una ventana Settings abierta desde el menú de la app con ⌘, y titulada "*App Name* Settings" si solo tiene un panel.
- `privacy.md › Requesting permission`: "Avoid requesting permission at launch unless the data or resource is required…" Drive y MongoDB se piden en contexto, no al arrancar.
- `launching.md`: "Launch instantly." Hoy la ventana espera hasta 8 s a `/health`.

---

## 3. Diagnóstico: bloqueantes encontrados en el código

Ordenados por gravedad. **B** = bloquea la publicación, **S** = riesgo de seguridad, **M** = mejora necesaria.

| # | Tipo | Hallazgo | Ubicación |
| --- | --- | --- | --- |
| 1 | S/B | El servidor Flask en `127.0.0.1` **no tiene autenticación ni protección CSRF/Origin**. Cualquier proceso local, o una web que el usuario visite, podría llamar a `/execute`, `/delete_backup` o `/drive/*`. Falta verificar hasta dónde es explotable con peticiones *cross-origin* sencillas, pero el riesgo existe. | `backup_interface.py` (no hay `before_request` ni comprobación de token) |
| 2 | S/B | `setup_py2app.py` mete **todo `credentials/` dentro del `.app`**: `token.json`, `client_secrets*.json` y `mongodb.json`. Publicado, eso distribuiría tus tokens. | `setup_py2app.py:45-47` |
| 3 | B | Escribe datos en `cfg.PROJECT_ROOT` (backups, logs, credenciales, registro Drive). Dentro del bundle firmado eso es inválido: rompe la firma o el sandbox lo deniega. | `config.py:9-16`, `backup_interface.py:31,44,1251-1268`, `tools/*.py`, `scripts/local/maintenance/*.py` |
| 4 | B | Ejecuta scripts arbitrarios del árbol con `subprocess` y `sys.executable`, y lanza los interactivos en **Terminal vía AppleScript**. Choca con 2.5.2 y con el sandbox (Apple Events a Terminal). | `backup_interface.py:428-436, 449-462, 488-498, 980-989` |
| 5 | B | Usa AppleScript `osascript` para el diálogo de carpeta (Finder) y para las notificaciones. En sandbox exige excepciones de Apple Events que Review cuestiona. | `backup_interface.py:79-87, 772-800`, `main.py:notify` |
| 6 | B | `main.py --install` hace `pip install` en runtime. | `main.py:install_dependencies` |
| 7 | B | Arranque en login mediante LaunchAgent instalado por script. | `install_launchagent.sh`, `com.edf.backup.plist` |
| 8 | B | La función de producto está atada al entorno EDF: el *source* por defecto es `PROJECT_ROOT`, y hay scripts de limpieza de imágenes y cachés de otra app y de "verificar interfaz web". Review lo rechazaría por funcionalidad incompleta o confusa (2.1 / 4.2). | `config.py:BACKUP_SCRIPTS` |
| 9 | M | Credenciales en JSON plano (token OAuth, URI de MongoDB con contraseña). Deben ir al **Llavero**. | `credentials/` |
| 10 | M | Versiones incoherentes: `config.py` dice 2.0.0, `main.py` dice v2.2 y `setup_py2app.py` dice 2.3.0. Bundle ID `com.edf.backup`, sin dominio propio verificado. | varios |
| 11 | M | No hay `LSApplicationCategoryType`, `ITSAppUsesNonExemptEncryption`, `PrivacyInfo.xcprivacy` ni entitlements. Sobra `NSLocalNetworkUsageDescription`, porque el *loopback* no la necesita. | `setup_py2app.py:plist` |
| 12 | M | La UI es web y está en español fijo. No tiene menú nativo completo, ventana Settings, ni comprobaciones de accesibilidad o modo oscuro. | `templates/index.html` |

> **Nota v2.** El diagnóstico describe el código Python. Con la reescritura en Swift, los bloqueantes 3–8, 11 y 12 desaparecen por diseño. Los puntos 1, 2, 9 y 10 se corrigieron en la Fase 1 (2026-11-13) para el uso personal de la herramienta. La tabla se conserva como lista de **lo que la app Swift no debe repetir**.

---

## 4. Decisiones

| ID | Decisión | Elegido (2026-11-14) | Consecuencia |
| --- | --- | --- | --- |
| D1 | Alcance | Producto para la Mac App Store: utilidad genérica de backup de carpetas elegidas por el usuario, en local y en Google Drive | Nada específico de EDF en la app. Los scripts de mantenimiento se quedan en la herramienta Python. |
| D2 | Stack | Reescritura en **Swift/SwiftUI** | Proyecto nuevo. El Python queda como herramienta personal y referencia funcional. |
| D3 | Empaquetado | **Proyecto Xcode nativo** (archive, firma automática, exportación a App Store Connect) | Se descartan py2app y Briefcase para el producto: Briefcase empaqueta Python y no aplica a una app Swift. |
| D4 | MongoDB | **Fuera del producto** | El estado de la app (historial, ajustes, carpetas) se guarda localmente en el contenedor. El backup de Atlas sigue en la herramienta Python. Sin `network.client` hacia bases de datos ni URI en la etiqueta de privacidad. |
| D5 | Modelo de negocio | Gratis | Sin StoreKit. |
| D6 | Nombre, bundle ID, dominio | **SystemBack** · `com.efjdev.systemback` · `systemback.efjdev.com` (pendiente de crear) | Riesgos aceptados, ver §8: colisión con *Systemback* de Linux y un nombre que puede sugerir backup completo del sistema. Comprobar la disponibilidad del nombre al crear la app en App Store Connect. |
| D7 | Idiomas | es + en | String Catalog (`Localizable.xcstrings`) en el bundle. |

Decisiones nuevas que abre la reescritura (se cierran en la Fase 2):

| ID | Decisión | Opciones | Recomendación provisional |
| --- | --- | --- | --- |
| D8 | Versión mínima de macOS | 14 / 15 / 26+ | **macOS 14**: SwiftData, `@Observable`, `SMAppService` (13+) y una base de usuarios amplia. Subirla solo si alguna API lo exige. |
| D9 | Formato del backup | (a) `.tar.gz`, compatible con los backups actuales; (b) `.zip`; (c) Apple Archive `.aar` | (a) o (b). Foundation no trae un escritor tar/gzip ni zip. Hace falta una librería SPM (p. ej. ZIPFoundation, SWCompression) o una implementación propia. `.aar` es nativo, pero el usuario no lo abre fuera de macOS. **Sin verificar**: el spike decide. |
| D10 | OAuth de Google | (a) SDK GoogleSignIn (soporta macOS); (b) `ASWebAuthenticationSession` + PKCE + REST de Drive con `URLSession` | (b) si funciona en sandbox: no añade dependencias y el redirect usa un esquema propio, sin servidor *loopback* (se elimina `network.server`). (a) como alternativa. **Sin verificar** en macOS con sandbox. |
| D11 | Persistencia del estado | SwiftData / JSON `Codable` en Application Support | JSON `Codable`: el estado es pequeño (registro ≤ 200 entradas, ajustes, bookmarks) y es fácil de migrar y testear. |
| D12 | Ubicación del código | Repositorio git nuevo junto a este proyecto / subcarpeta | **Repositorio nuevo** (`../SystemBack`): ciclo de vida, CI y firma independientes. Este proyecto no es git. |

---

## 5. Arquitectura objetivo

```
SystemBack.app (Swift 6, SwiftUI, App Sandbox)
├── App
│   ├── WindowGroup principal (lista de trabajos de backup + historial)
│   ├── Settings scene (⌘,): carpetas, Drive, abrir al iniciar sesión, menu bar extra, idioma
│   ├── MenuBarExtra opcional (desactivado por defecto)
│   └── Commands: menú completo, Ayuda → política de privacidad
├── Core (paquete Swift local, testeable sin UI)
│   ├── BackupEngine      completo / incremental (por fecha de modificación) / actualización
│   ├── ArchiveWriter     formato D9, con progreso y cancelación (Swift concurrency)
│   ├── RestoreEngine     extracción con validación de rutas (anti path traversal)
│   ├── Registry          historial + estado local/Drive (sustituye a drive_registro.json)
│   └── FolderAccess      NSOpenPanel + security-scoped bookmarks
├── Drive
│   ├── GoogleAuth        D10, tokens en el Llavero (kSecClassGenericPassword)
│   └── DriveClient       REST v3 con URLSession: carpeta raíz, subida reanudable, listado, descarga, borrado
├── System
│   ├── Notifications     UserNotifications (permiso pedido en contexto)
│   └── LoginItem         SMAppService.mainApp con toggle en Ajustes
└── Datos: ~/Library/Containers/com.efjdev.systemback/Data/Library/
        ├── Application Support/SystemBack/  (registro, ajustes, bookmarks)
        ├── Logs/                             (os.Logger; nada sensible)
        └── destino de backups: elegido por el usuario (bookmark) o carpeta por defecto en el contenedor
```

Equivalencias con el Python actual (referencia para portar):

| Python | Swift |
| --- | --- |
| `tools/test_simple_backup.py`, `update_backup.py`, `create_incremental_backup.py` | `Core/BackupEngine` |
| Restauración con validación de rutas en `backup_interface.py` + tests `TestSafePath` | `Core/RestoreEngine` + tests portados |
| `tools/drive_client.py` (scope `drive.file`, carpeta `MisBackups`) | `Drive/DriveClient` (mismo scope; carpeta raíz renombrable) |
| `secret_store.py` | `Security` nativo |
| Protocolo SSE `line`/`error`/`timeout`/`done` | `AsyncStream<BackupEvent>` hacia la vista |
| `config.BACKUP_SCRIPTS` | No existe: no hay catálogo de scripts |
| Flask, `/execute`, Terminal, `osascript`, LaunchAgent | Eliminados |

Principios:
- **Un solo proceso**: nada de procesos hijos ni procesos que sigan vivos al salir (2.4.5(iii)).
- **Sin red salvo Google**: `network.client` solo para Drive y OAuth.
- **Sin dependencias** salvo que el spike demuestre que hacen falta (D9/D10). Cada dependencia SPM aporta su privacy manifest y se revisa.

---

## 6. Plan por fases

Las estimaciones son orientativas para una persona con dedicación parcial; la Fase 2 las recalibra.

### Fase 0 — Decisiones y cuentas (en curso)
- [x] D1–D7 cerradas (2026-11-14).
- Alta o renovación en **Apple Developer Program**. Comprobar si la cuenta es individual o de organización: el nombre del vendedor aparece en la tienda.
- Registrar el bundle ID `com.efjdev.systemback` y crear la app en App Store Connect. Ahí se confirma que el nombre "SystemBack" está libre.
- Firma: con Xcode basta la firma automática (*Apple Distribution* + perfil Mac App Store). Para `.pkg` manual haría falta además *Mac Installer Distribution*.
- Crear `systemback.efjdev.com` con política de privacidad (es/en) y página de soporte.
- Google Cloud: proyecto de producción, Drive API, pantalla de consentimiento externa con dominio `efjdev.com` verificado, *homepage* y política. Tipo de cliente OAuth según D10: el SDK GoogleSignIn usa un cliente de tipo iOS, válido para macOS; un redirect con esquema propio necesita confirmar el tipo en el spike.

**Salida**: cuenta activa, bundle ID registrado, app creada en App Store Connect y web publicada.

### Fase 1 — Seguridad e higiene de la herramienta Python ✔
Hecha el 2026-11-13; ver el seguimiento. Sigue siendo válida para el uso personal y no bloquea la app Swift.

### Fase 2 — Spike Swift (1–1,5 semanas) · gate técnico
Proyecto Xcode mínimo `SystemBack` con App Sandbox (entitlements generados por ajustes de build: `ENABLE_APP_SANDBOX`, `ENABLE_USER_SELECTED_FILES = readwrite`, `ENABLE_OUTGOING_NETWORK_CONNECTIONS`):
1. NSOpenPanel → bookmark → relanzar → acceso a la carpeta sin volver a pedirla.
2. **D9**: crear y restaurar un archivo de prueba en el formato elegido, con progreso, cancelación y validación de rutas. Medir con una carpeta de 1 GB.
3. **D10**: OAuth de Google en sandbox, token en el Llavero, subida reanudable de 50 MB a Drive y listado.
4. UserNotifications y `SMAppService.mainApp` (registrar y desregistrar).
5. Salir de la app: ningún proceso vivo.
6. Archive → validación → **TestFlight macOS** (build interno).

**Salida**: build en TestFlight; D8–D12 cerradas en el seguimiento.

### Fase 3 — Núcleo (3–4 semanas)
- `Core` como paquete Swift local, con tests (Swift Testing). Se portan como especificación los casos de `test_backup_interface.py`: backup con timestamp, aparece en la lista, se puede borrar, path traversal y validación de rutas en la restauración.
- Backup completo, incremental (por `contentModificationDate`) y de actualización; registro local con el estado local/Drive.
- Restauración desde backup local y desde Drive.
- Errores tipados con mensaje y sugerencia (equivalente a `error_code`/`hint`), sin perder el detalle en el log.

**Salida**: suite verde y backup + restauración completos desde la CLI de test o una UI mínima.

### Fase 4 — UI SwiftUI según HIG (2–3 semanas)
- Ventana principal: trabajos de backup (origen → destino, local/Drive), estado, historial y acciones.
- Settings scene, MenuBarExtra opcional con icono plantilla, Commands completos y Ayuda con la política de privacidad (5.1.1(i)).
- Confirmación con Cancelar en acciones destructivas: borrar backup y restaurar sobre una carpeta con datos.
- Accesibilidad: VoiceOver, teclado completo, Dynamic Type donde aplique y contraste. Modo claro/oscuro con colores semánticos.
- String Catalog es/en completo.
- Revisión con `apple-design` (Code audit + Accessibility audit) y con las skills `xcode-integration:accessibility-*`.

**Salida**: informe `apple-design` sin Critical ni High.

### Fase 5 — Producción (1 semana)
- `PrivacyInfo.xcprivacy` definitivo, revisado contra las APIs que se usen de verdad.
- Icono completo en el asset catalog, Info.plist (§7) y auditoría con `xcode-integration:audit-xcode-security-settings`.
- TestFlight externo opcional y prueba en una cuenta de usuario limpia.

**Salida**: archive validado sin avisos ITMS.

### Fase 6 — App Store Connect y envío (1 semana)
- Metadatos es/en: nombre, subtítulo, descripción, palabras clave, URL de soporte y de privacidad, categoría Utilidades y copyright.
- Dejar claro en el subtítulo y la descripción que hace backup de **carpetas elegidas**, no del sistema completo (mitiga el riesgo del nombre, guía 2.3).
- Capturas 16:10 (1280×800, 1440×900, 2560×1600 o 2880×1800).
- App Privacy: sin tracking ni analítica. El contenido que el usuario sube a **su** Drive no lo recoge el desarrollador; declararlo según el flujo real.
- Cumplimiento de exportación: solo HTTPS estándar → `ITSAppUsesNonExemptEncryption = NO`.
- Notas para Review: flujo en 3 pasos (elegir carpeta → backup → restaurar) y Drive con la cuenta del revisor.

### Fase 7 — Review y post-lanzamiento
- Rechazos registrados en el seguimiento, con la guía citada y la acción tomada.
- Actualizaciones solo por la App Store (2.4.5(vii)).

**Duración total orientativa: 9–12 semanas** tras la Fase 0, condicionada por la Fase 2.

---

## 7. Configuración objetivo (borrador)

### Info.plist / ajustes de target

| Clave | Valor |
| --- | --- |
| `CFBundleIdentifier` | `com.efjdev.systemback` |
| `CFBundleDisplayName` | `SystemBack` |
| `CFBundleShortVersionString` / `CFBundleVersion` | `1.0.0` / número de build incremental |
| `LSApplicationCategoryType` | `public.app-category.utilities` |
| `LSMinimumSystemVersion` | según D8 (propuesta 14.0) |
| `ITSAppUsesNonExemptEncryption` | `false` |
| `NSHumanReadableCopyright` | titular real |
| `CFBundleURLTypes` | esquema propio del redirect OAuth (solo si D10 = b) |
| `CFBundleLocalizations` / String Catalog | `es`, `en` |

### Entitlements y privacy manifest
Entitlements efectivos (verificados con `codesign -d --entitlements -`): `app-sandbox`, `files.user-selected.read-write`, `network.client`. No hay `network.server` ni `files.bookmarks.app-scope` (este último ya no figura en el catálogo de entitlements). Privacy manifest: [`SystemBack/PrivacyInfo.xcprivacy`](../../SystemBack/PrivacyInfo.xcprivacy).

---

## 8. Riesgos

| Riesgo | Prob. | Impacto | Mitigación |
| --- | --- | --- | --- |
| Coste de la reescritura mayor de lo estimado | Media | Alto | Alcance v1 cerrado (D1/D4). El núcleo se porta guiado por los tests Python. |
| OAuth de Google en sandbox (redirect, tipo de cliente, verificación) | Media | Alto | Spike en la Fase 2 con dos alternativas (D10). Verificación de marca iniciada en la Fase 0. |
| Formato de archivo sin soporte nativo | Media | Medio | D9 en el spike: librería SPM auditada o `.zip`. |
| Nombre "SystemBack": colisión con *Systemback* (Linux) y lectura de "backup del sistema" | Media | Medio | Riesgo aceptado (D6). Subtítulo y descripción precisos. Si App Store Connect o Review lo rechazan, cambiar nombre antes del envío (el bundle ID puede mantenerse). |
| Review: funcionalidad mínima (4.2) | Baja-media | Alto | Producto completo: local + Drive + restauración + programación por login item. |
| Aviso ITMS-91053 por required reason API | Media | Bajo | Privacy manifest desde el primer build de TestFlight. |
| Pérdida de datos al restaurar | Baja | Alto | Restaurar a una carpeta nueva por defecto; sobrescribir solo con confirmación. Tests de rutas. |

---

## 9. Skills y herramientas de apoyo

| Skill / herramienta | Uso en el plan |
| --- | --- |
| `write-swift`, `xcode-integration:swiftui-specialist` | Implementación SwiftUI y Swift 6 (concurrencia estricta). |
| MCP `xcode` (BuildProject, RunAllTests, GetBuildLog, RenderPreview…) | Builds, tests y previews desde la sesión. |
| `xcode-integration:audit-xcode-security-settings` | Ajustes de seguridad del proyecto (Fase 5). |
| `xcode-integration:translation` / `translation-coordinator` | String Catalog es/en. |
| `xcode-integration:accessibility-voiceover-specialist`, `-dynamic-type-specialist`, `-sufficient-contrast-specialist` | Accesibilidad (Fase 4). |
| `apple-design` | HIG macOS: menú, Settings, menu bar extra, privacidad. Revisión de las Fases 4 y 6. |
| `security-review` | OAuth, Llavero y restauración (Fases 3 y 5). |

No he instalado skills externas: el intento de buscar con `npx skills` lo bloqueó la política de permisos. Si quieres alguna concreta (App Store Connect / Fastlane), indícala y la apruebas.
