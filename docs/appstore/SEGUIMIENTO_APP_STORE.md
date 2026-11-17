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
| D6 | Nombre / bundle ID / dominio | SystemBack · `com.edefrutos.systemback` (cambiado el 2026-11-14) · `efjdev.com/systemback/` | 2026-11-14 | Riesgo aceptado: colisión con *Systemback* (Linux) y lectura de "backup del sistema" (plan §8). Subdominio alineado con el nombre en lugar de `sysback` |
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
- [ ] Bundle ID `com.edefrutos.systemback` registrado
- [ ] App creada en App Store Connect (confirma que el nombre "SystemBack" está libre)
- [ ] Firma automática de Xcode operativa (Apple Distribution + perfil Mac App Store)
- [ ] Página `efjdev.com/systemback/` y sección `efjdev.com/privacidad/` (soporte: `efjdev.com/soporte/`)
- [x] Google Cloud: proyecto de producción, Drive API, pantalla de consentimiento externa, dominio `efjdev.com` verificado, marca verificada (2026-11-16)

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
- [x] Capturas 16:10: 6 por idioma (es, en) a 2880×1800 en `docs/appstore/capturas/` (2026-11-17)
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

### 2026-11-14 (F2 → paridad con la app original)
- Prueba visual del spike validada por el usuario. Log de Xcode sin errores propios (solo ruido del sistema: `linkd.autoShortcut`/AppIntents, puerto de tarea del depurador, ventana de Liquid Glass).
- Commit inicial `f2c0de5`.
- Recuperadas funciones de la app original sin depender de Google:
  - «Actualizar backup» = backup completo + el anterior a la Papelera (recuperable; si el volumen no tiene Papelera, se avisa y el backup nuevo se conserva).
  - Lista de backups del destino (`ArchiveCatalog`) con restaurar, mostrar en Finder y mover a la Papelera.
  - Panel «Actividad» (inspector) con registro en vivo; progreso con fase (escaneo indeterminado → determinado) y fichero en curso.
  - Identidad visual de la original con colores del sistema: tarjetas de acción y etiquetas Completo/Cambios/Local.
- Tabla de paridad: MongoDB, limpieza de cachés/imágenes, verificación web y ejecución de scripts quedan fuera del producto (D4, guía 2.5.2).
- Núcleo: 29 tests.
- El usuario está creando el client ID de Google (tipo iOS, bundle `com.efjdev.systemback`, scope `drive.file`) para D10.

### 2026-11-14 (pruebas del usuario, ronda 2)
- Backup completo: OK. «Actualizar» y restaurar desde la lista: fallan; restaurar desde archivo: crea una carpeta nueva en el destino (comportamiento previsto, pero no lo que el usuario esperaba).
- `Failed to open store index with errno: 2`: mensaje del sistema que no identifica la causa. No hay denegaciones del sandbox visibles en `log show`.
- Causa probable del menú `…` sin efecto: `.fileImporter` activado desde un menú que se está cerrando (aviso `makeKeyWindow … _NSGlassEffectWindow`). Cambiado a NSOpenPanel (`FolderPicker`) + botones visibles en cada fila.
- Diagnóstico añadido al panel Actividad: backup anterior que se reemplaza, ubicación en la Papelera y carpeta de restauración. El aviso final de restauración ofrece «Mostrar en Finder».
- Español por defecto con inglés en Ajustes (`AppLanguage`); String Catalog con 97 cadenas es/en; región de desarrollo `es`; privacy manifest añade UserDefaults (CA92.1).
- Pendiente: repetir «Actualizar» y restaurar desde la lista con el panel Actividad abierto.


### 2026-11-14 (pruebas del usuario, ronda 3)

- El backup de las 13:38 que faltaba lo borró el usuario: no es un fallo de la app.
- Nuevo: **Restaurar en la carpeta original** (`RestoreEngine.restoreInPlace`). No toca los idénticos (mismo tamaño y fecha), mueve a la Papelera lo que sustituye (deshacible) y aborta si no puede apartarlo. Rechaza rutas que escapen por enlaces. Pide confirmación. 5 tests nuevos (34 en total).
- Corregido: «Mostrar en Finder» fallaba en sandbox (`Sandbox extension creation failed … public.file-url`). Ahora abre el acceso de la bookmark antes de llamar a `NSWorkspace` (`AppModel.reveal`).
- Pendiente: el usuario vuelve a probar «Actualizar backup» con el panel Actividad abierto.
- Prueba del usuario OK: restaurar en origen, «Mostrar en Finder» y «Actualizar backup» (el anterior va a la Papelera de iCloud, `~/Library/Mobile Documents/.Trash`, porque Documentos se sincroniza con iCloud; eso explica también el backup «desaparecido» de las 13:38).
- Añadido: `.help` en todos los controles de solo icono, en las etiquetas y en las tarjetas (si están desactivadas, explica por qué). «Restaurar desde archivo» usa ahora `doc.zipper`.
- Corregido: plurales («1 elementos») con variaciones `plural` y `substitutions` en el catálogo. Verificado es/en con el bundle compilado.

### 2026-11-14 (cuentas y web)

- **D6 revisada:** bundle ID `com.edefrutos.systemback` (proyecto, `Logger` y docs actualizados). Team ID `V29BTBRY6G` (`DEVELOPMENT_TEAM` en Debug y Release). Los datos de pruebas del contenedor sandbox anterior (`com.efjdev.systemback`) no se migran.
- **Web:** sin subdominio, porque la app no tiene servidor.
  - Sección «SystemBack» publicada en `https://efjdev.com/privacidad/`, con la declaración de uso limitado de Google. No hay ancla: Elementor quita el `id`.
  - Página `efjdev.com/systemback/` creada como borrador (post 136), con la misma estructura que Replacer. Pendiente de que el usuario la publique.
  - `AppLinks` apunta a `https://efjdev.com/privacidad/` y `https://efjdev.com/soporte/`.
- **Google:** el cliente OAuth actual es de tipo «Escritorio». Hace falta uno de tipo **iOS** con bundle `com.edefrutos.systemback` para `ASWebAuthenticationSession` con el esquema del client ID invertido.
- **D10 ampliada:** Drive entra en la v1.0. La publicación espera a la verificación de la marca y del dominio en la pantalla de consentimiento de Google.
- **App Store Connect:** respuestas preparadas en `docs/appstore/APP_STORE_CONNECT.md`.
- App Store Connect: «SystemBack» se acepta en es-ES, pero está ocupado en inglés. En la localización en se usa `SystemBack: Folder Backups`. El nombre en el Mac (`CFBundleDisplayName`) sigue siendo «SystemBack».

### 2026-11-14 (Google Drive, fase A)

- Cliente OAuth **iOS** creado por el usuario (`784383135948-i33ib…`), con bundle `com.edefrutos.systemback`.
- Hecho:
  - inicio de sesión con PKCE y token de renovación en el Llavero;
  - en Ajustes, conectar y desconectar (al desconectar se revoca el acceso en Google);
  - por trabajo, la opción «Subir los backups nuevos a Google Drive»;
  - por fila, la etiqueta «Drive» y el botón «Subir a Google Drive», con progreso en Actividad y cancelación.
- Permisos del sandbox sin cambios (solo `network.client`).
- 43 tests en el núcleo: 8 de Drive y OAuth y 1 de compatibilidad de `jobs.json`.
- Pendiente (fase B): listar los backups que solo están en Drive y restaurarlos (descargar y luego restaurar), y enviarlos a la papelera de Drive.
- Pendiente (usuario): pantalla de consentimiento con el permiso `drive.file`, usuarios de prueba mientras esté en «Testing», y verificación de marca y dominio antes de publicar.

### 2026-11-15 (Google Drive, fase B)

- Consola de Google configurada por el usuario: Drive API habilitada, permiso `drive.file`, usuario de prueba, app «En prueba».
- Primera prueba real: la subida funcionó. Dos fallos de decodificación corregidos con test:
  - Google omite `files` si la lista está vacía;
  - al crear carpeta con `fields=id` no llega `name`.
- Decisión: el destino sigue siendo local; Drive es copia adicional (no hay destino «solo Drive»).
- Hecho:
  - la lista de backups incluye los que solo están en Drive (etiqueta «Drive»);
  - descargar a la carpeta de destino, restaurar en carpeta nueva o en la original (descarga primero), mandar a la papelera de Drive;
  - en filas locales con copia en Drive, menú contextual para mandar esa copia a la papelera de Drive.
- 47 tests en el núcleo. 156 cadenas en el catálogo.
- Pendiente: probar la fase B con la cuenta real.

### 2026-11-15 (icono, revisión de diseño y capturas)

- **Icono:** sale de `assets/SystemBack.jpg`, la versión sin texto (las HIG piden texto solo si es esencial).
  - Recortado a cuadrado y escalado a 1024 px, sin máscara. El sistema aplica las esquinas.
  - Se generan los tamaños de 16 a 1024 en `AppIcon.appiconset`.
- **Revisión de diseño** en `REVISION_DISENO.md`. Corregido:
  - órdenes en la barra de menús con atajos (`AppCommands.swift`);
  - el fallo al leer Drive se muestra en la lista, sin alerta;
  - contraste del texto de las etiquetas;
  - el aviso de `onChange`.
- **Pendiente para la v1.1:** icono simplificado por capas en Icon Composer.
- **Capturas** documentadas en `CAPTURAS.md`.

### 2026-11-15 (web)

- `efjdev.com/systemback/` (página 136) publicada. El texto de Drive se cambia de «próximamente» a función disponible (subir y restaurar; la app solo ve sus archivos).
- La portada (página 25) tiene la tarjeta «SystemBack · Mac App Store · próximamente», que enlaza a la página 136.
- La sección de SystemBack en `/privacidad/` ya describía Drive correctamente (OAuth, `drive.file`, Llavero, uso limitado). No se ha tocado.
- Siguiente paso: en Google Auth Platform › Centro de verificación, solicitar la verificación de marca. Las URLs de inicio y de privacidad ya responden.

### 2026-11-16 (Google)

- Google Auth Platform › Centro de verificación: «Se verificó la información de tu marca y se muestra a los usuarios». La pantalla de consentimiento muestra SystemBack con el dominio `efjdev.com`.
- Permiso único `drive.file` (no sensible): no hace falta revisión de seguridad.
- Comprobar en Público que el estado de publicación es «En producción». En «En prueba» solo entran los usuarios de prueba y el token de renovación caduca a los 7 días.
- Tras pasar a producción: desconectar y volver a conectar Drive en la app para obtener un token de producción.

### 2026-11-16/17 (capturas y ajustes de la app)

- **Rutas con `~/`:** la app abrevia la carpeta de inicio real (`getpwuid`, no el contenedor del sandbox) en la interfaz, los diálogos y el registro. `PathDisplay` en SystemBackCore, con tests (`/Users/anabel` no se abrevia si el inicio es `/Users/ana`).
- **«Último backup hace…»:** la barra lateral y la cabecera comparten un reloj por minutos (`TimelineView(.everyMinute)`) y ya no se contradicen. Nuevo texto «Último backup hace un momento».
- **Aspecto en Ajustes** (Automático, Claro, Oscuro), a petición del usuario. Se aparta de las HIG (`dark-mode.md`); justificado en `REVISION_DISENO.md`.
- **Columnas de la lista de backups alineadas:** etiquetas Local y Drive, tamaño y botones en huecos de ancho fijo. Un `Group` o un `if` vacío no ocupa sitio; se usa `ZStack` con `frame`.
- **Capturas:** 6 en es y 6 en en, 2880×1800, RGB, sin transparencia, con datos de `~/Demo`. Revisadas: sin usuario, discos, correo ni Terminal. Pasos y orden en `CAPTURAS.md`.
- `.gitignore`: `Icon\r` (icono de carpeta de Finder) y `scripts/` locales.
