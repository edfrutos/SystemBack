# Revisión de diseño (HIG), 2026-11-15

Revisión de SystemBack sobre el código (SwiftUI, macOS 14+) y las capturas de la prueba con Drive. Las citas son de las HIG de Apple (copia local en el skill apple-design).

## Resumen

Valoración: **Buena**. Es una utilidad discreta: controles del sistema, colores semánticos con significado fijo (verde = completo, naranja = actualizar, morado = cambios) y siempre con icono y texto. Ese tono sobrio es el adecuado. Lo más reconocible es el icono, un panel retro de madera con un disco y una flecha de restaurar.

## Corregido en esta revisión

| Severidad | Problema | Guía | Cambio |
| --- | --- | --- | --- |
| Alta | Las órdenes de la barra de herramientas y de las tarjetas no estaban en la barra de menús | `toolbars.md › macOS`: «Make every toolbar item available as a command in the menu bar» | `AppCommands.swift`: Archivo › Nuevo trabajo de backup… (⌘N) y Restaurar desde archivo… (⌘O); menú Backup con Hacer backup ahora (⌘B), Actualizar backup (⌥⌘B), Copiar solo cambios (⇧⌘B) y Actualizar lista (⌘R); Visualización › Mostrar/Ocultar actividad (⌥⌘I) con el título según el estado |
| Alta | Una alerta «No se ha podido leer Google Drive» saltaba al seleccionar un trabajo, sin que el usuario hubiera pedido nada | `alerts.md › Best practices`: «Avoid using an alert merely to provide information» | El fallo de las lecturas automáticas se muestra dentro de la lista de backups con el botón «Reintentar». Solo se usa alerta para acciones que pide el usuario o si Google retira el acceso |
| Crítica (accesibilidad) | El texto de las etiquetas, de tamaño pequeño, iba en verde, azul o morado sobre su propio tinte. El contraste quedaba por debajo de 4,5:1; es una estimación, porque los valores del sistema cambian según el aspecto | `color.md` y `accessibility.md`: 4,5:1 para texto de hasta 17 pt | El texto pasa al color principal; el color queda en el icono y el fondo |
| Baja | Aviso de SwiftUI por `onChange` sobre un `UUID?` en el panel Actividad | — | Se observa `log.count` |

## Pendiente (no bloquea el envío)

| Severidad | Problema | Guía | Propuesta |
| --- | --- | --- | --- |
| Media | El icono es una ilustración casi fotográfica con mucho detalle (relojes, interruptores); a 16 y 32 px se convierte en una mancha | `app-icons.md › Design`: «Embrace simplicity… details may be hard to discern at smaller sizes» | Para la v1.1, una versión simplificada (marco rojo, madera, disco y flecha) hecha por capas en Icon Composer, con variantes oscura y tintada |
| Media | El icono es una imagen plana, no por capas: no recibe los reflejos de Liquid Glass ni tiene variantes oscura o transparente propias (el sistema las genera) | `app-icons.md › Layer design` | Igual que la anterior |
| Baja | El aviso «Sin cambios» tras «Copiar solo cambios» es una alerta informativa | `alerts.md` | Se mantiene porque es respuesta a una acción del usuario y el panel Actividad puede estar cerrado. Más adelante, un estado dentro de la tarjeta |
| Baja | Los botones de las filas tienen el tamaño mínimo (unos 20 pt) y están muy juntos | `layout.md`: en escritorio, mínimo 20×20 pt | Funciona y tiene ayuda emergente; vigilar en la prueba con usuarios |

## Lo que funciona y hay que conservar

- Las acciones de cada fila están visibles y también en el menú contextual, todas con ayuda emergente.
- **Color con significado fijo**, nunca solo: siempre va con icono y texto.
- **Mensajes de error accionables:** dicen qué pasó y qué hacer, sin disculparse.
- **Restaurar en la carpeta original** con una confirmación que explica el efecto. Lo sustituido va a la Papelera, así que se puede deshacer.
- **Aspecto y textos:** claro y oscuro con colores del sistema. Ajustes en el menú de la app (⌘,).

## Decisiones que se apartan de las HIG

- **Selector de aspecto en Ajustes** (Automático, Claro, Oscuro), añadido el 2026-11-16 a petición del usuario. `dark-mode.md › Best practices`: «Avoid offering an app-specific appearance setting». Se mitiga así: el valor por defecto es «Automático», que sigue al sistema (también el cambio de día y noche), y el cambio se aplica al momento sin reiniciar. No es motivo de rechazo en la revisión de la App Store.
- **Icono:** la versión sin texto, porque las HIG piden texto solo si es esencial. Se entrega cuadrado y sin máscara, y el sistema aplica las esquinas: `app-icons.md › Icon shape`.
