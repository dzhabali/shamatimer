import SwiftUI
import SwiftData

@main
struct ShamaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var env: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Session.self)
        } catch {
            fatalError("SwiftData: \(error)")
        }
        _env = StateObject(wrappedValue: AppEnvironment(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .environmentObject(env.auth)
                .environmentObject(env.sync)
                .environmentObject(env.timer)
                .environmentObject(env.healthExport)
                .modelContainer(env.container)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { env.becameActive() }
        }
    }
}

/// HealthKit будит приложение в фоне — observer'ы нужны с первой секунды каждого запуска, до SwiftUI.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        HealthExporter.shared.startObserving()
        return true
    }
}

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        Group {
            switch auth.state {
            case .checking:
                Text("Shama")
                    .font(Theme.serifItalic(40))
                    .foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                LoginView()
            case .signedIn:
                MainView()
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .task { await env.launch() }
        .onChange(of: auth.state) { old, new in
            if old == .signedOut, new == .signedIn { env.signedIn() }
        }
    }
}
