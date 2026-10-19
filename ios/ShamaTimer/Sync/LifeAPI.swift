import Foundation

enum LifeAPI {
    static let base = URL(string: "https://life.maxdzhabali.com")!
    static let sessionsURL = base.appendingPathComponent("shama/api/sessions")
    static let meURL = base.appendingPathComponent("shama/api/me")
    static let loginURL = base.appendingPathComponent("chronicle/login")
    static let cookieName = "life"

    /// Одна URLSession на всё приложение; кука `life` (Max-Age год) живёт в HTTPCookieStorage.shared
    /// и переживает перезапуск.
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = .shared
        c.httpCookieAcceptPolicy = .always
        c.httpShouldSetCookies = true
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()
}

enum SyncError: Error {
    case unauthorized
    case notFound
    case network(Error)
    case server(Int)
    case badResponse
}
