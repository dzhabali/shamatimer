import Foundation

/// Даты в формате сервера/веба. Чистый Foundation — собирается и на macOS.
enum ShamaDate {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let secondsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    /// Устойчивый разбор ISO-строки: дробная часть любой длины (обрезается/дополняется до 3 знаков),
    /// без дробной части, без зоны (считается UTC).
    static func parse(_ raw: String) -> Date? {
        var s = normalizeFraction(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if !hasTimeZone(s) { s += "Z" }
        if let d = fractional.date(from: s) { return d }
        if let d = plain.date(from: s) { return d }
        return nil
    }

    /// `2026-10-16T05:38:54.727654Z` → `2026-10-16T05:38:54.727Z`; `.5Z` → `.500Z`.
    static func normalizeFraction(_ s: String) -> String {
        guard let t = s.firstIndex(of: "T"),
              let dot = s[t...].firstIndex(of: ".") else { return s }
        var i = s.index(after: dot)
        var digits = ""
        while i < s.endIndex, s[i].isASCII, s[i].isNumber {
            digits.append(s[i])
            i = s.index(after: i)
        }
        if digits.isEmpty { return String(s[..<dot]) + String(s[i...]) }
        var three = String(digits.prefix(3))
        while three.count < 3 { three += "0" }
        return String(s[..<dot]) + "." + three + String(s[i...])
    }

    private static func hasTimeZone(_ s: String) -> Bool {
        guard let t = s.firstIndex(of: "T") else { return true }
        let time = s[s.index(after: t)...]
        return time.contains("Z") || time.contains("z") || time.contains("+") || time.contains("-")
    }

    /// Как JS `toISOString()`: `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`, UTC, миллисекунды без дрейфа double.
    static func format(_ date: Date) -> String {
        let ms = Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
        let secs = ms >= 0 ? ms / 1000 : (ms - 999) / 1000
        let frac = Int(ms - secs * 1000)
        let base = secondsFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(secs)))
        return base + "." + String(format: "%03d", frac) + "Z"
    }

    /// Миллисекунды Unix (как `Date.now()` в JS).
    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }

    static func fromMilliseconds(_ ms: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }
}
