import Foundation
import AVFoundation

/// Колокола + фоновая тишина. Пока идёт сессия, silence.caf играет в цикле — это держит
/// приложение живым при погашенном экране (UIBackgroundModes = audio), а финальный колокол
/// заранее запланирован через `play(atTime:)`.
@MainActor
final class BellPlayer {
    private var startPlayer: AVAudioPlayer?
    private var endPlayer: AVAudioPlayer?
    private var silencePlayer: AVAudioPlayer?

    private(set) var isActive = false
    /// Аудиосессия прервана (звонок и т.п.) — запланированный колокол может не прозвучать.
    private(set) var isInterrupted = false
    private var scheduledEnd: Date?
    private var deactivateTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    var endIsPlaying: Bool { endPlayer?.isPlaying ?? false }

    init() {
        loadPlayers()
        #if os(iOS)
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                        queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in self?.handleInterruption(typeRaw: raw) }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil,
                                        queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleMediaReset() }
        })
        #endif
    }

    private func loadPlayers() {
        startPlayer = Self.load("bell-start")
        endPlayer = Self.load("bell-end")
        silencePlayer = Self.load("silence")
        silencePlayer?.numberOfLoops = -1
    }

    private static func load(_ name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.prepareToPlay()
        return p
    }

    /// Начать (или продолжить после паузы/перезапуска) фоновую сессию.
    func beginSession(playStartBell: Bool) {
        deactivateTask?.cancel()
        deactivateTask = nil
        activateAudioSession()
        if silencePlayer?.isPlaying != true { silencePlayer?.play() }
        isActive = true
        if playStartBell, let p = startPlayer {
            p.stop()
            p.currentTime = 0
            p.play()
        }
    }

    /// Запланировать финальный колокол на дату. false — запланировать не вышло.
    @discardableResult
    func scheduleEnd(at date: Date) -> Bool {
        scheduledEnd = date
        guard let p = endPlayer else { return false }
        p.stop()
        p.currentTime = 0
        p.prepareToPlay()
        let delay = max(0, date.timeIntervalSinceNow)
        return p.play(atTime: p.deviceCurrentTime + delay)
    }

    func cancelScheduledEnd() {
        endPlayer?.stop()
        endPlayer?.currentTime = 0
        scheduledEnd = nil
    }

    func playEndNow() {
        if endPlayer == nil { endPlayer = Self.load("bell-end") }
        guard let p = endPlayer else { return }
        activateAudioSession()
        p.stop()
        p.currentTime = 0
        p.play()
    }

    /// Остановить тишину; аудиосессию отпустить через `deactivateAfter` с (чтобы колокол дозвучал).
    func endSession(deactivateAfter seconds: TimeInterval) {
        scheduledEnd = nil
        silencePlayer?.stop()
        isActive = false
        deactivateTask?.cancel()
        deactivateTask = Task { [weak self] in
            if seconds > 0 { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            guard !Task.isCancelled, let self, !self.isActive else { return }
            self.deactivateAudioSession()
        }
    }

    private func handleInterruption(typeRaw: UInt?) {
        #if os(iOS)
        guard let raw = typeRaw, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began { isInterrupted = true; return }
        isInterrupted = false
        guard isActive else { return }
        resumeAfterLoss()
        #endif
    }

    private func handleMediaReset() {
        isInterrupted = false
        loadPlayers()
        guard isActive else { return }
        resumeAfterLoss()
    }

    private func resumeAfterLoss() {
        activateAudioSession()
        silencePlayer?.play()
        if let end = scheduledEnd {
            let now = Date()
            if end > now {
                scheduleEnd(at: end)
            } else if now.timeIntervalSince(end) < 60 {
                playEndNow() // закончилось во время звонка — дозвонить
                scheduledEnd = nil
            }
        }
    }

    private func activateAudioSession() {
        #if os(iOS)
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? s.setActive(true)
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
