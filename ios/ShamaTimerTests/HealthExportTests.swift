import Foundation
import XCTest
@testable import ShamaTimer

final class HealthExportTests: XCTestCase {
    private var vienna: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return c
    }()

    private func d(_ s: String) -> Date { ShamaDate.parse(s)! }
    private func iv(_ a: String, _ b: String) -> DateInterval { DateInterval(start: d(a), end: d(b)) }

    func testDayStringIsLocal() {
        XCTAssertEqual(HealthDay.string(d("2026-10-18T22:30:00Z"), calendar: vienna), "2026-10-19")
        XCTAssertEqual(HealthDay.string(d("2026-10-18T21:59:00Z"), calendar: vienna), "2026-10-18")
    }

    func testSleepNightAssignedToWakeDay() {
        // 23:00 18.10 → 07:00 19.10 по Вене (летнее время до 25.10: UTC+2)
        let m = SleepMath.minutesByNight([(true, iv("2026-10-18T21:00:00Z", "2026-10-19T05:00:00Z"))], calendar: vienna)
        XCTAssertEqual(m, ["2026-10-19": 480])
    }

    func testSleepExcludesInBedAndMergesOverlaps() {
        let m = SleepMath.minutesByNight([
            (false, iv("2026-10-18T20:00:00Z", "2026-10-19T06:00:00Z")),   // в кровати — не считается
            (true, iv("2026-10-18T21:00:00Z", "2026-10-19T01:00:00Z")),    // часы
            (true, iv("2026-10-19T00:00:00Z", "2026-10-19T03:00:00Z")),    // айфон, пересекается на час
        ], calendar: vienna)
        XCTAssertEqual(m, ["2026-10-19": 360])
    }

    func testSleepSplitsAt1800AndNapGoesToNextDay() {
        // дневной сон 17:30–18:30 местного: 30 мин в ночь 19-го, 30 — в ночь 20-го
        let m = SleepMath.minutesByNight([(true, iv("2026-10-19T15:30:00Z", "2026-10-19T16:30:00Z"))], calendar: vienna)
        XCTAssertEqual(m["2026-10-19"], 30)
        XCTAssertEqual(m["2026-10-20"], 30)
    }

    func testMindfulByStartDay() {
        let m = MindfulMath.minutesByDay([iv("2026-10-18T22:30:00Z", "2026-10-18T22:50:00Z"),
                                          iv("2026-10-19T06:00:00Z", "2026-10-19T06:10:00Z")], calendar: vienna)
        XCTAssertEqual(m, ["2026-10-19": 30])
    }

    func testValueRoundingAndMultipliers() {
        XCTAssertEqual(HealthMetrics.value("fat", raw: 0.2134), 21.3)
        XCTAssertEqual(HealthMetrics.value("steadiness", raw: 0.876), 88)
        XCTAssertEqual(HealthMetrics.value("steps", raw: 1234.6), 1235)
        XCTAssertEqual(HealthMetrics.value("distance", raw: 3.14159), 3.14)
        XCTAssertEqual(HealthMetrics.value("hrv", raw: 42.27), 42.3)
        XCTAssertEqual(HealthMetrics.value("sleep", raw: 431.6), 432)
        XCTAssertEqual(HealthMetrics.value("resthr", raw: 54.4), 54)
    }

    func testLedgerChangedRecordPrune() {
        var l = HealthLedger()
        let a = HealthSample(k: "steps", v: 100, d: "2026-10-18")
        let b = HealthSample(k: "sleep", v: 420, d: "2026-10-18")
        XCTAssertEqual(l.changed([a, b], timeZone: "Europe/Vienna"), [a, b])
        l.record([a, b], timeZone: "Europe/Vienna")
        XCTAssertEqual(l.changed([a, b], timeZone: "Europe/Vienna"), [])
        let a2 = HealthSample(k: "steps", v: 150, d: "2026-10-18")
        let c = HealthSample(k: "steps", v: 10, d: "2026-10-19")
        XCTAssertEqual(l.changed([a2, b, c], timeZone: "Europe/Vienna"), [a2, c])
        l.record([HealthSample(k: "hr", v: 60, d: "2025-01-01")], timeZone: "Europe/Vienna")
        l.prune(before: "2025-09-14")
        XCTAssertNil(l.sent["hr|2025-01-01"])
        XCTAssertEqual(l.sent.count, 2)
    }

    func testLedgerSkipsDaysSentInOtherTimeZone() {
        var l = HealthLedger()
        l.record([HealthSample(k: "steps", v: 100, d: "2026-10-10"),
                  HealthSample(k: "steps", v: 100, d: "2026-10-18")], timeZone: "Europe/Vienna")
        let moved = [HealthSample(k: "steps", v: 130, d: "2026-10-10"),   // старый день — пересчитан со сдвигом
                     HealthSample(k: "steps", v: 140, d: "2026-10-18"),   // вчера — шлём всегда
                     HealthSample(k: "steps", v: 50, d: "2026-10-05")]    // не отправлялся — шлём
        XCTAssertEqual(l.changed(moved, timeZone: "Asia/Kuala_Lumpur", alwaysDays: ["2026-10-18", "2026-10-19"]),
                       [moved[1], moved[2]])
        XCTAssertEqual(l.changed(moved, timeZone: "Europe/Vienna"), moved)
    }

    func testBatches() {
        XCTAssertEqual(HealthPush.batches(Array(0..<4500)).map(\.count), [2000, 2000, 500])
        XCTAssertEqual(HealthPush.batches([Int]()).count, 0)
        XCTAssertEqual(HealthPush.batches([1, 2, 3], size: 2), [[1, 2], [3]])
    }

    func testBodyJSONAndResponse() throws {
        let data = try HealthPush.body([HealthSample(k: "sleep", v: 431, d: "2026-10-19")])
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let s = (obj?["samples"] as? [[String: Any]])?.first
        XCTAssertEqual(s?["k"] as? String, "sleep")
        XCTAssertEqual(s?["d"] as? String, "2026-10-19")
        XCTAssertEqual((s?["v"] as? NSNumber)?.doubleValue, 431)
        let r = HealthPush.decode(#"{"ok": 3, "skipped": 1, "old": 0}"#.data(using: .utf8)!)
        XCTAssertEqual(r, HealthPush.Response(ok: 3, skipped: 1, old: 0))
        XCTAssertNil(HealthPush.decode(#"{"error":"нужен токен"}"#.data(using: .utf8)!))
    }

    func testAllServerKeysCovered() {
        let keys = Set(HealthMetrics.all.map(\.key))
        XCTAssertEqual(keys, ["steps", "distance", "flights", "active", "basal", "weight", "fat", "bmi", "lean",
                              "speed", "steplen", "support", "asym", "steadiness", "headphones",
                              "sleep", "resthr", "hrv", "hr", "resp", "vo2", "mindful"])
    }
}
