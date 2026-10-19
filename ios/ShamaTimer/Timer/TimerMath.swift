import Foundation

/// Состояние активной сессии. Время считается от дат (старт + накопленная пауза), не тиками.
struct ActiveTimer: Codable, Equatable {
    enum Mode: String, Codable { case stopwatch, countdown }

    var mode: Mode
    var start: Date
    /// Запланировано секунд (только countdown, иначе 0).
    var plannedSec: Int
    var pausedAt: Date?
    var pausedAccum: TimeInterval = 0

    var isPaused: Bool { pausedAt != nil }
    var isRunning: Bool { pausedAt == nil }

    func elapsed(at now: Date) -> TimeInterval {
        let pausedNow = pausedAt.map { now.timeIntervalSince($0) } ?? 0
        return max(0, now.timeIntervalSince(start) - pausedAccum - pausedNow)
    }

    func elapsedSec(at now: Date) -> Int { Int(elapsed(at: now).rounded(.down)) }

    /// Сколько осталось (countdown), с дробной частью.
    func remaining(at now: Date) -> TimeInterval { max(0, TimeInterval(plannedSec) - elapsed(at: now)) }

    func secondsLeft(at now: Date) -> Int { max(0, plannedSec - elapsedSec(at: now)) }

    /// Когда countdown закончится, если не ставить на паузу.
    var expectedEnd: Date? {
        guard mode == .countdown, pausedAt == nil else { return nil }
        return start.addingTimeInterval(TimeInterval(plannedSec) + pausedAccum)
    }

    func isExpired(at now: Date) -> Bool {
        mode == .countdown && isRunning && elapsed(at: now) >= TimeInterval(plannedSec)
    }

    mutating func pause(at now: Date) {
        guard pausedAt == nil else { return }
        pausedAt = now
    }

    mutating func resume(at now: Date) {
        guard let p = pausedAt else { return }
        pausedAccum += max(0, now.timeIntervalSince(p))
        pausedAt = nil
    }

    /// Итог сессии. nil — если вышло ≤ 3 с (не сохраняем, как в вебе).
    /// Истёкший countdown фиксируется ровно на плановой длительности, конец = старт + план + паузы
    /// (важно, если приложение было убито и восстановлено позже).
    func finish(at now: Date) -> FinishedSession? {
        if mode == .countdown, isExpired(at: now), let end = expectedEnd {
            return FinishedSession(start: start, end: end, durationSec: plannedSec,
                                   plannedSec: plannedSec, complete: true, mode: mode.rawValue)
        }
        let el = elapsedSec(at: now)
        guard el > 3 else { return nil }
        switch mode {
        case .stopwatch:
            return FinishedSession(start: start, end: now, durationSec: el,
                                   plannedSec: nil, complete: true, mode: mode.rawValue)
        case .countdown:
            return FinishedSession(start: start, end: now, durationSec: el,
                                   plannedSec: plannedSec, complete: el >= plannedSec, mode: mode.rawValue)
        }
    }
}

struct FinishedSession: Equatable {
    let start: Date
    let end: Date
    let durationSec: Int
    let plannedSec: Int?
    let complete: Bool
    let mode: String
}

enum TimeFormat {
    /// countdown: `05:07`
    static func countdown(_ sec: Int) -> String {
        String(format: "%02d:%02d", sec / 60, sec % 60)
    }
    /// stopwatch: `5:07`
    static func countUp(_ sec: Int) -> String {
        String(format: "%d:%02d", sec / 60, sec % 60)
    }
}
