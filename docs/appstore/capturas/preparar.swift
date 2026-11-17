// Prepara capturas para App Store Connect: 2880×1800, RGB, sin canal alfa.
//
//   swift preparar.swift <entrada.png> <salida.png> [x,y,ancho,alto ...]
//
// - La imagen se dibuja centrada sobre un lienzo de 2880×1800 con el color de su píxel (2,2)
//   (las esquinas redondeadas de la ventana quedan rellenas con ese color).
// - Cada rectángulo opcional (en píxeles de la entrada, origen arriba a la izquierda) se tapa
//   con el color del píxel justo a su izquierda: sirve para ocultar datos personales.
import AppKit

let args = CommandLine.arguments
guard args.count >= 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("uso: swift preparar.swift entrada.png salida.png [x,y,w,h ...]\n".utf8))
    exit(1)
}

let width = 2880, height = 1800
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
let rep = NSBitmapImageRep(cgImage: image)

/// Color de un píxel de la entrada (origen arriba a la izquierda), opaco.
func color(atX x: Int, y: Int) -> CGColor {
    let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) ?? .white
    return CGColor(srgbRed: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: 1)
}

guard image.width <= width, image.height <= height,
      let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: rgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    FileHandle.standardError.write(Data("la imagen supera 2880×1800\n".utf8))
    exit(1)
}

// Fondo: un píxel interior cerca de la esquina superior izquierda, dentro de la ventana.
context.setFillColor(color(atX: min(40, image.width - 1), y: min(image.height / 2, image.height - 1)))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
let originX = (width - image.width) / 2
let originY = (height - image.height) / 2
context.draw(image, in: CGRect(x: originX, y: originY, width: image.width, height: image.height))

// Rectángulos a tapar (coordenadas de la entrada, origen arriba a la izquierda).
for spec in args.dropFirst(3) {
    let n = spec.split(separator: ",").compactMap { Int($0) }
    guard n.count == 4 else { continue }
    let (x, y, w, h) = (n[0], n[1], n[2], n[3])
    context.setFillColor(color(atX: max(x - 4, 0), y: y + h / 2))
    // CGContext tiene el origen abajo a la izquierda.
    context.fill(CGRect(x: originX + x, y: originY + image.height - y - h, width: w, height: h))
}

guard let output = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL,
                                                        "public.png" as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(destination, output, nil)
exit(CGImageDestinationFinalize(destination) ? 0 : 1)
