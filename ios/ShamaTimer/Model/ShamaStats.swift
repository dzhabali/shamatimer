import Foundation

/// Локальный календарный день (по `Calendar.current` устройства, не UTC).
struct DayKey: Hashable, Comparable {
    let year: Int, month: Int, day: Int

    init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }

    init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
    }

    static func < (a: DayKey, b: DayKey) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

enum ShamaStats {
    /// Суммарные секунды по локальным дням начала сессии (сессии с durationSec 0 пропускаются, как в вебе).
    static func secondsByDay(_ items: [(date: Date, durationSec: Int)], calendar: Calendar) -> [DayKey: Int] {
        var out: [DayKey: Int] = [:]
        for it in items where it.durationSec > 0 {
            out[DayKey(it.date, calendar: calendar), default: 0] += it.durationSec
        }
        return out
    }

    /// Дни подряд, начиная с сегодня (если сегодня пусто — 0), как calcStreak в вебе.
    static func streak(dates: [Date], today: Date, calendar: Calendar) -> Int {
        let days = Set(dates.map { DayKey($0, calendar: calendar) })
        var n = 0
        var cursor = today
        for _ in 0..<365 {
            guard days.contains(DayKey(cursor, calendar: calendar)) else { break }
            n += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return n
    }

    static func minutes(_ seconds: Int) -> Int { Int((Double(seconds) / 60).rounded()) }

    /// Уровень заливки ячейки календаря 0…5.
    static func level(minutes: Int) -> Int {
        if minutes <= 0 { return 0 }
        if minutes <= 20 { return 1 }
        if minutes <= 40 { return 2 }
        if minutes <= 59 { return 3 }
        if minutes <= 90 { return 4 }
        return 5
    }

    static let levelAlpha: [Double] = [0, 0.10, 0.22, 0.38, 0.58, 0.85]

    /// «12 min» / «2 h 5 min» — карточка Total time.
    static func totalTime(seconds: Int) -> (value: String, unit: String) {
        let m = minutes(seconds)
        if m < 60 { return ("\(m)", " min") }
        return ("\(m / 60)", " h \(m % 60) min")
    }

    struct Cell: Equatable {
        let day: Int
        let minutes: Int
        let level: Int
        let isToday: Bool
    }

    struct Week: Equatable {
        /// 7 позиций Пн…Вс, nil — пустая ячейка вне месяца.
        let cells: [Cell?]
        /// Среднее по активным дням недели (0 — нет данных).
        let average: Int
    }

    struct MonthGrid: Equatable {
        let weeks: [Week]
        /// Среднее по активным дням месяца (0 — нет данных).
        let average: Int
    }

    static func monthGrid(year: Int, month: Int, byDay: [DayKey: Int], today: Date, calendar: Calendar) -> MonthGrid {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = 1
        guard let first = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: first) else {
            return MonthGrid(weeks: [], average: 0)
        }
        let weekday = calendar.component(.weekday, from: first) // 1 = Sun
        let startDow = (weekday + 5) % 7                         // Mon = 0 … Sun = 6
        let todayKey = DayKey(today, calendar: calendar)

        var slots: [Cell?] = Array(repeating: nil, count: startDow)
        var sum = 0, active = 0
        for d in range {
            let key = DayKey(year: year, month: month, day: d)
            let m = minutes(byDay[key] ?? 0)
            if m > 0 { sum += m; active += 1 }
            slots.append(Cell(day: d, minutes: m, level: level(minutes: m), isToday: key == todayKey))
        }
        while slots.count % 7 != 0 { slots.append(nil) }

        var weeks: [Week] = []
        for w in stride(from: 0, to: slots.count, by: 7) {
            let cells = Array(slots[w..<w + 7])
            let mins = cells.compactMap { $0?.minutes }.filter { $0 > 0 }
            let avg = mins.isEmpty ? 0 : Int((Double(mins.reduce(0, +)) / Double(mins.count)).rounded())
            weeks.append(Week(cells: cells, average: avg))
        }
        let avg = active == 0 ? 0 : Int((Double(sum) / Double(active)).rounded())
        return MonthGrid(weeks: weeks, average: avg)
    }
}
