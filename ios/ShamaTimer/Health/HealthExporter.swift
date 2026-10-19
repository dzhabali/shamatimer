import Foundation
import HealthKit
#if os(iOS)
import UIKit
#endif

/// Фоновая выгрузка дневных сводок Apple Health в Life (POST /chronicle/api/health/push по куке `life`).
/// Шлёт только изменившиеся (ключ, день). Первый полностью успешный прогон — год назад, дальше — 14 дней.
/// Один общий объект (`shared`): observer'ы регистрирует AppDelegate при каждом запуске, AppEnvironment
/// берёт его же. @MainActor + флаг isRunning — параллельных прогонов нет; пропущенный запуск (идёт прогон,
/// частые пробуждения, заблокированный экран) помечается pending и досылается позже.
@MainActor
final class HealthExporter: ObservableObject {
    enum Status: Equatable { case unknown, unavailable, noAccess, sent(Date) }

    static let shared = HealthExporter(store: HealthStore.hkStore)

    @Published private(set) var status: Status = .unknown

    static let pushURL = LifeAPI.base.appendingPathComponent("chronicle/api/health/push")
    static let recentDays = 14
    static let backfillDays = 365
    static let keepDays = 400
    static let backgroundInterval: TimeInterval = 120
    static let foregroundInterval: TimeInterval = 600

    private let store: HKHealthStore
    private let urlSession: URLSession
    private var isRunning = false
    private var lastRun: Date?
    private var pending = false
    private var rerunScheduled = false
    private var queries: [HKObserverQuery] = []
    private var protectedObserver: NSObjectProtocol?
    #if os(iOS)
    private var backgroundBox: TaskBox?
    #endif

    private let lastSentKey = "health.lastSent"
    private let backfillKey = "health.backfillDone"

    init(store: HKHealthStore, urlSession: URLSession = LifeAPI.session) {
        self.store = store
        self.urlSession = urlSession
        if let d = UserDefaults.standard.object(forKey: lastSentKey) as? Date { status = .sent(d) }
        #if os(iOS)
        protectedObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.protectedDataAvailable() }
        }
        #endif
    }

    // MARK: триггеры

    /// Observer'ы на все типы + фоновая доставка. Зовётся при каждом запуске (iOS требует) и ещё раз после
    /// выдачи разрешения: старые observer'ы снимаются, новые ставятся, доставка включается заново.
    func startObserving() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        for q in queries { store.stop(q) }
        queries = []
        for type in HealthTypes.sampleTypes {
            let q = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                if error != nil { completion(); return }
                Task { @MainActor in
                    await self?.run(minInterval: Self.backgroundInterval, markPending: true)
                    completion()
                }
            }
            store.execute(q)
            queries.append(q)
            let immediate = type == HealthTypes.sleep || type == HKQuantityType(.bodyMass)
            store.enableBackgroundDelivery(for: type, frequency: immediate ? .immediate : .hourly) { _, _ in }
        }
    }

    /// Запуск/возврат на передний план — не чаще раза в 10 минут.
    func kick() {
        Task { await run(minInterval: Self.foregroundInterval, markPending: false) }
    }

    /// После диалога разрешений — переподписаться и выгрузить сразу.
    func authorizationFinished() {
        startObserving()
        Task { await run(minInterval: 0, markPending: true) }
    }

    private func protectedDataAvailable() {
        guard pending else { return }
        pending = false
        Task { await run(minInterval: 0, markPending: true) }
    }

    // MARK: прогон

    func run(minInterval: TimeInterval, markPending: Bool) async {
        if isRunning { pending = true; return }
        if let l = lastRun, Date().timeIntervalSince(l) < minInterval {
            if markPending { pending = true; scheduleRerun() }
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { status = .unavailable; return }
        guard hasLifeCookie() else { return }
        #if os(iOS)
        // экран заблокирован — база Health закрыта; досылаем, как только откроется
        guard UIApplication.shared.isProtectedDataAvailable else { pending = true; return }
        #endif
        isRunning = true
        pending = false
        lastRun = Date()
        let bg = beginBackground()
        defer {
            isRunning = false
            endBackground(bg)
            if pending { scheduleRerun() }
        }
        guard await accessRequested() else { status = .noAccess; return }

        let backfill = !UserDefaults.standard.bool(forKey: backfillKey)
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let days = backfill ? Self.backfillDays : Self.recentDays
        let from = cal.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let (samples, complete) = await collect(from: from, to: now, calendar: cal)

        var ledger = loadLedger()
        let cutoff = cal.date(byAdding: .day, value: -Self.keepDays, to: today) ?? today
        ledger.prune(before: HealthDay.string(cutoff, calendar: cal))
        let tz = cal.timeZone.identifier
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
        let fresh: Set<String> = [HealthDay.string(today, calendar: cal), HealthDay.string(yesterday, calendar: cal)]
        let todo = ledger.changed(samples, timeZone: tz, alwaysDays: fresh)

        for batch in HealthPush.batches(todo) {
            switch await send(batch) {
            case .ok:
                ledger.record(batch, timeZone: tz)
                saveLedger(ledger)
            case .unauthorized, .failed:
                saveLedger(ledger)
                return // 401 — вход протух, приложение само покажет логин; сеть — в следующий раз
            }
        }
        saveLedger(ledger)
        guard complete else { pending = true; return } // часть типов не прочиталась — успехом не считаем
        UserDefaults.standard.set(true, forKey: backfillKey)
        UserDefaults.standard.set(now, forKey: lastSentKey)
        status = .sent(now)
    }

    /// Ещё один прогон, когда истечёт фоновая пауза (один на всех).
    private func scheduleRerun() {
        guard !rerunScheduled else { return }
        rerunScheduled = true
        let wait = max(0, Self.backgroundInterval - Date().timeIntervalSince(lastRun ?? .distantPast))
        Task {
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            rerunScheduled = false
            guard pending else { return }
            await run(minInterval: 0, markPending: true)
        }
    }

    // MARK: HealthKit

    private struct QueryFailed: Error {}

    /// Диалог чтения уже показывался (что выбрал пользователь, HealthKit не говорит).
    private func accessRequested() async -> Bool {
        await withCheckedContinuation { cont in
            store.getRequestStatusForAuthorization(toShare: [], read: HealthTypes.readTypes) { s, error in
                cont.resume(returning: error == nil && s == .unnecessary)
            }
        }
    }

    /// → (сэмплы, все ли типы прочитались). Тип с ошибкой пропускается целиком — его дни не трогаем.
    private func collect(from: Date, to: Date, calendar: Calendar) async -> ([HealthSample], Bool) {
        var out: [HealthSample] = []
        var complete = true
        let firstDay = HealthDay.string(from, calendar: calendar)
        for q in HealthTypes.quantities {
            guard let spec = HealthMetrics.spec(q.key) else { continue }
            do {
                let byDay = try await dailyStatistics(q, agg: spec.agg, from: from, to: to, calendar: calendar)
                for (d, raw) in byDay where d >= firstDay {
                    out.append(HealthSample(k: q.key, v: HealthMetrics.value(q.key, raw: raw), d: d))
                }
            } catch {
                complete = false
            }
        }
        // сон: ночь начинается в 18:00 накануне первого дня
        do {
            let raw = try await categorySamples(HealthTypes.sleep, from: from.addingTimeInterval(-6 * 3600), to: to)
            let nights = SleepMath.minutesByNight(raw.map { (HealthTypes.isAsleep($0.value), Self.interval($0)) },
                                                  calendar: calendar)
            for (d, m) in nights where d >= firstDay && m > 0 {
                out.append(HealthSample(k: "sleep", v: HealthMetrics.value("sleep", raw: m), d: d))
            }
        } catch {
            complete = false
        }
        do {
            let raw = try await categorySamples(HealthTypes.mindful, from: from, to: to)
            let mind = MindfulMath.minutesByDay(raw.map(Self.interval), calendar: calendar)
            for (d, m) in mind where d >= firstDay && m > 0 {
                out.append(HealthSample(k: "mindful", v: HealthMetrics.value("mindful", raw: m), d: d))
            }
        } catch {
            complete = false
        }
        return (out, complete)
    }

    private nonisolated static func interval(_ s: HKCategorySample) -> DateInterval {
        DateInterval(start: s.startDate, end: max(s.startDate, s.endDate))
    }

    private func dailyStatistics(_ q: HealthTypes.Quantity, agg: HealthAgg, from: Date, to: Date,
                                 calendar: Calendar) async throws -> [String: Double] {
        let type = HKQuantityType(q.id)
        let options: HKStatisticsOptions
        switch agg {
        case .sum: options = .cumulativeSum
        case .mean: options = .discreteAverage
        case .last: options = .mostRecent
        }
        let anchor = calendar.startOfDay(for: from)
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: to, options: [])
        let unit = q.unit
        return try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                    options: options, anchorDate: anchor,
                                                    intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, results, error in
                if let error = error as? HKError, error.code == .errorNoData {
                    cont.resume(returning: [:]); return
                }
                guard error == nil, let results else { cont.resume(throwing: error ?? QueryFailed()); return }
                var out: [String: Double] = [:]
                results.enumerateStatistics(from: anchor, to: to) { s, _ in
                    let quantity: HKQuantity?
                    switch agg {
                    case .sum: quantity = s.sumQuantity()
                    case .mean: quantity = s.averageQuantity()
                    case .last: quantity = s.mostRecentQuantity()
                    }
                    if let quantity, quantity.is(compatibleWith: unit) {
                        out[HealthDay.string(s.startDate, calendar: calendar)] = quantity.doubleValue(for: unit)
                    }
                }
                cont.resume(returning: out)
            }
            store.execute(query)
        }
    }

    private func categorySamples(_ type: HKCategoryType, from: Date, to: Date) async throws -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, error in
                if let error = error as? HKError, error.code == .errorNoData {
                    cont.resume(returning: []); return
                }
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
    }

    // MARK: сеть

    private enum SendResult { case ok, unauthorized, failed }

    private func hasLifeCookie() -> Bool {
        (HTTPCookieStorage.shared.cookies(for: LifeAPI.base) ?? []).contains { $0.name == LifeAPI.cookieName }
    }

    private func send(_ batch: [HealthSample]) async -> SendResult {
        var r = URLRequest(url: Self.pushURL)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let body = try? HealthPush.body(batch) else { return .failed }
        r.httpBody = body
        do {
            let (data, resp) = try await urlSession.data(for: r)
            guard let http = resp as? HTTPURLResponse else { return .failed }
            if http.statusCode == 401 { return .unauthorized }
            guard http.statusCode == 200, HealthPush.decode(data) != nil else { return .failed }
            return .ok
        } catch {
            return .failed
        }
    }

    // MARK: что отправлено

    private var ledgerURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("health-sent.json")
    }

    private func loadLedger() -> HealthLedger {
        guard let url = ledgerURL, let data = try? Data(contentsOf: url),
              let l = try? JSONDecoder().decode(HealthLedger.self, from: data) else { return HealthLedger() }
        return l
    }

    private func saveLedger(_ l: HealthLedger) {
        guard let url = ledgerURL, let data = try? JSONEncoder().encode(l) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // файл должен читаться и в фоне после первой разблокировки
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: фон

    #if os(iOS)
    private final class TaskBox { var id: UIBackgroundTaskIdentifier = .invalid }

    /// Время вышло — задачу закрываем сами (иначе iOS убьёт приложение); недосланное уйдёт в следующий раз.
    private func beginBackground() -> UIBackgroundTaskIdentifier {
        let box = TaskBox()
        box.id = UIApplication.shared.beginBackgroundTask(withName: "shama.health") {
            if box.id != .invalid { UIApplication.shared.endBackgroundTask(box.id) }
            box.id = .invalid
        }
        backgroundBox = box
        return box.id
    }

    private func endBackground(_ id: UIBackgroundTaskIdentifier) {
        guard let box = backgroundBox, box.id == id, id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        box.id = .invalid
        backgroundBox = nil
    }
    #else
    private func beginBackground() -> Int { 0 }
    private func endBackground(_ id: Int) {}
    #endif
}
