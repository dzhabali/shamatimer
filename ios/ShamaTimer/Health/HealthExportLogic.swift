import Foundation

/// Чистая логика выгрузки Health → Life (без HealthKit, покрыта тестами).
/// Правила свода по дню повторяют tools/health_import.py в life-chronicle.

enum HealthAgg { case sum, mean, last }

struct HealthMetricSpec {
    let key: String
    let agg: HealthAgg
    /// Множитель к значению HealthKit (доли → проценты).
    let multiplier: Double
    /// Знаков после запятой.
    let digits: Int
}

enum HealthMetrics {
    static let all: [HealthMetricSpec] = [
        .init(key: "steps", agg: .sum, multiplier: 1, digits: 0),
        .init(key: "distance", agg: .sum, multiplier: 1, digits: 2),
        .init(key: "flights", agg: .sum, multiplier: 1, digits: 0),
        .init(key: "active", agg: .sum, multiplier: 1, digits: 0),
        .init(key: "basal", agg: .sum, multiplier: 1, digits: 0),
        .init(key: "weight", agg: .last, multiplier: 1, digits: 1),
        .init(key: "fat", agg: .last, multiplier: 100, digits: 1),
        .init(key: "bmi", agg: .last, multiplier: 1, digits: 1),
        .init(key: "lean", agg: .last, multiplier: 1, digits: 1),
        .init(key: "speed", agg: .mean, multiplier: 1, digits: 2),
        .init(key: "steplen", agg: .mean, multiplier: 1, digits: 0),
        .init(key: "support", agg: .mean, multiplier: 100, digits: 1),
        .init(key: "asym", agg: .mean, multiplier: 100, digits: 1),
        .init(key: "steadiness", agg: .last, multiplier: 100, digits: 0),
        .init(key: "headphones", agg: .mean, multiplier: 1, digits: 0),
        .init(key: "resthr", agg: .last, multiplier: 1, digits: 0),
        .init(key: "hrv", agg: .mean, multiplier: 1, digits: 1),
        .init(key: "hr", agg: .mean, multiplier: 1, digits: 0),
        .init(key: "resp", agg: .mean, multiplier: 1, digits: 1),
        .init(key: "vo2", agg: .last, multiplier: 1, digits: 1),
        // особые: считаются из категорий, не из статистики
        .init(key: "sleep", agg: .sum, multiplier: 1, digits: 0),
        .init(key: "mindful", agg: .sum, multiplier: 1, digits: 0),
    ]

    static func spec(_ key: String) -> HealthMetricSpec? { all.first { $0.key == key } }

    /// Сырое значение HealthKit → значение для Life (множитель + округление).
    static func value(_ key: String, raw: Double) -> Double {
        guard let s = spec(key) else { return raw }
        return round(raw * s.multiplier, digits: s.digits)
    }

    static func round(_ v: Double, digits: Int) -> Double {
        let p = pow(10.0, Double(digits))
        return (v * p).rounded() / p
    }
}

struct HealthSample: Codable, Equatable {
    let k: String
    let v: Double
    let d: String

    var ledgerKey: String { k + "|" + d }
}

enum HealthDay {
    /// «YYYY-MM-DD» по календарю (локальному — как в Life).
    static func string(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

enum SleepMath {
    /// Минуты сна по ночам. Ночь — 18:00 предыдущего дня → 18:00 этого дня, день = дата конца ночи.
    /// Учитываются только интервалы сна (не «в кровати»); пересечения разных источников склеиваются.
    static func minutesByNight(_ samples: [(asleep: Bool, interval: DateInterval)],
                               calendar: Calendar) -> [String: Double] {
        let merged = merge(samples.filter(\.asleep).map(\.interval))
        var out: [String: Double] = [:]
        for iv in merged {
            var cursor = iv.start
            while cursor < iv.end {
                let boundary = nextEvening(after: cursor, calendar: calendar)
                let pieceEnd = min(iv.end, boundary)
                let day = HealthDay.string(boundary, calendar: calendar)
                out[day, default: 0] += pieceEnd.timeIntervalSince(cursor) / 60
                cursor = pieceEnd
            }
        }
        return out
    }

    /// Ближайшее 18:00 строго после момента.
    static func nextEvening(after t: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: t)
        if let e = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day), e > t { return e }
        let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: next) ?? next.addingTimeInterval(18 * 3600)
    }

    static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        var out: [DateInterval] = []
        for iv in intervals.sorted(by: { $0.start < $1.start }) where iv.duration > 0 {
            if let last = out.last, iv.start <= last.end {
                out[out.count - 1] = DateInterval(start: last.start, end: max(last.end, iv.end))
            } else {
                out.append(iv)
            }
        }
        return out
    }
}

enum MindfulMath {
    /// Минуты осознанности по дню начала сессии (как в health_import.py).
    static func minutesByDay(_ intervals: [DateInterval], calendar: Calendar) -> [String: Double] {
        var out: [String: Double] = [:]
        for iv in intervals where iv.duration > 0 {
            out[HealthDay.string(iv.start, calendar: calendar), default: 0] += iv.duration / 60
        }
        return out
    }
}

/// Что уже отправлено: «ключ|день» → значение + часовой пояс, в котором день считался.
struct HealthLedger: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let v: Double
        let tz: String
    }

    var sent: [String: Entry] = [:]

    /// Только новые и изменившиеся (ключ, день). День, отправленный в другом поясе (поездка), не
    /// пересылаем — в новом поясе его границы сдвинуты; исключение — `alwaysDays` (сегодня, вчера).
    func changed(_ samples: [HealthSample], timeZone: String, alwaysDays: Set<String> = []) -> [HealthSample] {
        samples.filter { s in
            guard let e = sent[s.ledgerKey] else { return true }
            if e.tz != timeZone && !alwaysDays.contains(s.d) { return false }
            return e.v != s.v
        }
    }

    mutating func record(_ samples: [HealthSample], timeZone: String) {
        for s in samples { sent[s.ledgerKey] = Entry(v: s.v, tz: timeZone) }
    }

    /// Выкинуть записи старше дня `cutoff` («YYYY-MM-DD», строки сравнимы).
    mutating func prune(before cutoff: String) {
        sent = sent.filter { key, _ in
            guard let bar = key.lastIndex(of: "|") else { return false }
            return String(key[key.index(after: bar)...]) >= cutoff
        }
    }
}

enum HealthPush {
    static let maxBatch = 2000

    static func batches<T>(_ items: [T], size: Int = maxBatch) -> [[T]] {
        guard size > 0 else { return [items] }
        return stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
    }

    static func body(_ samples: [HealthSample]) throws -> Data {
        struct Body: Encodable { let samples: [HealthSample] }
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(Body(samples: samples))
    }

    struct Response: Decodable, Equatable {
        let ok: Int
        let skipped: Int?
        let old: Int?
    }

    static func decode(_ data: Data) -> Response? { try? JSONDecoder().decode(Response.self, from: data) }
}
