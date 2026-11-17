import Foundation

/// «Último backup hace…» para la barra lateral y la cabecera del trabajo.
///
/// Las dos vistas lo calculan con la fecha de un `TimelineView(.everyMinute)`, que se actualiza
/// al empezar cada minuto: así muestran siempre el mismo texto y no se quedan congeladas.
/// Por debajo de un minuto se dice «hace un momento», porque los segundos no se refrescan.
enum LastBackupText {
    static func string(for date: Date?, now: Date) -> String {
        guard let date else { return String(localized: "Never backed up") }
        if now.timeIntervalSince(date) < 60 { return String(localized: "Last backup just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: date, relativeTo: now)
        return String(localized: "Last backup \(relative)")
    }
}
