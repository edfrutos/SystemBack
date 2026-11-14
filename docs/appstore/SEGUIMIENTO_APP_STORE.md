# Seguimiento — SystemBack en Mac App Store

> Documento vivo. Actualiza estados, fechas y la bitácora en cada sesión.
> Plan de referencia: [`PLAN_APP_STORE.md`](PLAN_APP_STORE.md).
> Desde el 2026-11-14 este documento vive en el repositorio `SystemBack`. La copia del repositorio Python queda congelada.

Leyenda de estado: `[ ]` pendiente · `[~]` en curso · `[x]` hecho · `[!]` bloqueado

---


## Estado global

| Fase | Estado | Inicio | Fin | Notas |
| --- | --- | --- | --- | --- |
| F0 Decisiones y cuentas | `[~]` | 2026-11-13 | | D1–D7 cerradas el 2026-11-14; faltan cuentas, dominio y Google Cloud |
| F1 Seguridad e higiene (herramienta Python) | `[~]` | 2026-11-13 | | Pertenece al repositorio Python; solo queda regenerar `dist/` allí |
| F2 Spike Swift (gate técnico) | `[~]` | 2026-11-14 | | Núcleo + app compilando; faltan prueba interactiva, OAuth Drive y TestFlight |
| F3 Núcleo Swift | `[ ]` | | | |
| F4 UI SwiftUI HIG | `[ ]` | | | |
| F5 Producción | `[ ]` | | | |
| F6 App Store Connect + envío | `[ ]` | | | |
| F7 Review / post-lanzamiento | `[ ]` | | | |

---

## Registro de decisiones

| ID | Decisión | Elegido | Fecha | Motivo |
| --- | --- | --- | --- | --- |
| D1 | Alcance del producto | Producto para la App Store: backup de carpetas elegidas, local + Google Drive | 2026-11-14 | Objetivo explícito: App Store |
| D2 | Stack | Reescritura en Swift/SwiftUI | 2026-11-14 | Sandbox, firma y APIs nativas sin intérprete embebido |
| D3 | Empaquetado | Proyecto Xcode nativo | 2026-11-14 | Consecuencia de D2. Briefcase descartado: empaqueta Python |
| D4 | MongoDB | Fuera del producto; estado local en el contenedor | 2026-11-14 | El backup de Atlas sigue en la herramienta Python |
| D5 | Modelo de negocio | Gratis | 2026-11-14 | Sin StoreKit |
| D6 | Nombre / bundle ID / dominio | SystemBack · `com.efjdev.systemback` · `systemback.efjdev.com` | 2026-11-14 | Riesgo aceptado: colisión con *Systemback* (Linux) y lectura de "backup del sistema" (plan §8). Subdominio alineado con el nombre en lugar de `sysback` |
| D7 | Idiomas | es + en | 2026-11-14 | String Catalog en el bundle |
| D8 | macOS mínimo | **macOS 14** | 2026-11-14 | SwiftData/`@Observable`/SMAppService disponibles; base amplia |
| D9 | Formato del backup | **`.tar.gz` propio** (tar POSIX/PAX + gzip sobre Compression `.zlib` + `crc32` de zlib) | 2026-11-14 | Sin dependencias; verificado con `tar`/`gunzip` del sistema y `tarfile` de Python en ambos sentidos. 1 GiB: backup 17,5 s, restauración 1,4 s |
| D10 | OAuth de Google | **`ASWebAuthenticationSession` + PKCE + REST** (alternativa: SDK GoogleSignIn) | 2026-11-14 | Elegido por el usuario; pendiente de implementar y probar en sandbox (necesita client ID de Google) |
| D11 | Persistencia | **JSON `Codable`** (`JobStore`, versionado) | 2026-11-14 | Implementado y testeado |
| D12 | Ubicación del código | **Repositorio git independiente `../SystemBack`** | 2026-11-14 | El repositorio Python queda intacto como herramienta personal |

---

## Checklist por fase

### F0 — Decisiones y cuentas
- [x] D1–D7 cerradas
- [ ] Apple Developer Program activo (¿individual u organización?)
- [ ] Bundle ID `com.efjdev.systemback` registrado
- [ ] App creada en App Store Connect (confirma que el nombre "SystemBack" está libre)
- [ ] Firma automática de Xcode operativa (Apple Distribution + perfil Mac App Store)
- [ ] `systemback.efjdev.com` creado con política de privacidad (es/en) y página de soporte
- [ ] Google Cloud: proyecto de producción, Drive API, pantalla de consentimiento externa, dominio `efjdev.com` verificado, verificación de marca iniciada

### F1 — Seguridad e higiene
- [x] `credentials/` excluido de `setup_py2app.py` (solo se empaqueta `client_secrets.json`) + test
- [ ] `dist/` regenerado (`make build-dev`) y comprobado sin `token.json`/`mongodb.json`
- [x] Token OAuth de Drive antiguo inservible: Google respondió `invalid_grant` al renovarlo (2026-11-13); se re-autenticó y luego se desconectó desde la UI
- [x] Token de sesión + validación `Origin`/`Host` en todas las rutas Flask
- [x] Tests de auth/CSRF añadidos (`TestSessionAuth`)
- [x] Token Drive en el Llavero (`secret_store`, migración automática)
- [x] URI MongoDB en el Llavero (UI + scripts 08/09/10)
- [x] Versión única en `config.APP_VERSION` (2.3.0)
- [x] `--install` desactivado en builds empaquetados (`sys.frozen`)
- [x] Validación manual: `make run` abre la ventana nativa con sesión (302 + cookie); Drive y MongoDB migraron al Llavero y se borraron los ficheros; revocar/borrar desde la UI limpia el Llavero
- [x] Token de sesión redactado en el log de werkzeug (`_RedactTokenFilter`) + test


### F2 — Spike Swift (gate técnico)
- [x] Repositorio y proyecto Xcode `SystemBack` creados (D12), paquete local `SystemBackCore` enlazado
- [x] App Sandbox por ajustes de build; `codesign -d --entitlements -` muestra solo `app-sandbox`, `user-selected.read-write` y `network.client`; `codesign --verify --deep --strict` OK
- [ ] NSOpenPanel + security-scoped bookmark funcionando tras relanzar (código hecho; falta prueba manual)
- [x] D9: crear y restaurar con progreso, cancelación y validación de rutas; 1 GiB medido
- [x] Privacy manifest incluido en el bundle (códigos FileTimestamp pendientes de verificar)
- [ ] D10: OAuth de Google en sandbox, token en el Llavero, subida reanudable de 50 MB y listado
- [ ] UserNotifications funcionando (código hecho; falta prueba manual)
- [ ] SMAppService registrar/desregistrar funcionando (código hecho; falta prueba manual)
- [ ] Ningún proceso vivo tras salir
- [ ] Sin `Sandbox: deny` en Consola
- [ ] Archive validado y build interno en TestFlight (macOS)
- [ ] D8–D12 registradas

### F3 — Núcleo Swift
- [ ] Paquete `Core` con tests (Swift Testing)
- [ ] Casos de `test_backup_interface.py` portados como especificación (timestamp, listado, borrado, path traversal, rutas del archivo al restaurar)
- [ ] Backup completo, incremental y de actualización
- [ ] Registro local con estado local/Drive
- [ ] Restauración local y desde Drive (a una carpeta nueva por defecto)
- [ ] Errores tipados con mensaje + sugerencia
- [ ] `DriveClient`: carpeta raíz, subida reanudable, listado, descarga, borrado

### F4 — UI SwiftUI HIG
- [ ] Ventana principal (trabajos, estado, historial)
- [ ] Settings scene (⌘,)
- [ ] Commands completos; Ayuda → política de privacidad (5.1.1(i))
- [ ] MenuBarExtra opcional, desactivado por defecto, icono plantilla
- [ ] Toggle "Abrir al iniciar sesión" (SMAppService)
- [ ] Confirmación con Cancelar en acciones destructivas
- [ ] Modo claro/oscuro con colores semánticos
- [ ] Teclado completo + VoiceOver probado
- [ ] Contraste ≥ 4,5:1 medido
- [ ] String Catalog es/en completo
- [ ] Informe `apple-design` sin Critical/High

### F5 — Producción
- [ ] Info.plist / ajustes de target definitivos (§7 del plan)
- [ ] `PrivacyInfo.xcprivacy` incluido y revisado contra las APIs reales
- [ ] Icono completo en el asset catalog
- [ ] Auditoría `audit-xcode-security-settings`
- [ ] Prueba en una cuenta de usuario limpia
- [ ] Archive validado sin avisos ITMS

### F6 — App Store Connect y envío
- [ ] Nombre, subtítulo, descripción, palabras clave
- [ ] URL de soporte + URL de la política de privacidad
- [ ] Capturas 16:10 (1280×800 / 1440×900 / 2560×1600 / 2880×1800)
- [ ] Etiquetas App Privacy
- [ ] Clasificación por edades
- [ ] Cumplimiento de exportación
- [ ] Notas para Review
- [ ] Build seleccionado y enviado

### F7 — Review
- [ ] Respuesta de Review registrada
- [ ] Publicada

---

## Registro de rechazos de App Review

| Fecha | Build | Guía citada | Motivo resumido | Acción | Estado |
| --- | --- | --- | --- | --- | --- |
| | | | | | |

---

## Bitácora

### 2026-11-13
- Análisis inicial del código frente a las App Review Guidelines (2.4.5, 2.5.2, 5.1.1) y las HIG macOS.
- Creados `PLAN_APP_STORE.md`, este seguimiento y los borradores de entitlements y privacy manifest.
- Hallazgos urgentes: el bundle `dist/` incluye `credentials/` y el servidor Flask local no tiene autenticación. Ver plan §3, filas 1–2.

### 2026-11-13 (F1)
- Nuevo `secret_store.py` (Llavero vía PyObjC `Security`, sin dependencias nuevas). Probado contra el Llavero real con un servicio de prueba.
- `drive_client.py` y la configuración MongoDB (UI y scripts) usan el Llavero. Los ficheros heredados se migran y se borran tras verificar.
- Flask: `before_request` con Host loopback, `Origin` y token por arranque → cookie HttpOnly SameSite=Strict. `main.py` y la barra de menús abren `app_url()`.
- `setup_py2app.py`: solo `client_secrets.json`; versión desde `config`.
- `Makefile`: detección de un intérprete funcional (`.venv` estaba roto: apuntaba a Python 3.14.3 eliminado por Homebrew).
- Tests: 42 → 65, todos en verde. Prueba de humo con curl sobre servidor real: sin sesión, rebinding y CSRF dan 403.
- Validación manual con `make run`: login por token OK, migración al Llavero OK (log `migrado al Llavero`). El token Drive heredado ya era inválido (`invalid_grant`).
- `start_general_backup_interface.sh` elige un venv funcional (`.venv` roto eliminado por el usuario).
- Detectado y corregido: el access log de werkzeug guardaba `/?token=…` en `logs/backup_interface.log`. Filtro de redacción + test (66 tests).
- Deuda detectada (previa): `TestBackupFlow` ejecuta `tools/test_simple_backup.py` real y deja `backups/edf_test_src_*` en el proyecto.

### 2026-11-14 (F0)
- Cerradas D1–D7: producto para la App Store, reescritura en Swift/SwiftUI, proyecto Xcode nativo, MongoDB fuera, gratis, SystemBack / `com.efjdev.systemback` / `systemback.efjdev.com`, es+en.
- Conflicto resuelto: D3 = Briefcase era incompatible con D2 = Swift; se adopta Xcode nativo.
- Aviso de nombre: *Systemback* es una herramienta Linux conocida (discontinuada). Riesgo aceptado; mitigación en el subtítulo y la descripción.
- Plan reescrito a v2 (Swift). v1 (Python) archivada en `archivo/PLAN_APP_STORE_v1_python.md`.
- Borradores: `EDFBackups.entitlements` sustituido por `SystemBack.entitlements` (sin `network.server`). Comentario del privacy manifest actualizado para Swift.
- Nuevas decisiones abiertas D8–D12 para el spike F2.

### 2026-11-14 (F2)
- Repositorio nuevo e independiente `SystemBack` (git, rama `main`). El repositorio Python no se ha modificado.
- Proyecto Xcode creado con el plugin de Xcode (plantilla de app macOS). Ajustes: bundle `com.efjdev.systemback`, macOS 14, Swift 6, actor principal por defecto, sandbox con `user-selected.read-write` y `network.client`, categoría Utilidades, `ITSAppUsesNonExemptEncryption = NO`, regiones en/es.
- Aviso: los cambios de ajustes hechos con las herramientas MCP de Xcode quedan en memoria y se pierden si se cierra el workspace sin guardar. Los ajustes definitivos se escribieron en el proyecto y se verificaron en el binario.
- `com.apple.security.files.bookmarks.app-scope` ya no aparece en el catálogo de entitlements de Xcode ni en la lista de Apple. Se omite; las bookmarks con security scope se prueban en el spike.
- `SystemBackCore` (paquete Swift, sin dependencias): tar POSIX/PAX, gzip, backup completo/incremental, restauración segura, `FolderReference` (bookmarks) y `JobStore`. Suite de 25 tests con Swift Testing (casos portados de la suite Python + fixture creado con `tarfile` de Python).
- Bug encontrado y corregido: `skipDescendants()` tras excluir un fichero (`.DS_Store`) saltaba la subcarpeta anterior.
- Rendimiento con 1 GiB (Release): backup 17,5 s (`gzip -5` del sistema ≈ 10 s equivalentes), restauración 1,4 s, tras cambiar el CRC-32 a `crc32` de zlib.
- App SwiftUI del spike: trabajos origen→destino, backup completo e incremental con progreso y cancelación, restauración a carpeta nueva, notificaciones con permiso en contexto, "Abrir al iniciar sesión" con SMAppService, menú Ayuda con la política de privacidad.

