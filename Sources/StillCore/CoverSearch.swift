import Foundation

public actor CoverSearch {
    public static let shared = CoverSearch()
    private var nextRequest = Date.distantPast
    public struct Release: Decodable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let date: String?
        public let country: String?
        public var imageURL: URL? {
            guard UUID(uuidString: id) != nil else { return nil }
            return URL(string: "https://coverartarchive.org/release/\(id)/front-500")
        }
    }
    private struct Response: Decodable { let releases: [Release] }
    public func search(_ query: String) async throws -> [Release] {
        let delay = nextRequest.timeIntervalSinceNow
        nextRequest = Date().addingTimeInterval(max(0, delay) + 1.1)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release/")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query), URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "12"),
        ]
        let data = try await Self.fetch(components.url!, limit: 2 * 1024 * 1024)
        return try JSONDecoder().decode(Response.self, from: data).releases
    }
    public static func fetch(_ url: URL, limit: Int = 16 * 1024 * 1024) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue("StillMusic/0.2 (https://github.com/bhone101/still-music)", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard response.expectedContentLength <= Int64(limit) else { throw URLError(.dataLengthExceedsMaximum) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
}
