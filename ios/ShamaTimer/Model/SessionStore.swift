import Foundation
import SwiftData

/// Все записи в локальную базу проходят здесь: сохранить, заметка, удалить — затем синк.
@MainActor
final class SessionStore {
    private let context: ModelContext
    private let sync: SyncEngine
    private let health: HealthStore

    init(context: ModelContext, sync: SyncEngine, health: HealthStore) {
        self.context = context
        self.sync = sync
        self.health = health
    }

    func record(_ f: FinishedSession) {
        insert(start: f.start, end: f.end, durationSec: f.durationSec, plannedSec: f.plannedSec,
               complete: f.complete, mode: f.mode)
    }

    /// Ручная сессия: старт в 12:00 локально выбранного дня.
    func addManual(day: Date, minutes: Int) {
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 12, minute: 0, second: 0, of: cal.startOfDay(for: day)) ?? day
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        insert(start: start, end: end, durationSec: minutes * 60, plannedSec: nil, complete: true, mode: "manual")
    }

    func setNote(_ s: Session, note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (s.note ?? "") != trimmed else { return }
        s.note = trimmed
        s.needsNotePush = true
        try? context.save()
        sync.kick()
    }

    func delete(_ s: Session) {
        s.pendingDelete = true
        try? context.save()
        sync.kick()
    }

    private func insert(start: Date, end: Date, durationSec: Int, plannedSec: Int?, complete: Bool, mode: String) {
        let s = Session(clientId: newClientId(), date: start, endDate: end, durationSec: durationSec,
                        plannedSec: plannedSec, complete: complete, mode: mode)
        context.insert(s)
        try? context.save()
        health.saveMindful(start: start, end: end)
        sync.kick()
    }

    private func newClientId() -> Int64 {
        var id = ShamaDate.milliseconds(Date())
        while exists(id) { id += 1 }
        return id
    }

    private func exists(_ id: Int64) -> Bool {
        var d = FetchDescriptor<Session>(predicate: #Predicate { $0.clientId == id })
        d.fetchLimit = 1
        return ((try? context.fetchCount(d)) ?? 0) > 0
    }
}
