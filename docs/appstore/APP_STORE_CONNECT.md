# App Store Connect: respuestas para SystemBack

Borrador para rellenar App Store Connect. Supuestos de partida:

- La v1.0 incluye la copia en Google Drive (scope `drive.file`).
- Si Drive se queda fuera de la v1.0, se aplican igual estas respuestas y se borra lo marcado *(Drive)*.

Revisar antes de enviar: quien responde ante Apple es el titular de la cuenta.

## 1. Registro del identificador (developer.apple.com › Identifiers)

| Campo | Valor |
| --- | --- |
| Platform | macOS |
| Description | SystemBack |
| Bundle ID (explicit) | `com.edefrutos.systemback` (ver nota) |
| Capabilities | Ninguna adicional (el sandbox va en el binario, no aquí) |

Nota: el bundle ID no se puede cambiar una vez creada la app en App Store Connect. Tiene que coincidir con:

- el del proyecto (`com.edefrutos.systemback`);
- el del cliente OAuth de Google (tipo iOS).

## 2. Nueva app (App Store Connect › Apps › +)

| Campo | Valor |
| --- | --- |
| Plataforma | macOS |
| Nombre | SystemBack (es-ES). En la localización en: `SystemBack: Folder Backups` («SystemBack» a secas está ocupado en inglés) |
| Idioma principal | Español (España) |
| Bundle ID | `com.edefrutos.systemback` |
| SKU | `systemback-macos` |
| Acceso | Acceso completo |

## 3. Información de la app

| Campo | es-ES | en |
| --- | --- | --- |
| Subtítulo (≤30) | Backups de carpetas en tu Mac | Folder backups for your Mac |
| Categoría principal | Utilidades | Utilities |
| Categoría secundaria | Productividad | Productivity |
| URL de política de privacidad | `https://efjdev.com/privacidad/` | igual |
| Derechos de contenido | No contiene, muestra ni accede a contenido de terceros | |

## 4. Precio y disponibilidad

- Precio: gratis (D5).
- Países: todos.
- Distribución en Mac con Apple silicon (iPad app): no aplica, es una app de Mac.

## 5. Privacidad de la app («etiqueta nutricional»)

**¿Recopilas datos de esta app?** → **No, no recopilamos datos de esta app.**

Justificación según la definición de Apple: «recopilar» es transmitir datos fuera del dispositivo de forma que el desarrollador o sus socios puedan acceder a ellos más allá de atender la petición en tiempo real.

- SystemBack no tiene servidor, ni analítica, ni SDK de terceros, ni publicidad.
- Los backups se escriben en carpetas que elige el usuario.
- *(Drive)* La copia en Google Drive la ordena el usuario y va directamente de su Mac a **su propia** cuenta de Drive. El desarrollador no recibe ni puede ver nada.
- El token de Google se guarda en el Llavero del Mac.

Es la misma respuesta que corresponde a Gestor de Correos Gmail (mismo patrón OAuth y procesamiento local). Si allí se declaró otra cosa, conviene que las dos apps coincidan.

## 6. Clasificación por edades (cuestionario)

Responder **No / Ninguno** a todo:

- **Funciones de la app:**
  - controles parentales;
  - verificación de edad;
  - contenido generado por usuarios;
  - mensajería o chat;
  - publicidad;
  - acceso web sin restricciones (el inicio de sesión de Google usa `ASWebAuthenticationSession` solo para OAuth, no es un navegador);
  - juegos de azar;
  - concursos.
- **Contenido:**
  - violencia (dibujos, realista o prolongada);
  - terror;
  - temas para adultos o sugerentes;
  - sexualidad y desnudos;
  - lenguaje soez;
  - alcohol, tabaco y drogas;
  - información médica o de bienestar;
  - armas.

Resultado esperado: **4+**.

## 7. Cumplimiento de exportación (cifrado)

`ITSAppUsesNonExemptEncryption = NO` ya está en el Info.plist. Por eso App Store Connect no pregunta nada al subir el build. El motivo: la app solo usa el cifrado del sistema (HTTPS con `URLSession`, Llavero), que está exento.

## 8. Información para la revisión (App Review)

- **Inicio de sesión necesario:** No. *(Drive)* Google es opcional y solo conecta el servicio de almacenamiento.
- **Contacto:** nombre, teléfono y correo del titular, que se rellenan a mano.
- **Notas para el revisor** (en inglés, que es lo que lee el revisor):

```
SystemBack backs up a folder the user chooses into another folder the user chooses, as a standard
.tar.gz archive, and restores it (into a new folder, or into the original folder; replaced files
go to the Trash first).

How to test:
1. Click "+" and choose any folder with a few files as Source, and any empty folder as Destination.
2. Click "Back Up Now". The archive appears under "Backups".
3. Use the row buttons to restore into a new folder or into the original folder.

The app is sandboxed and only accesses folders chosen through the Open panel (security-scoped
bookmarks). It has no account, no server, no analytics and no ads.
"Open at Login" is off by default and only enabled by the user in Settings (SMAppService).

(Drive) Google Drive upload is optional. Google sign-in is used only to connect the user's own
Drive storage (scope drive.file: the app can only see files it created). It is not an app account,
so Sign in with Apple (guideline 4.8) does not apply. You can test it with any Google account.
```

## 9. Textos de la ficha

### Texto promocional (≤170, editable sin revisión)

- es: `Copia tus carpetas en archivos .tar.gz estándar y restáuralas cuando quieras: en una carpeta nueva o en su sitio original. Sin cuentas, sin seguimiento.`
- en: `Back up your folders into standard .tar.gz archives and restore them whenever you need: into a new folder or right where they were. No accounts, no tracking.`

### Descripción (es)

```
SystemBack hace copias de seguridad de las carpetas que eliges, en archivos .tar.gz estándar que
se pueden abrir en cualquier Mac, Linux o Windows.

QUÉ PUEDES HACER
• Backup completo de una carpeta con un clic (⌘B).
• Actualizar el último backup: crea uno nuevo y manda el anterior a la Papelera.
• Copiar solo los cambios desde el último backup.
• Restaurar en una carpeta nueva, sin tocar nada de lo que ya tienes.
• Restaurar en la carpeta original: recupera lo borrado o modificado; lo que se sustituye va
  primero a la Papelera, así que siempre puedes deshacer.
• Ver tus backups, su tipo, fecha y tamaño, y abrirlos en el Finder.
• Panel de actividad con el progreso y el registro de cada operación.

PRIVACIDAD
Todo ocurre en tu Mac. Sin cuentas, sin servidores, sin publicidad y sin analítica. La app solo
accede a las carpetas que tú eliges.

FORMATO ABIERTO
Tus backups no dependen de SystemBack: son archivos .tar.gz normales.
```

### Description (en)

```
SystemBack backs up the folders you choose into standard .tar.gz archives that open on any Mac,
Linux or Windows computer.

WHAT YOU CAN DO
• Full backup of a folder in one click (⌘B).
• Replace the last backup: create a new one and move the previous one to the Trash.
• Back up only what changed since the last backup.
• Restore into a new folder, leaving everything you have untouched.
• Restore into the original folder: bring back deleted or changed files; anything replaced goes
  to the Trash first, so you can always undo.
• See your backups with type, date and size, and show them in Finder.
• Activity panel with progress and a log of every operation.

PRIVACY
Everything happens on your Mac. No accounts, no servers, no ads, no analytics. The app only
accesses the folders you choose.

OPEN FORMAT
Your backups don't depend on SystemBack: they're plain .tar.gz files.
```

*(Drive)* Cuando exista, añadir a «Qué puedes hacer»: `• Guardar una copia en tu Google Drive (opcional).` y a privacidad `La copia en Google Drive va directamente de tu Mac a tu cuenta.`

### Palabras clave (≤100, sin marcas de terceros: guía 2.3.7)

- es (96): `backup,copia de seguridad,respaldo,restaurar,tar.gz,incremental,carpetas,archivos,disco,papelera`
- en (≤100): `backup,restore,archive,tar.gz,incremental,folder,files,copy,safe,versions,disk,recovery`

### URLs

| Campo | URL |
| --- | --- |
| Soporte | `https://efjdev.com/soporte/` |
| Marketing | `https://efjdev.com/systemback/` |
| Copyright | `2026 Eugenio de Frutos Sánchez` |

### Capturas (Mac)

Lista, preparación y requisitos en [`CAPTURAS.md`](CAPTURAS.md): seis capturas a 2880×1800, con datos de demostración.

## 10. Comprobación de guías antes de enviar

| Guía | Estado |
| --- | --- |
| 2.4.5(i) sandbox, solo herramientas de Xcode | Sí |
| 2.4.5(iii) no arranca al iniciar sesión sin consentimiento | Sí (toggle en Ajustes, desactivado por defecto) |
| 2.4.5(iv) sin instaladores ni autoactualización propia | Sí |
| 2.3.7 metadatos sin marcas ajenas | Sí (sin «Google Drive» en palabras clave) |
| 4.8 Iniciar sesión con Apple | No aplica (Google no es la cuenta de la app) |
| 5.1.1(i) enlace a privacidad en la app y en la ficha | Sí (menú Ayuda) |
| 5.1.2 uso de datos | Sin recopilación |
| Manifiesto de privacidad | Incluido. Pendiente: confirmar los motivos de FileTimestamp en la primera validación |
| Nombre «SystemBack» | Hay una herramienta Linux «Systemback» (riesgo aceptado en D6) |
