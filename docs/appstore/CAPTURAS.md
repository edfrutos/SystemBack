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
3. **Pantalla:** en Retina, elige en Ajustes del Sistema › Pantallas la resolución «parece 1440×900». Las capturas a pantalla completa salen entonces a 2880×1800.
4. **Ventana:** tamaño de unos 1280×800 puntos, centrada. Con el panel Actividad abierto donde se indica.
5. **Idioma:** Ajustes de la app › Idioma. Haz el juego es-ES en español y el juego en en inglés, reiniciando la app entre los dos.

## Cómo capturar

- **Pantalla completa** (recomendado): ⇧⌘3. Sale a 2880×1800 directamente con la resolución del punto 3.
- **Solo la ventana**: ⇧⌘4 y luego Espacio, con ⌥ pulsado para quitar la sombra. Después hay que colocarla sobre un lienzo de 2880×1800, porque Apple exige el tamaño exacto.
- Comprueba el tamaño con `sips -g pixelWidth -g pixelHeight captura.png`.

## Capturas propuestas (en este orden)

| # | Pantalla | Qué tiene que verse | Texto superpuesto opcional (es / en) |
| --- | --- | --- | --- |
| 1 | Ventana principal, trabajo «Proyecto Web» seleccionado | Barra lateral con los dos trabajos, las tres tarjetas de acción y la lista de backups con etiquetas Completo, Cambios, Local y Drive | «Tus carpetas, a salvo en .tar.gz» / «Your folders, safe in .tar.gz» |
| 2 | Backup en curso con el panel Actividad abierto | Barra de progreso con la ruta del archivo actual y el registro con líneas en verde | «Progreso y registro de cada operación» / «Progress and a log of every step» |
| 3 | Diálogo «¿Restaurar en la carpeta original?» | El texto que explica que lo sustituido va a la Papelera | «Restaura en su sitio. Lo sustituido va a la Papelera» / «Restore in place. Anything replaced goes to the Trash» |
| 4 | Lista con un backup «solo en Drive» y el puntero sobre «Descargar a este Mac» | Etiqueta Drive sin Local y la ayuda emergente visible | «Copia opcional en tu Google Drive» / «Optional copy in your Google Drive» |
| 5 | Ajustes | Idioma, la sección Google Drive conectada (con una cuenta de demostración, no la personal) y «Abrir al iniciar sesión» | «Sin cuentas propias ni seguimiento» / «No accounts, no tracking» |
| 6 | Hoja «Nuevo trabajo de backup» | Origen y destino elegidos en `~/Demo` | «Elige qué copiar y dónde» / «Choose what to back up, and where» |

Notas:

- **Captura 5:** el correo de Google se ve en pantalla. Usa una cuenta de demostración o tapa el correo con un rectángulo del color del fondo; no lo difumines.
- **Texto superpuesto:** si se añade, va en una franja encima de la captura y en el idioma de la ficha. La parte de la app tiene que seguir viéndose entera y legible.
- **Vídeo de vista previa:** opcional y fuera de la v1.0.

## Comprobación antes de subir

- [ ] Tamaño exacto en las seis capturas (2880×1800).
- [ ] No aparece ninguna ruta, nombre ni correo personal.
- [ ] El juego es-ES está en español y el juego en en inglés, también los menús y las alertas.
- [ ] El icono de la app aparece correctamente en el Dock, si sale.
- [ ] Ninguna captura muestra funciones que no estén en el build que se envía.
