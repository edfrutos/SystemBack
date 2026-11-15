import SwiftUI
import SystemBackCore

/// Identidad visual heredada de la app original (verde = completo, naranja = actualizar,
/// morado = incremental), con colores del sistema: se adaptan a claro/oscuro y alto contraste.
/// Un color significa siempre lo mismo y nunca va solo: lleva icono y texto (HIG `color.md`).
enum Theme {
    static let full = Color.green
    static let replace = Color.orange
    static let incremental = Color.purple
    static let restore = Color.teal

    static func tint(for kind: ArchiveInfo.Kind) -> Color {
        switch kind {
        case .full: full
        case .incremental: incremental
        case .other: .secondary
        }
    }

    static func symbol(for kind: ArchiveInfo.Kind) -> String {
        switch kind {
        case .full: "externaldrive.fill"
        case .incremental: "plus.square.on.square"
        case .other: "doc.zipper"
        }
    }

    /// Texto al pasar el puntero por la etiqueta de tipo.
    static func help(for kind: ArchiveInfo.Kind) -> LocalizedStringKey {
        switch kind {
        case .full: "Full backup: a complete copy of the folder"
        case .incremental: "Changes only: files modified since the previous backup"
        case .other: "A .tar.gz file whose name SystemBack doesn’t recognize"
        }
    }

    static func label(for kind: ArchiveInfo.Kind) -> LocalizedStringKey {
        switch kind {
        case .full: "Full"
        case .incremental: "Changes"
        case .other: "Other"
        }
    }
}

/// Etiqueta tipo cápsula: icono + texto + color (como los badges de la app original).
/// El color va en el icono y el fondo; el texto usa el color principal para cumplir 4,5:1
/// (verde o azul del sistema sobre su propio tinte no llega en texto pequeño).
struct Badge: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(.primary)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(tint.opacity(0.14), in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// Tarjeta de acción (equivalente a los botones por categoría de la app original).
struct ActionCard: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    let tint: Color
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(12)
            .background(tint.opacity(isHovered && isEnabled ? 0.16 : 0.09), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.35))
            }
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
