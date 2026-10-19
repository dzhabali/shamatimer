import Foundation
import SwiftData

@Model
final class Session {
    /// = `id` веба (Date.now() в мс). Ключ слияния с сервером.
    @Attribute(.unique) var clientId: Int64
    var date: Date
    var endDate: Date
    var durationSec: Int
    var plannedSec: Int?
    var complete: Bool
    var mode: String?
    var activity: String?
    var note: String?
    var source: String?
    /// `firebaseDocId` на сервере; nil — ещё не отправлена.
    var serverId: String?
    var needsNotePush: Bool = false
    var pendingDelete: Bool = false

    init(clientId: Int64, date: Date, endDate: Date, durationSec: Int, plannedSec: Int?, complete: Bool,
         mode: String?, activity: String? = nil, note: String? = nil, source: String? = nil, serverId: String? = nil) {
        self.clientId = clientId
        self.date = date
        self.endDate = endDate
        self.durationSec = durationSec
        self.plannedSec = plannedSec
        self.complete = complete
        self.mode = mode
        self.activity = activity
        self.note = note
        self.source = source
        self.serverId = serverId
    }

    convenience init(dto: SessionDTO) {
        self.init(clientId: dto.id, date: dto.date, endDate: dto.endDate, durationSec: dto.durationSec,
                  plannedSec: dto.plannedSec, complete: dto.complete, mode: dto.mode, activity: dto.activity,
                  note: dto.note, source: dto.source, serverId: dto.firebaseDocId)
    }

    var dto: SessionDTO {
        SessionDTO(id: clientId, date: date, endDate: endDate, durationSec: durationSec, plannedSec: plannedSec,
                   complete: complete, mode: mode, activity: activity, note: note, source: source,
                   firebaseDocId: serverId)
    }

    var hasNote: Bool { !(note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Серверные поля перетирают локальные (кроме заметки, если она ещё не отправлена).
    /// Присваиваем только изменившееся, чтобы не дёргать @Query на каждом pull.
    func apply(_ r: SessionDTO, keepNote: Bool) {
        if date != r.date { date = r.date }
        if endDate != r.endDate { endDate = r.endDate }
        if durationSec != r.durationSec { durationSec = r.durationSec }
        if plannedSec != r.plannedSec { plannedSec = r.plannedSec }
        if complete != r.complete { complete = r.complete }
        if mode != r.mode { mode = r.mode }
        if activity != r.activity { activity = r.activity }
        if source != r.source { source = r.source }
        if serverId != r.firebaseDocId { serverId = r.firebaseDocId }
        if !keepNote, note != r.note { note = r.note }
    }
}
