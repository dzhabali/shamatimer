import Foundation

protocol SyncBackend {
    func fetchAll() async throws -> [SessionDTO]
    /// POST, возвращает серверный id.
    func create(_ s: SessionDTO) async throws -> String
    func patch(serverId: String, fields: [String: String]) async throws
    func delete(serverId: String) async throws
}

struct LifeServerBackend: SyncBackend {
    var urlSession: URLSession = LifeAPI.session

    func fetchAll() async throws -> [SessionDTO] {
        var r = URLRequest(url: LifeAPI.sessionsURL)
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await send(r)
        do { return try SessionDTO.decodeList(data) } catch { throw SyncError.badResponse }
    }

    func create(_ s: SessionDTO) async throws -> String {
        var r = URLRequest(url: LifeAPI.sessionsURL)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try s.postBody()
        let (data, _) = try await send(r)
        struct Created: Decodable { let id: String }
        guard let c = try? JSONDecoder().decode(Created.self, from: data), !c.id.isEmpty else {
            throw SyncError.badResponse
        }
        return c.id
    }

    func patch(serverId: String, fields: [String: String]) async throws {
        var r = URLRequest(url: url(for: serverId))
        r.httpMethod = "PATCH"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONEncoder().encode(fields)
        _ = try await send(r)
    }

    func delete(serverId: String) async throws {
        var r = URLRequest(url: url(for: serverId))
        r.httpMethod = "DELETE"
        _ = try await send(r)
    }

    private func url(for serverId: String) -> URL {
        LifeAPI.sessionsURL.appendingPathComponent(serverId)
    }

    private func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await urlSession.data(for: req)
        } catch {
            throw SyncError.network(error)
        }
        guard let http = resp as? HTTPURLResponse else { throw SyncError.badResponse }
        switch http.statusCode {
        case 200..<300: return (data, http)
        case 401: throw SyncError.unauthorized
        case 404: throw SyncError.notFound
        default: throw SyncError.server(http.statusCode)
        }
    }
}
