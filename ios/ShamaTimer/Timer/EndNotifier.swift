import Foundation
import UserNotifications

/// Страховка: локальное уведомление с колоколом на момент окончания countdown
/// (сработает, если приложение убито/усыплено). Если приложение живо — снимается за 3 с до конца.
final class EndNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let requestId = "shama.session.end"
    private let center = UNUserNotificationCenter.current()
    /// Поколение запроса: cancel() после schedule() не даст запоздалому add() пройти.
    private var generation = 0

    override init() {
        super.init()
        center.delegate = self
    }

    /// Спрашивает разрешение при первом старте countdown, затем ставит уведомление.
    func schedule(at date: Date) {
        generation += 1
        let gen = generation
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                switch settings.authorizationStatus {
                case .notDetermined:
                    self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        DispatchQueue.main.async {
                            guard granted, gen == self.generation else { return }
                            self.add(at: date)
                        }
                    }
                case .authorized, .provisional, .ephemeral:
                    self.add(at: date)
                default:
                    break
                }
            }
        }
    }

    func cancel() {
        generation += 1
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestId])
    }

    private func add(at date: Date) {
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Session complete"
        content.interruptionLevel = .timeSensitive
        content.sound = UNNotificationSound(named: UNNotificationSoundName("bell-end.caf"))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.requestId, content: content, trigger: trigger))
    }

    // В foreground колокол играет плеер — уведомление без звука.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
