import Foundation
import XCTest
@testable import ShamaTimer

final class StatsTests: XCTestCase {
    private var vienna: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return c
    }()

    private func d(_ s: String) -> Date { ShamaDate.parse(s)! }

    func testLocalDayAt0030Vienna() {
        // 00:30 по Вене 19.10 = 22:30Z 18.10 — день должен быть 19-е, а не 18-е (баг веба с UTC).
        XCTAssertEqual(DayKey(d("2026-10-18T22:30:00Z"), calendar: vienna), DayKey(year: 2026, month: 10, day: 19))
        let by = ShamaStats.secondsByDay([(d("2026-10-18T22:30:00Z"), 600),
                                          (d("2026-10-18T10:00:00Z"), 1200),
                                          (d("2026-10-18T11:00:00Z"), 0)], calendar: vienna)
        XCTAssertEqual(by[DayKey(year: 2026, month: 10, day: 19)], 600)
        XCTAssertEqual(by[DayKey(year: 2026, month: 10, day: 18)], 1200)
    }

    func testStreak() {
        let today = d("2026-10-19T08:00:00Z")
        let dates = [d("2026-10-18T22:30:00Z"), d("2026-10-18T10:00:00Z"), d("2026-10-17T10:00:00Z"), d("2026-10-15T10:00:00Z")]
        XCTAssertEqual(ShamaStats.streak(dates: dates, today: today, calendar: vienna), 3)
        XCTAssertEqual(ShamaStats.streak(dates: [d("2026-10-18T10:00:00Z")], today: today, calendar: vienna), 0)
        XCTAssertEqual(ShamaStats.streak(dates: [], today: today, calendar: vienna), 0)
    }

    func testLevels() {
        XCTAssertEqual([0, 1, 20, 21, 40, 41, 59, 60, 90, 91].map(ShamaStats.level), [0, 1, 1, 2, 2, 3, 3, 4, 4, 5])
    }

    func testMonthGrid() {
        let by: [DayKey: Int] = [DayKey(year: 2026, month: 10, day: 19): 600,
                                 DayKey(year: 2026, month: 10, day: 18): 1200]
        let g = ShamaStats.monthGrid(year: 2026, month: 10, byDay: by, today: d("2026-10-19T08:00:00Z"), calendar: vienna)
        XCTAssertTrue(g.weeks.allSatisfy { $0.cells.count == 7 })
        XCTAssertEqual(g.weeks[0].cells[3]?.day, 1, "1 октября 2026 — четверг")
        XCTAssertNil(g.weeks[0].cells[0])
        XCTAssertEqual(g.average, 15)
        let week19 = g.weeks.first { $0.cells.contains { $0?.day == 19 } }!
        XCTAssertEqual(week19.average, 10)
        XCTAssertEqual(week19.cells[0]?.isToday, true)
        XCTAssertEqual(week19.cells[0]?.level, 1)
    }

    func testTotalTime() {
        XCTAssertTrue(ShamaStats.totalTime(seconds: 1500) == ("25", " min"))
        XCTAssertTrue(ShamaStats.totalTime(seconds: 3900) == ("1", " h 5 min"))
    }
}
