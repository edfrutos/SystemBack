# Plan de actuación — EDF Backups en Mac App Store

> Documento de preparación. Estado del análisis: **2026-11-13**.
> Seguimiento operativo en [`SEGUIMIENTO_APP_STORE.md`](SEGUIMIENTO_APP_STORE.md).
> Borradores técnicos en [`drafts/`](drafts/).

---

## 1. Resumen ejecutivo

Hoy la app es una **herramienta personal de desarrollo**. Es un servidor Flask local dentro de una ventana `pywebview`, empaquetado con `py2app`. Hace backup **de su propio directorio de proyecto**, ejecuta scripts Python como subprocesos y lanza AppleScript (Finder, Terminal, notificaciones). Guarda credenciales y datos dentro del árbol del proyecto y se arranca al iniciar sesión mediante un LaunchAgent instalado por script.

Ese diseño choca de frente con las reglas de la Mac App Store: sandbox obligatorio, contenedor de datos, nada de código ejecutado fuera del bundle y nada de arranque automático sin consentimiento. **No basta con firmar y subir**: hay que hacer tres cosas.

1. **Redefinir el producto**: pasar de "backup del entorno EDF" a "backup de carpetas que elige el usuario, en local y en Google Drive".
2. **Refactorizar para el sandbox**: rutas, ejecución, diálogos, notificaciones, credenciales y arranque en login.
3. **Rehacer el empaquetado**: entitlements, firma de todos los binarios anidados, privacy manifest, `.pkg` y subida a App Store Connect.

Recomendación: **mantener el stack Python + pywebview**, eliminar progresivamente el servidor HTTP y la ejecución por subprocesos, y validar antes, con un *spike*, la cadena de empaquetado (py2app frente a Briefcase).

---

## 2. Requisitos de Apple aplicables (texto vigente)

Citas literales de las App Review Guidelines, consultadas el 2026-11-13:

| Guía | Texto | Impacto en EDF Backups |
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

---

## 4. Decisiones previas (bloquean la Fase 1)

| ID | Decisión | Opciones | Recomendación |
| --- | --- | --- | --- |
| D1 | Alcance del producto | (a) Utilidad genérica de backup de carpetas + Drive (+ MongoDB opcional); (b) mantener herramienta interna y distribuir **fuera** de la App Store con Developer ID + notarización | (a) si el objetivo es la App Store. Si solo la usas tú, (b) cuesta mucho menos. |
| D2 | Stack | (a) Python + pywebview refactorizado; (b) reescritura en Swift/SwiftUI | (a) en la v1. Revaluarlo si el spike de empaquetado falla. |
| D3 | Empaquetado | (a) py2app + firma manual; (b) Briefcase (BeeWare) con plantilla Xcode | Spike comparativo (Fase 2). Mi preferencia provisional es (b): proyecto Xcode nativo para entitlements, firma y privacy manifest. **Sin verificar** en este proyecto. |
| D4 | MongoDB | Incluir en v1 / dejar para v1.1 | v1.1. Reduce superficie de Review y la etiqueta de privacidad. |
| D5 | Modelo de negocio | Gratis / pago / suscripción | Gratis en la v1. Las compras in-app añaden StoreKit y otras revisiones. |
| D6 | Nombre, bundle ID y dominio | Nombre comercial, `com.<dominio-propio>.backups` | Hace falta un dominio propio para la política de privacidad y el *homepage* de OAuth de Google. |
| D7 | Idiomas | es / es+en | es+en: amplía el mercado y la localización va en el bundle (2.4.5(ix)). |

---

## 5. Arquitectura objetivo

```
EDF Backups.app (sandbox)
├── Proceso único Python (bundle firmado)
│   ├── pywebview (WKWebView) ── js_api bridge ──► core/ (lógica de backup in-process)
│   ├── Menú nativo macOS (pywebview menu / AppKit vía PyObjC)
│   ├── Menu bar extra opcional (rumps o NSStatusItem)
│   ├── Notificaciones: UserNotifications (PyObjC)
│   ├── Diálogo de carpetas: NSOpenPanel (pywebview create_file_dialog)
│   ├── Credenciales: Llavero (Security.framework / keyring)
│   └── Login item: SMAppService.mainApp (con consentimiento)
└── Datos: ~/Library/Containers/<bundle-id>/Data/
        ├── Library/Application Support/  (registro, ajustes, bookmarks)
        ├── Library/Logs/
        └── Backups por defecto (o un destino elegido por el usuario con security-scoped bookmark)
```

Cambios estructurales clave:

1. **`config.py` → rutas de datos de usuario**. `PROJECT_ROOT` queda solo como ubicación de recursos (lectura). Las rutas de datos se derivan de `~/Library/Application Support/<bundle-id>`, que dentro del sandbox se resuelve automáticamente al contenedor. En desarrollo, sin sandbox, apuntan a la misma ruta sin contenedor.
2. **Backups in-process**. `tools/test_simple_backup.py`, `update_backup.py` y `create_incremental_backup.py` se convierten en funciones de un paquete `core/` que se importan y ejecutan en un hilo. El *streaming* de progreso se conserva con el mismo contrato de eventos (`line`/`error`/`timeout`/`done`), pero llega por el puente JS (`window.evaluate_js`) en lugar de SSE. Desaparecen los `subprocess` y los scripts arbitrarios.
3. **Retirar el servidor Flask**, en dos pasos:
   - **Paso intermedio** (permite publicar antes): Flask sigue, pero con un token aleatorio por sesión, inyectado en la ventana y exigido en cada petición, más comprobación de `Origin`/`Host`. Requiere el entitlement `network.server`.
   - **Objetivo**: `js_api` de pywebview y `templates/index.html` servido como fichero local. Se elimina el puerto, la superficie de ataque y el entitlement de servidor (salvo el que pida el *loopback* de OAuth, ver punto 5).
4. **Acceso a carpetas del usuario**: `NSOpenPanel` + entitlement `files.user-selected.read-write` + **security-scoped bookmarks** (`files.bookmarks.app-scope`), para recordar carpetas origen y destino entre sesiones.
5. **Google Drive**: el flujo `InstalledAppFlow.run_local_server` abre un servidor *loopback* temporal, que necesita `network.server`. Es aceptable, aunque conviene verificarlo en sandbox durante el spike. El token va al Llavero. `client_secrets.json` de tipo "Desktop app" se empaqueta solo con el *client ID/secret* público de la app; nunca `token.json`. Google considera `drive.file` un scope no sensible, pero exige pantalla de consentimiento con dominio, *homepage* y política de privacidad verificados.

---

## 6. Plan por fases

Cada fase tiene criterio de salida verificable. Estimaciones orientativas para una persona.

### Fase 0 — Decisiones y cuentas (0,5–1 semana)
- Cerrar D1–D7.
- Alta o renovación en **Apple Developer Program** (individual u organización).
- Registrar el bundle ID definitivo y crear el registro de la app en App Store Connect.
- Certificados: *Apple Distribution* (o *3rd Party Mac Developer Application*) y *Mac Installer Distribution* (o *3rd Party Mac Developer Installer*). Perfil de aprovisionamiento Mac App Store.
- Dominio y web mínima con **política de privacidad** y página de soporte.
- Proyecto OAuth de Google para producción: pantalla de consentimiento externa y verificación de marca.

**Salida**: decisiones firmadas en `SEGUIMIENTO_APP_STORE.md`, certificados en el llavero y la app creada en App Store Connect.

### Fase 1 — Seguridad e higiene (1 semana) · también vale para el uso actual
- Excluir `credentials/` de `setup_py2app.py` y regenerar `dist/`. **Revocar y rotar** el `token.json` y los secretos que hayan ido en bundles ya generados.
- Token por sesión + validación de `Origin`/`Host` en todas las rutas de Flask, con tests.
- Migrar el token de Drive y la URI de MongoDB al Llavero.
- Unificar la versión en un solo sitio (`config.APP_VERSION`) y leerla desde `setup`.
- Retirar `main.py --install` de los builds empaquetados.

**Salida**: la suite pasa, hay tests nuevos de auth/CSRF y `dist/` no contiene `credentials/`.

### Fase 2 — Spike de empaquetado sandbox (1–1,5 semanas) · **gate go/no-go**
Construir una app mínima "hola mundo" con el mismo stack (pywebview + PyObjC + rumps) y:
1. Activar App Sandbox con los entitlements de [`drafts/EDFBackups.entitlements`](drafts/EDFBackups.entitlements).
2. Firmar **todos** los Mach-O anidados (`.so`, `.dylib`, intérprete) de dentro hacia fuera y la app al final, con entitlements.
3. Comprobar que arranca en sandbox: `codesign -d --entitlements - "EDF Backups.app"`, y Consola sin denegaciones `Sandbox: deny`.
4. Probar NSOpenPanel + bookmark, notificación, OAuth *loopback* y SMAppService.
5. `productbuild --component … --sign "3rd Party Mac Developer Installer: …"` y validación/subida a TestFlight (Transporter).
6. Repetir con **Briefcase** si py2app da problemas de firma o sandbox.

**Salida**: build de prueba aceptado en TestFlight para macOS. Si no se consigue, reevaluar D2 (Swift).

### Fase 3 — Refactor de producto y sandbox (3–4 semanas)
- Paquete `core/` con backup simple, incremental y actualización in-process. Origen y destino los elige el usuario.
- Retirar del catálogo los scripts específicos de EDF (limpieza de imágenes, cachés, verificación web) y la ejecución de scripts arbitrarios (`/execute`, `/view_script`, Terminal).
- Rutas de datos en el contenedor y migración de datos desde la ubicación antigua en el primer arranque.
- NSOpenPanel en lugar de AppleScript/Finder; UserNotifications en lugar de `osascript`.
- `SMAppService.mainApp` con *toggle* "Abrir al iniciar sesión" en Ajustes. Eliminar el LaunchAgent del producto (puede quedar como herramienta de desarrollo).
- Garantizar que al cerrar la app no queda ningún hilo ni proceso vivo (2.4.5(iii)).
- Restauración desde Drive: la extracción `tar` sigue validando rutas (ya cubierto por tests).
- Adaptar la suite: las rutas temporales del contenedor se simulan con `tmp_path`.

**Salida**: la app funciona completa en sandbox, con cero denegaciones en Consola y la suite verde.

### Fase 4 — UI/UX según HIG macOS (2 semanas)
- Menú de app completo: Acerca de, Ajustes ⌘, Ocultar, Salir, Edición estándar, Ventana y Ayuda con enlace a la política de privacidad.
- Ventana **Settings** (origen/destino, Drive, login item, icono en barra de menús, idioma).
- Menu bar extra **desactivado por defecto**, activable en Ajustes, con icono plantilla monocromo (24 pt de alto de barra).
- Modo claro/oscuro con colores semánticos (CSS `prefers-color-scheme`), sin conmutador propio.
- Accesibilidad: navegación por teclado, foco visible, etiquetas ARIA, contraste ≥ 4,5:1 y VoiceOver probado.
- Localización es/en dentro del bundle.
- Destructivos (borrar o reemplazar backup) con confirmación y Cancelar.
- Revisión de diseño completa con la skill `apple-design` (modo *Code audit* y *Accessibility audit*).

**Salida**: informe `apple-design` sin hallazgos Critical/High.

### Fase 5 — Empaquetado de producción (1 semana)
- Info.plist definitivo (ver §7).
- `PrivacyInfo.xcprivacy` (ver [`drafts/PrivacyInfo.xcprivacy`](drafts/PrivacyInfo.xcprivacy)).
- Icono `.icns` completo (16–1024 px), o *asset catalog* si se usa Xcode.
- Script de build reproducible (`make build-store`): build, firma anidada, verificación (`codesign --verify --deep --strict`), `productbuild` y validación.
- Builds internos en TestFlight; probar en una máquina limpia (otra cuenta de usuario).

**Salida**: un `.pkg` validado sin errores ni avisos ITMS.

### Fase 6 — App Store Connect y envío (1 semana)
- Metadatos: nombre, subtítulo, descripción, palabras clave, URL de soporte, URL de la política de privacidad, categoría (Utilidades) y copyright.
- Capturas Mac: 16:10, a una de las resoluciones aceptadas: 1280×800, 1440×900, 2560×1600 o 2880×1800.
- **Etiquetas de privacidad (App Privacy)**: con Drive, el contenido de usuario lo transmite el propio usuario a su cuenta; declarar según el *data flow* real. Sin analítica ni tracking.
- Cuestionario de clasificación por edades. Cumplimiento de exportación: solo HTTPS estándar → `ITSAppUsesNonExemptEncryption = NO`.
- **Notas para Review**: cómo probar sin MongoDB, que Drive usa la cuenta del revisor y el scope `drive.file`, y la ruta para crear y restaurar un backup en 3 pasos.

**Salida**: envío realizado.

### Fase 7 — Review y post-lanzamiento
- Responder rechazos en el Resolution Center. Registrar cada uno en el seguimiento con la guía citada y la acción tomada.
- Releases siguientes solo por la App Store (2.4.5(vii)).
- v1.1 candidata: MongoDB (conexión de red cliente, URI en el Llavero).

**Duración total orientativa: 10–13 semanas**, condicionada por el gate de la Fase 2.

---

## 7. Configuración objetivo (borrador)

### Info.plist (claves a añadir o ajustar)

| Clave | Valor |
| --- | --- |
| `CFBundleIdentifier` | `com.<dominio-propio>.backups` (D6) |
| `CFBundleShortVersionString` / `CFBundleVersion` | desde `config.APP_VERSION` / número de build incremental |
| `LSApplicationCategoryType` | `public.app-category.utilities` |
| `LSMinimumSystemVersion` | 13.0 o superior (`SMAppService` requiere macOS 13) |
| `ITSAppUsesNonExemptEncryption` | `false` |
| `NSHumanReadableCopyright` | titular real |
| `NSAppTransportSecurity` | quitar `NSAllowsLocalNetworking` cuando desaparezca Flask |
| `NSLocalNetworkUsageDescription` | eliminar (el *loopback* no la requiere) |

### Entitlements y privacy manifest
Ver [`drafts/EDFBackups.entitlements`](drafts/EDFBackups.entitlements) y [`drafts/PrivacyInfo.xcprivacy`](drafts/PrivacyInfo.xcprivacy). Hay que validar ambos en la Fase 2.

---

## 8. Riesgos

| Riesgo | Prob. | Impacto | Mitigación |
| --- | --- | --- | --- |
| py2app no firma o sandboxea bien todos los binarios anidados | Media | Alto | Spike en la Fase 2; alternativa Briefcase; última opción Swift. |
| Review rechaza por funcionalidad mínima o confusa (4.2/2.1) | Media | Alto | Producto genérico claro (D1), notas de revisión y flujo de 3 pasos. |
| Verificación OAuth de Google lenta | Media | Medio | Iniciarla en la Fase 0, en paralelo. |
| Aviso ITMS-91053 por APIs con *required reason* no declaradas | Media | Medio | Privacy manifest desde el primer build de TestFlight; leer el correo de validación. |
| Explotación del servidor local antes del refactor | Baja-media | Alto | Fase 1 inmediata (token + Origin). |
| Pérdida de datos en la migración al contenedor | Baja | Alto | Migración con copia, no movimiento, y test dedicado. |

---

## 9. Skills y herramientas de apoyo

Disponibles en este entorno y aplicables:

| Skill / herramienta | Uso en el plan |
| --- | --- |
| `apple-design` | HIG macOS (menú, Ajustes, menu bar extra, privacidad, accesibilidad, modo oscuro). Revisión de las Fases 4 y 6. |
| `accessibility` | Auditoría WCAG de `templates/index.html`. |
| `xcode-integration:audit-xcode-security-settings` | Si D3 = Briefcase/Xcode: auditoría de los ajustes de seguridad del proyecto Xcode. |
| `xcode-integration:translation` | Localización es/en (String Catalogs) si hay proyecto Xcode. |
| `security-review` | Revisión de la Fase 1 (auth del servidor local, Llavero). |
| MCP `xcode` (BuildProject, GetBuildLog…) | Builds y logs si se adopta el proyecto Xcode. |

No he podido instalar skills externas desde el registro público: el intento de buscar con `npx skills` lo bloqueó la política de permisos. Si quieres añadir alguna concreta (por ejemplo, una de App Store Connect / Fastlane), indícame cuál y la apruebas.
