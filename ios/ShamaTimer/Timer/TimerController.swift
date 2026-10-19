import Foundation

/// Таймер: stopwatch (тап по орбу) и countdown (кнопка ▶), с блокировкой режима как в вебе.
@MainActor
final class TimerController: ObservableObject {
    @Published private(set) var active: ActiveTimer?
    @Published private(set) var now = Date()
    @Published private(set) var isDimmed = false
    @Published var toast: String?
    @Published var totalMinutes: Int {
        didSet { UserDefaults.standard.set(totalMinutes, forKey: Self.minutesKey) }
    }

    static let presets = [15, 30, 45, 60]
    private static let activeKey = "shama.active"
    private static let minutesKey = "shama.totalMinutes"

    private let bells: BellPlayer
    private let notifier: EndNotifier
    var onFinish: (FinishedSession) -> Void = { _ in }
    /// Первый старт таймера на переднем плане — здесь спрашиваем разрешения (Health).
    var onStart: () -> Void = {}

    private var ticker: Timer?
    private var dimTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var endScheduled = false
    private var notificationCleared = false

    init(bells: BellPlayer, notifier: EndNotifier) {
        self.bells = bells
        self.notifier = notifier
        let saved = UserDefaults.standard.integer(forKey: Self.minutesKey)
        totalMinutes = saved > 0 ? min(240, max(5, saved)) : 30
    }

    // MARK: состояние для UI

    var mode: ActiveTimer.Mode? { active?.mode }
    var isRunning: Bool { active?.isRunning ?? false }
    var isPaused: Bool { active?.isPaused ?? false }

    var displayText: String {
        guard let a = active else { return "▶" }
        switch a.mode {
        case .stopwatch: return TimeFormat.countUp(a.elapsedSec(at: now))
        case .countdown: return TimeFormat.countdown(a.secondsLeft(at: now))
        }
    }

    var orbLabel: String {
        guard let a = active else { return "DPE" }
        switch a.mode {
        case .stopwatch: return a.isPaused ? "▶" : "⏸"
        case .countdown: return a.isPaused ? "paused" : ""
        }
    }

    /// SF Symbol для большой кнопки.
    var playIcon: String { (active?.mode == .countdown && isRunning) ? "pause.fill" : "play.fill" }

    /// Видимая доля кольца: countdown — сколько осталось, иначе пусто.
    var ringFraction: Double {
        guard let a = active, a.mode == .countdown, a.plannedSec > 0 else { return 0 }
        return a.remaining(at: now) / Double(a.plannedSec)
    }

    // MARK: действия

    func setPreset(_ m: Int) { totalMinutes = m }
    func adjust(_ delta: Int) { totalMinutes = max(5, min(240, totalMinutes + delta)) }

    func orbTapped() {
        if isDimmed { undim(); return }
        if active?.mode == .countdown { return }
        if active == nil { start(.stopwatch) } else { togglePause() }
    }

    func playTapped() {
        if isDimmed { undim(); return }
        if active?.mode == .stopwatch { return }
        if active == nil { start(.countdown) } else { togglePause() }
    }

    func finishTapped() { finalize(at: Date()) }

    func undim() {
        isDimmed = false
        if isRunning { scheduleDim() }
    }

    /// Запуск приложения: восстановить активную сессию (как restoreActiveState в вебе).
    func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.activeKey) else { return }
        guard let a = try? JSONDecoder().decode(ActiveTimer.self, from: data) else {
            UserDefaults.standard.removeObject(forKey: Self.activeKey)
            return
        }
        active = a
        if a.mode == .countdown, a.plannedSec > 0 { totalMinutes = max(5, Int((Double(a.plannedSec) / 60).rounded())) }
        now = Date()
        if a.isExpired(at: now) {
            finalize(at: now) // колокол уже прозвучал уведомлением
            return
        }
        if a.isRunning {
            bells.beginSession(playStartBell: false)
            if a.mode == .countdown { scheduleEnd() }
            startTicker()
            scheduleDim()
        }
    }

    /// Возврат в foreground.
    func becameActive() {
        tick()
        if isRunning { startTicker() }
    }

    // MARK: внутреннее

    private func start(_ mode: ActiveTimer.Mode) {
        let a = ActiveTimer(mode: mode, start: Date(), plannedSec: mode == .countdown ? totalMinutes * 60 : 0,
                            pausedAt: nil)
        active = a
        now = a.start
        persist()
        onStart()
        bells.beginSession(playStartBell: true)
        if mode == .countdown { scheduleEnd() }
        startTicker()
        scheduleDim()
    }

    private func togglePause() {
        guard var a = active else { return }
        let t = Date()
        if a.isRunning {
            a.pause(at: t)
            active = a
            cancelEnd()
            bells.endSession(deactivateAfter: 0) // на паузе тишину не крутим
            dimTask?.cancel()
            isDimmed = false
        } else {
            a.resume(at: t)
            active = a
            if !bells.isActive { bells.beginSession(playStartBell: false) }
            if a.mode == .countdown { scheduleEnd() }
            startTicker()
            scheduleDim()
        }
        now = t
        persist()
    }

    private func scheduleEnd() {
        guard let end = active?.expectedEnd else { return }
        endScheduled = bells.scheduleEnd(at: end)
        notificationCleared = false
        notifier.schedule(at: end)
    }

    private func cancelEnd() {
        bells.cancelScheduledEnd()
        endScheduled = false
        notifier.cancel()
    }

    private func finalize(at t: Date) {
        guard let a = active else { return }
        var bellRings = false
        if a.isExpired(at: t), let end = a.expectedEnd {
            let lateness = t.timeIntervalSince(end)
            if lateness < 2 {
                // приложение живо: если запланированный колокол не звучит — играем сами
                if !endScheduled || !bells.endIsPlaying { bells.playEndNow() }
                bellRings = true
            }
            notifier.cancel()
        } else {
            cancelEnd()
        }
        let result = a.finish(at: t)
        active = nil
        endScheduled = false
        persist()
        stopTicker()
        dimTask?.cancel()
        isDimmed = false
        bells.endSession(deactivateAfter: bellRings ? 8 : 1)
        if let r = result {
            onFinish(r)
            showToast(r.complete ? "Session complete ✓" : "Session saved")
        }
    }

    private func tick() {
        now = Date()
        guard let a = active, a.isRunning, a.mode == .countdown else { return }
        let left = a.remaining(at: now)
        if left <= 3, !notificationCleared, !bells.isInterrupted {
            notifier.cancel() // приложение живо — колокол сыграет плеер, без двойного
            notificationCleared = true
        }
        if left <= 0 { finalize(at: now) }
    }

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func scheduleDim() {
        dimTask?.cancel()
        dimTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled, let self, self.isRunning else { return }
            self.isDimmed = true
        }
    }

    private func showToast(_ s: String) {
        toast = s
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    private func persist() {
        if let a = active, let data = try? JSONEncoder().encode(a) {
            UserDefaults.standard.set(data, forKey: Self.activeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeKey)
        }
    }
}
