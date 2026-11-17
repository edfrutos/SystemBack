# Capturas para la ficha de la Mac App Store

## Requisitos de Apple (Mac)

- Formato 16:10. Tamaños válidos: 1280×800, 1440×900, 2560×1600 o 2880×1800 px.
- Entre 1 y 10 capturas por idioma. Las tres primeras son las que se ven sin desplegar la ficha.
- PNG o JPEG, en RGB y sin transparencia.
- Tienen que mostrar la app real. No vale una maqueta, ni marcos de dispositivo con contenido inventado.
- Si una captura enseña Google Drive, no se puede usar el logotipo de Google como reclamo (guía 2.3.7). Que aparezca el nombre dentro de la app es correcto.

## Preparación

1. **Datos de demostración**, sin rutas ni nombres personales:
   - Crea `~/Demo/Proyecto Web` con unas 30 carpetas y archivos variados, y `~/Demo/Fotos 2026` con imágenes.
   - Crea el destino `~/Demo/Backups`.
   - En la app, crea los trabajos «Proyecto Web» y «Fotos 2026».
   - Haz dos backups completos y uno de cambios en «Proyecto Web», con un día de diferencia si es posible. Así la lista tiene fechas distintas.
   - Con Drive conectado, sube uno de esos backups. Manda otro a la Papelera del Mac para que en la lista quede uno «solo en Drive».
   - Las rutas visibles tienen que ser las de `~/Demo`, nunca carpetas de trabajo reales.
2. **Sistema:**
   - Aspecto claro para el juego principal. Opcionalmente, un segundo juego en oscuro.
   - Fondo de escritorio neutro y Dock oculto.
   - Barra de menús sin extras de terceros.
   - No molestar activado, para que no salgan notificaciones.
3. **Pantalla:** el método de pantalla completa solo sirve en pantallas 16:10 con la resolución «parece 1440×900». En una pantalla 16:9 (como la 5K de Studio Display) se captura solo la ventana: ver el punto 4.
4. **Ventana:** exactamente 1440×900 puntos, que en Retina dan 2880×1800 px. Con el panel Actividad abierto donde se indica. Para fijar el tamaño (requiere permiso de Accesibilidad para Terminal):

   ```bash
   osascript -e 'tell application "System Events" to tell process "SystemBack"
   set position of window 1 to {200, 100}
   set size of window 1 to {1440, 900}
   end tell'
   ```
5. **Idioma:** Ajustes de la app › Idioma. Haz el juego es-ES en español y el juego en en inglés, reiniciando la app entre los dos.

## Cómo capturar

- **Solo la ventana** (recomendado): ⇧⌘4, luego Espacio, y clic en la ventana con ⌥ pulsado para quitar la sombra. Con la ventana a 1440×900 pt sale a 2880×1800 directamente.
- **Pantalla completa**: ⇧⌘3, solo en pantallas 16:10 con la resolución del punto 3.
- Los diálogos y hojas salen dentro de la ventana: captura la ventana, no el diálogo suelto.
- Comprueba el tamaño con `sips -g pixelWidth -g pixelHeight captura.png`.

## Capturas propuestas (en este orden)

Archivos finales en `capturas/es/` y `capturas/en/`, con el mismo número en los dos idiomas.

| # | Archivo (es / en) | Pantalla | Qué tiene que verse | Texto superpuesto opcional (es / en) |
| --- | --- | --- | --- | --- |
| 1 | `appstore-01-principal` / `appstore-01-main` | Ventana principal, «Proyecto Web» seleccionado | Barra lateral con los dos trabajos, las tres tarjetas de acción y la lista de backups con etiquetas Completo, Cambios y Local | «Tus carpetas, a salvo en .tar.gz» / «Your folders, safe in .tar.gz» |
| 2 | `appstore-02-backup-en-curso` / `appstore-02-backup-in-progress` | Backup en curso con el panel Actividad abierto | Barra de progreso con la ruta del archivo actual | «Progreso y registro de cada operación» / «Progress and a log of every step» |
| 3 | `appstore-03-google-drive` | Subida a Google Drive en curso | Barra «Subiendo … a Google Drive» y botón Subir en las filas | «Copia opcional en tu Google Drive» / «Optional copy in your Google Drive» |
| 4 | `appstore-04-restaurar-en-origen` / `appstore-04-restore-in-place` | Diálogo «¿Restaurar en la carpeta original?» | El texto que explica que lo sustituido va a la Papelera | «Restaura en su sitio. Lo sustituido va a la Papelera» / «Restore in place. Anything replaced goes to the Trash» |
| 5 | `appstore-05-nuevo-trabajo` / `appstore-05-new-job` | Hoja «Nuevo trabajo de backup» | Origen y destino elegidos en `~/Demo` | «Elige qué copiar y dónde» / «Choose what to back up, and where» |
| 6 | `appstore-06-ajustes` / `appstore-06-settings` | Ajustes | Idioma, Aspecto, Google Drive (desconectado: no se ve ningún correo) y «Abrir al iniciar sesión» | «Sin cuentas propias ni seguimiento» / «No accounts, no tracking» |

Notas:

- **Captura 6:** si Drive está conectado se ve el correo de Google. Captúrala desconectada, con una cuenta de demostración o con el correo tapado por un rectángulo del color del fondo; no lo difumines.
- **Antes de capturar:** oculta la Terminal y Finder (⌥⌘H desde SystemBack) y deja SystemBack en primer plano. Si no, salen el usuario y los discos, y los botones por defecto pierden el azul.
- **Texto superpuesto:** si se añade, va en una franja encima de la captura y en el idioma de la ficha. La parte de la app tiene que seguir viéndose entera y legible.
- **Vídeo de vista previa:** opcional y fuera de la v1.0.

## Comprobación antes de subir

- [ ] Tamaño exacto en las seis capturas (2880×1800).
- [ ] No aparece ninguna ruta, nombre ni correo personal.
- [ ] El juego es-ES está en español y el juego en en inglés, también los menús y las alertas.
- [ ] El icono de la app aparece correctamente en el Dock, si sale.
- [ ] Ninguna captura muestra funciones que no estén en el build que se envía.
