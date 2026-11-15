# SystemBack

App nativa de macOS para hacer backup de las carpetas que elijas y restaurarlas. Próximamente en la Mac App Store. Más información: [efjdev.com/systemback](https://efjdev.com/systemback/).

- Swift 6 · SwiftUI · macOS 14 o posterior · App Sandbox.
- Backups completos, de solo cambios o sustituyendo el último, en formato `.tar.gz` estándar: se abren con `tar` en cualquier sistema.
- Restauración a una carpeta nueva o en la carpeta original (lo sustituido va a la Papelera), siempre con validación de rutas.
- Copia opcional en tu propio Google Drive (permiso `drive.file`: la app solo ve los archivos que crea). El token se guarda en el Llavero.
- Sin cuentas propias, sin servidores y sin seguimiento.
- Interfaz en español e inglés.

## Requisitos

- Xcode 27 o posterior.

## Desarrollo

```bash
cd Packages/SystemBackCore && swift test          # núcleo
open SystemBack.xcodeproj                          # app
```

Estado del proyecto y decisiones: [`docs/appstore/SEGUIMIENTO_APP_STORE.md`](docs/appstore/SEGUIMIENTO_APP_STORE.md).

## Licencia

Código publicado solo para consulta. Todos los derechos reservados: ver [`LICENSE`](LICENSE).
