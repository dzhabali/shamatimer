import Foundation

/// Вход через пароль Life: POST /chronicle/login → кука `life`. Пароль не хранится.
@MainActor
final class AuthManager: ObservableObject {
    enum State: Equatable { case checking, signedOut, signedIn }

    @Published private(set) var state: State = .checking
    @Published private(set) var email: String?
    @Published private(set) var offline = false

    private let flagKey = "shama.wasSignedIn"
    private let emailKey = "shama.email"
    private let urlSession = LifeAPI.session

    private var wasSignedIn: Bool {
        get { UserDefaults.standard.bool(forKey: flagKey) }
        set { UserDefaults.standard.set(newValue, forKey: flagKey) }
    }

    init() {
        email = UserDefaults.standard.string(forKey: emailKey)
    }

    var isSignedIn: Bool { state == .signedIn }

    /// GET /shama/api/me. Нет сети, но раньше входили — пускаем офлайн.
    func check() async {
        switch await fetchMe() {
        case .ok:
            offline = false
            state = .signedIn
        case .unauthorized:
            markSignedOut()
        case .unreachable:
            offline = true
            state = wasSignedIn ? .signedIn : .signedOut
        }
    }

    /// nil — успех, иначе текст ошибки.
    func signIn(password: String) async -> String? {
        var r = URLRequest(url: LifeAPI.loginURL)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = FormEncoding.encode([("pw", password), ("next", "/shama/")]).data(using: .utf8)
        do {
            let (_, resp) = try await urlSession.data(for: r) // 303 → /shama/ URLSession проходит сам
            if let http = resp as? HTTPURLResponse, http.statusCode == 401 { return "Wrong password" }
        } catch {
            return "No connection"
        }
        switch await fetchMe() {
        case .ok:
            offline = false
            state = .signedIn
            return nil
        case .unauthorized:
            return "Wrong password"
        case .unreachable:
            return "No connection"
        }
    }

    func signOut() {
        let storage = HTTPCookieStorage.shared
        for c in storage.cookies ?? [] where c.name == LifeAPI.cookieName {
            storage.deleteCookie(c)
        }
        markSignedOut()
    }

    /// Успешный синк — сеть есть.
    func markOnline() { offline = false }

    /// 401 от API во время работы.
    func handleUnauthorized() { signOut() }

    private func markSignedOut() {
        wasSignedIn = false
        email = nil
        UserDefaults.standard.removeObject(forKey: emailKey)
        offline = false
        state = .signedOut
    }

    private enum MeResult { case ok, unauthorized, unreachable }

    private func fetchMe() async -> MeResult {
        var r = URLRequest(url: LifeAPI.meURL)
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await urlSession.data(for: r)
            guard let http = resp as? HTTPURLResponse else { return .unreachable }
            if http.statusCode == 401 { return .unauthorized }
            guard http.statusCode == 200 else { return .unreachable }
            struct Me: Decodable { let uid: String?; let email: String? }
            let me = try? JSONDecoder().decode(Me.self, from: data)
            wasSignedIn = true
            email = me?.email
            UserDefaults.standard.set(me?.email, forKey: emailKey)
            return .ok
        } catch {
            return .unreachable
        }
    }
}
