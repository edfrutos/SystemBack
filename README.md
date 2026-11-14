# SystemBack

App nativa de macOS para hacer backup de las carpetas que elijas y restaurarlas. Destinada a la Mac App Store.

- Swift 6 · SwiftUI · macOS 14 o posterior · App Sandbox
- Backups `.tar.gz` estándar: se abren con `tar` en cualquier sistema.
- Restauración siempre a una carpeta nueva, con validación de rutas.

## Requisitos

- Xcode 27 o posterior.

## Desarrollo

```bash
cd Packages/SystemBackCore && swift test          # núcleo
open SystemBack.xcodeproj                          # app
```

Estado del proyecto y decisiones: [`docs/appstore/SEGUIMIENTO_APP_STORE.md`](docs/appstore/SEGUIMIENTO_APP_STORE.md).
