import Foundation

/// Сессия в формате API `life.maxdzhabali.com/shama/api/sessions`.
struct SessionDTO: Equatable {
    var id: Int64
    var date: Date
    var endDate: Date
    var durationSec: Int
    var plannedSec: Int?
    var complete: Bool
    var mode: String?
    var activity: String?
    var note: String?
    var source: String?
    /// id записи на сервере (строка ≤80 `[\w.-]`). Только при чтении, на сервер не шлём.
    var firebaseDocId: String?
}

extension SessionDTO: Codable {
    enum CodingKeys: String, CodingKey {
        case id, date, endDate, durationSec, plannedSec, complete, mode, activity, note, source, firebaseDocId
    }

    enum DecodeError: Error { case badDate(String) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try Self.decodeInt64(c, .id)
        let dateStr = try c.decode(String.self, forKey: .date)
        guard let d = ShamaDate.parse(dateStr) else { throw DecodeError.badDate(dateStr) }
        date = d
        durationSec = Int((try? Self.decodeInt64(c, .durationSec)) ?? 0)
        if let endStr = try? c.decodeIfPresent(String.self, forKey: .endDate), let e = ShamaDate.parse(endStr) {
            endDate = e
        } else {
            endDate = d.addingTimeInterval(TimeInterval(durationSec))
        }
        plannedSec = (try? Self.decodeInt64(c, .plannedSec)).map { Int($0) }
        complete = ((try? c.decodeIfPresent(Bool.self, forKey: .complete)) ?? nil) ?? true
        mode = Self.string(c, .mode)
        activity = Self.string(c, .activity)
        note = Self.string(c, .note)
        source = Self.string(c, .source)
        firebaseDocId = Self.string(c, .firebaseDocId)
    }

    /// Тело POST: `{id, date, endDate, durationSec, plannedSec (null явно), complete, mode, note?, activity?, source?}`.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(ShamaDate.format(date), forKey: .date)
        try c.encode(ShamaDate.format(endDate), forKey: .endDate)
        try c.encode(durationSec, forKey: .durationSec)
        if let p = plannedSec { try c.encode(p, forKey: .plannedSec) } else { try c.encodeNil(forKey: .plannedSec) }
        try c.encode(complete, forKey: .complete)
        try c.encodeIfPresent(mode, forKey: .mode)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(activity, forKey: .activity)
        try c.encodeIfPresent(source, forKey: .source)
    }

    private static func decodeInt64(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) throws -> Int64 {
        if let v = try? c.decode(Int64.self, forKey: k) { return v }
        if let v = try? c.decode(Double.self, forKey: k) { return Int64(v.rounded()) }
        if let s = try? c.decode(String.self, forKey: k), let v = Int64(s) { return v }
        throw DecodingError.dataCorruptedError(forKey: k, in: c, debugDescription: "not an integer")
    }

    private static func string(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> String? {
        (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil
    }
}

extension SessionDTO {
    private struct Lossy: Decodable {
        let value: SessionDTO?
        init(from decoder: Decoder) throws { value = try? SessionDTO(from: decoder) }
    }

    /// Массив с сервера; битые записи пропускаются, а не валят весь синк.
    static func decodeList(_ data: Data) throws -> [SessionDTO] {
        try JSONDecoder().decode([Lossy].self, from: data).compactMap(\.value)
    }

    func postBody() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }
}
