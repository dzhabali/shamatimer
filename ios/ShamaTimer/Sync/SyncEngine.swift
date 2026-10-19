import Foundation
import SwiftData
#if os(iOS)
import UIKit
#endif

/// Двусторонний синк: сначала pull (он же проставляет serverId записям, чей POST дошёл, а ответ
/// потерялся — повторного POST не будет), потом push локальных изменений.
/// @MainActor + флаг isSyncing — гонок нет; повторный вызов во время синка ставит ещё один проход.
@MainActor
final class SyncEngine: ObservableObject {
    enum Status: Equatable { case idle, syncing, synced, offline }

    @Published private(set) var status: Status = .idle

    /// Больше стольких удалений за один pull не делаем (защита от пустого/битого ответа сервера).
    static let maxDeletesPerPull = 20

    private let backend: SyncBackend
    private let context: ModelContext
    private var isSyncing = false
    private var runAgain = false

    /// Можно ли сейчас синкать (вошли ли).
    var canSync: () -> Bool = { true }
    /// 401 от сервера.
    var onUnauthorized: () -> Void = {}
    /// Синк прошёл целиком.
    var onSuccess: () -> Void = {}

    init(backend: SyncBackend, context: ModelContext) {
        self.backend = backend
        self.context = context
    }

    func sync() async {
        guard canSync() else { return }
        if isSyncing { runAgain = true; return }
        isSyncing = true
        let bg = beginBackground()
        defer {
            isSyncing = false
            endBackground(bg)
        }
        repeat {
            runAgain = false
            let ok = await runOnce()
            if !ok { break }
        } while runAgain && canSync()
    }

    /// Запустить синк, не дожидаясь (после сохранения/удаления).
    func kick() {
        Task { await sync() }
    }

    private func runOnce() async -> Bool {
        status = .syncing
        do {
            try await pull()
            try await push()
            status = .synced
            onSuccess()
            return true
        } catch SyncError.unauthorized {
            status = .idle
            onUnauthorized()
            return false
        } catch {
            status = .offline
            return false
        }
    }

    /// Ошибка, на которой синк обрывается: сеть, 401, 5xx, битый ответ.
    /// 4xx (кроме 401) — «ядовитая» запись: пропускаем её и идём дальше.
    private static func isSkippable(_ error: Error) -> Bool {
        switch error {
        case SyncError.notFound: return true
        case SyncError.server(let code): return (400..<500).contains(code) && code != 401
        default: return false
        }
    }

    // MARK: push

    private func push() async throws {
        let all = try context.fetch(FetchDescriptor<Session>())
        let deletes = all.filter { $0.pendingDelete }
        let creates = all.filter { !$0.pendingDelete && $0.serverId == nil }
        let notes = all.filter { !$0.pendingDelete && $0.serverId != nil && $0.needsNotePush }

        for s in deletes where !s.isDeleted {
            if let sid = s.serverId {
                do { try await backend.delete(serverId: sid) } catch where Self.isSkippable(error) {
                    // 404 — уже нет; прочие 4xx — сервер не примет никогда, локально всё равно убираем
                }
            }
            if !s.isDeleted { context.delete(s) }
            try? context.save()
        }

        for s in creates where !s.isDeleted && s.modelContext != nil && s.serverId == nil && !s.pendingDelete {
            let sentNote = s.note
            do {
                let sid = try await backend.create(s.dto)
                guard !s.isDeleted else { continue }
                s.serverId = sid
                if s.note == sentNote { s.needsNotePush = false }
                try? context.save()
            } catch where Self.isSkippable(error) {
                continue // попробуем в следующий раз, остальные не держим
            }
        }

        for s in notes where !s.isDeleted && s.modelContext != nil && !s.pendingDelete {
            guard let sid = s.serverId else { continue }
            let sentNote = s.note ?? ""
            do {
                try await backend.patch(serverId: sid, fields: ["note": sentNote])
            } catch where Self.isSkippable(error) {
                // 404 — удалена в вебе, следующий pull уберёт; прочие 4xx — не долбим
            }
            guard !s.isDeleted else { continue }
            if (s.note ?? "") == sentNote { s.needsNotePush = false }
            try? context.save()
        }
    }

    // MARK: pull

    private func pull() async throws {
        let remote = try await backend.fetchAll()
        let all = try context.fetch(FetchDescriptor<Session>()).filter { !$0.isDeleted }
        var byClient: [Int64: Session] = [:]
        for s in all { byClient[s.clientId] = s }

        var seen = Set<Int64>()
        for r in remote {
            guard seen.insert(r.id).inserted else { continue } // дубль id на сервере — берём первый
            if let local = byClient[r.id] {
                if local.pendingDelete { continue }
                local.apply(r, keepNote: local.needsNotePush)
            } else {
                context.insert(Session(dto: r))
            }
        }

        // Удалены в вебе: были на сервере (есть serverId), а теперь их там нет.
        let gone = all.filter { $0.serverId != nil && !$0.pendingDelete && !seen.contains($0.clientId) }
        if !remote.isEmpty, gone.count <= Self.maxDeletesPerPull {
            for s in gone { context.delete(s) }
        }
        try context.save()
    }

    // MARK: фон

    #if os(iOS)
    private func beginBackground() -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(withName: "shama.sync") {
            // время вышло — система сама завершит; ответ дойдёт при следующем синке
        }
    }

    private func endBackground(_ id: UIBackgroundTaskIdentifier) {
        if id != .invalid { UIApplication.shared.endBackgroundTask(id) }
    }
    #else
    private func beginBackground() -> Int { 0 }
    private func endBackground(_ id: Int) {}
    #endif
}
