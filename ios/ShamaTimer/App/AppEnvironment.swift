import Foundation
import SwiftData

/// Сборка зависимостей приложения.
@MainActor
final class AppEnvironment: ObservableObject {
    let container: ModelContainer
    let auth: AuthManager
    let sync: SyncEngine
    let store: SessionStore
    let timer: TimerController
    let bells: BellPlayer
    let notifier: EndNotifier
    let health: HealthStore

    private var launched = false

    init(container: ModelContainer) {
        self.container = container
        let context = container.mainContext
        auth = AuthManager()
        sync = SyncEngine(backend: LifeServerBackend(), context: context)
        health = HealthStore()
        store = SessionStore(context: context, sync: sync, health: health)
        bells = BellPlayer()
        notifier = EndNotifier()
        timer = TimerController(bells: bells, notifier: notifier)

        let auth = self.auth
        sync.canSync = { auth.isSignedIn }
        sync.onUnauthorized = { auth.handleUnauthorized() }
        sync.onSuccess = { auth.markOnline() }
        let health = self.health
        timer.onStart = { health.requestAuthorizationIfNeeded() }
        let store = self.store
        timer.onFinish = { store.record($0) }
    }

    func launch() async {
        guard !launched else { return }
        launched = true
        timer.restore()
        await auth.check()
        await sync.sync()
    }

    func becameActive() {
        timer.becameActive()
        guard launched else { return }
        sync.kick()
    }

    func signedIn() {
        health.requestAuthorizationIfNeeded()
        sync.kick()
    }
}
