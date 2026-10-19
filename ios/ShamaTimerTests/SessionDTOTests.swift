import Foundation
import XCTest
@testable import ShamaTimer

final class SessionDTOTests: XCTestCase {
    private let json = """
    [
     {"id":1600000000000,"date":"2020-09-13T12:26:40.000Z","endDate":"2020-09-13T12:46:40.000Z","durationSec":1200,"plannedSec":null,"complete":true,"mode":"imported","activity":"meditation","note":"good","source":"insight-timer","firebaseDocId":"it_1600000000000","createdAt":"2026-10-16T05:38:54.727654Z"},
     {"id":1760000000123,"date":"2026-09-26T10:00:00.000Z","endDate":"2026-09-26T10:30:05.000Z","durationSec":1805,"complete":true,"mode":"stopwatch","firebaseDocId":"a1b2c3"},
     {"id":1760000000999,"date":"2026-09-27T10:00:00.000Z","endDate":"2026-09-27T10:45:00.000Z","durationSec":2700,"plannedSec":null,"complete":true,"mode":"manual","firebaseDocId":"x.y-z"},
     {"id":1700000000000,"date":"2023-11-14T22:13:20.5Z","endDate":"2023-11-14T22:33:20Z","durationSec":1200,"plannedSec":1800,"complete":false,"firebaseDocId":"old"},
     {"id":"bad","date":"nope"}
    ]
    """

    func testDecodeRealVariants() throws {
        let list = try SessionDTO.decodeList(Data(json.utf8))
        XCTAssertEqual(list.count, 4, "битая запись пропускается")

        let imported = list[0]
        XCTAssertEqual(imported.id, 1_600_000_000_000)
        XCTAssertEqual(imported.mode, "imported")
        XCTAssertEqual(imported.activity, "meditation")
        XCTAssertEqual(imported.note, "good")
        XCTAssertEqual(imported.source, "insight-timer")
        XCTAssertNil(imported.plannedSec)
        XCTAssertEqual(imported.firebaseDocId, "it_1600000000000")

        let sw = list[1]
        XCTAssertEqual(sw.mode, "stopwatch")
        XCTAssertNil(sw.plannedSec)
        XCTAssertEqual(sw.durationSec, 1805)

        XCTAssertEqual(list[2].mode, "manual")

        let noMode = list[3]
        XCTAssertNil(noMode.mode)
        XCTAssertEqual(noMode.plannedSec, 1800)
        XCTAssertFalse(noMode.complete)
        XCTAssertEqual(noMode.date.timeIntervalSince1970, 1_700_000_000.5, accuracy: 0.001)
    }

    func testDateParsingVariants() {
        XCTAssertEqual(ShamaDate.parse("2026-10-16T05:38:54.727654Z").map(ShamaDate.format), "2026-10-16T05:38:54.727Z")
        XCTAssertEqual(ShamaDate.parse("2026-10-16T05:38:54Z").map(ShamaDate.format), "2026-10-16T05:38:54.000Z")
        XCTAssertEqual(ShamaDate.parse("2026-10-16T07:38:54+02:00").map(ShamaDate.format), "2026-10-16T05:38:54.000Z")
        XCTAssertNotNil(ShamaDate.parse("2026-10-16T05:38:54"))
        XCTAssertNil(ShamaDate.parse("nope"))
    }

    func testPostBodyEncoding() throws {
        let dto = SessionDTO(id: 1_760_000_000_123,
                             date: ShamaDate.fromMilliseconds(1_760_000_000_123),
                             endDate: ShamaDate.fromMilliseconds(1_760_001_800_456),
                             durationSec: 1800, plannedSec: nil, complete: true, mode: "stopwatch",
                             note: nil, firebaseDocId: "server-id")
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: dto.postBody()) as? [String: Any])
        XCTAssertEqual(obj["date"] as? String, "2025-10-09T08:53:20.123Z")
        XCTAssertEqual(obj["endDate"] as? String, "2025-10-09T09:23:20.456Z")
        XCTAssertTrue(obj["plannedSec"] is NSNull, "plannedSec: null явно")
        XCTAssertEqual((obj["id"] as? NSNumber)?.int64Value, 1_760_000_000_123)
        XCTAssertNil(obj["firebaseDocId"])
        XCTAssertNil(obj["note"])
        XCTAssertEqual(obj["mode"] as? String, "stopwatch")
        XCTAssertEqual(obj["complete"] as? Bool, true)
    }

    func testRoundTrip() throws {
        let list = try SessionDTO.decodeList(Data(json.utf8))
        var s = list[0]
        s.firebaseDocId = nil
        let back = try JSONDecoder().decode(SessionDTO.self, from: s.postBody())
        XCTAssertEqual(back, s)
    }

    func testPasswordPercentEncoding() {
        XCTAssertEqual(FormEncoding.escape("a+b&c=d é"), "a%2Bb%26c%3Dd%20%C3%A9")
        XCTAssertEqual(FormEncoding.encode([("pw", "a+b&c=d é"), ("next", "/shama/")]),
                       "pw=a%2Bb%26c%3Dd%20%C3%A9&next=%2Fshama%2F")
    }
}
