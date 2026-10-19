import Foundation
import XCTest
@testable import ShamaTimer

final class TimerMathTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testElapsedWithPauses() {
        var a = ActiveTimer(mode: .countdown, start: t0, plannedSec: 600, pausedAt: nil)
        XCTAssertEqual(a.elapsedSec(at: at(100)), 100)
        a.pause(at: at(100))
        XCTAssertEqual(a.elapsedSec(at: at(400)), 100, "на паузе время стоит")
        XCTAssertNil(a.expectedEnd)
        a.resume(at: at(400))
        XCTAssertEqual(a.secondsLeft(at: at(500)), 400)
        XCTAssertEqual(a.expectedEnd, at(900))
        XCTAssertFalse(a.isExpired(at: at(899)))
        XCTAssertTrue(a.isExpired(at: at(900)))
    }

    func testCountdownFinish() {
        var a = ActiveTimer(mode: .countdown, start: t0, plannedSec: 600, pausedAt: nil)
        a.pause(at: at(100)); a.resume(at: at(400))
        let partial = a.finish(at: at(500))!
        XCTAssertFalse(partial.complete)
        XCTAssertEqual(partial.durationSec, 200)
        XCTAssertEqual(partial.plannedSec, 600)

        // приложение убили, восстановили через час — сессия complete, конец = старт + план + паузы
        let late = a.finish(at: at(5_000))!
        XCTAssertTrue(late.complete)
        XCTAssertEqual(late.durationSec, 600)
        XCTAssertEqual(late.end, at(900))
        XCTAssertEqual(late.start, t0)
    }

    func testStopwatchFinish() {
        let s = ActiveTimer(mode: .stopwatch, start: t0, plannedSec: 0, pausedAt: nil)
        XCTAssertNil(s.finish(at: at(3)), "≤ 3 с не сохраняем")
        let f = s.finish(at: at(65))!
        XCTAssertTrue(f.complete)
        XCTAssertNil(f.plannedSec)
        XCTAssertEqual(f.mode, "stopwatch")
        XCTAssertFalse(s.isExpired(at: at(99_999)))
    }

    func testPersistenceRoundTrip() throws {
        var a = ActiveTimer(mode: .countdown, start: t0, plannedSec: 1800, pausedAt: nil)
        a.pause(at: at(10))
        let back = try JSONDecoder().decode(ActiveTimer.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(back, a)
    }

    func testFormat() {
        XCTAssertEqual(TimeFormat.countdown(307), "05:07")
        XCTAssertEqual(TimeFormat.countUp(307), "5:07")
    }
}
