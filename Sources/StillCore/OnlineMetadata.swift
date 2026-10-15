import Foundation

/// Optional lookup only. Callers decide consent and always try local data first.
public actor OnlineMetadata {
    public typealias Fetch = @Sendable (URLRequest, Int) async throws -> Data
    private let fetch: Fetch
    private var nextRequest = Date.distantPast
    private var lyricsCache: [String: Lyrics] = [:]
    public init(fetch: @escaping Fetch = { request, limit in try await OnlineMetadata.download(request, limit: limit) }) { self.fetch = fetch }

    public static func download(_ request: URLRequest, limit: Int) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.expectedContentLength <= Int64(limit), response.url?.scheme == "https" else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            if data.count >= limit { throw URLError(.dataLengthExceedsMaximum) }
            try Task.checkCancellation()
            data.append(byte)
        }
        return data
    }
    private func request(_ url: URL, limit: Int = 1_048_576) async throws -> Data {
        // Check again after suspension; cancelled requests do not reserve future slots.
        while nextRequest.timeIntervalSinceNow > 0 {
            try await Task.sleep(nanoseconds: UInt64(max(0, nextRequest.timeIntervalSinceNow) * 1_000_000_000))
        }
        try Task.checkCancellation()
        nextRequest = Date().addingTimeInterval(1.1)
        var request = URLRequest(url: url)
        request.setValue("StillMusic/0.1.0 (native macOS music player)", forHTTPHeaderField: "User-Agent")
        return try await fetch(request, limit)
    }
    public static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    public func lyrics(for track: Track) async throws -> Lyrics {
        try Task.checkCancellation()
        guard !track.title.isEmpty, !track.artist.isEmpty, !track.artist.hasPrefix("Unknown") else { return Lyrics() }
        let key = track.title + "\u{001f}" + track.artist + "\u{001f}" + track.album + "\u{001f}" + String(track.duration)
        if let cached = lyricsCache[key] { return cached }
        var url = URLComponents(string: "https://lrclib.net/api/search")!
        url.queryItems = [.init(name: "track_name", value: track.title), .init(name: "artist_name", value: track.artist)]
        let records = try JSONDecoder().decode([LyricsRecord].self, from: await request(url.url!))
        let matches = records.filter {
            Self.normalized($0.trackName) == Self.normalized(track.title) && Self.normalized($0.artistName) == Self.normalized(track.artist)
                && abs($0.duration - track.duration) <= 2
        }.sorted {
            let a = Self.normalized($0.albumName ?? "") == Self.normalized(track.album)
            let b = Self.normalized($1.albumName ?? "") == Self.normalized(track.album)
            if a != b { return a }
            return abs($0.duration - track.duration) < abs($1.duration - track.duration)
        }
        var result = Lyrics()
        for match in matches {
            let synced = LRCParser.parse(match.syncedLyrics ?? "")
            let plain = LRCParser.parse(match.plainLyrics ?? "")
            if !synced.lines.isEmpty { result = synced; break }
            if !plain.lines.isEmpty { result = plain; break }
            if result.isEmpty { result = synced.isEmpty ? plain : synced }
        }
        try Task.checkCancellation()
        if lyricsCache.count >= 256 { lyricsCache.removeAll() }
        lyricsCache[key] = result
        return result
    }
    private struct LyricsRecord: Decodable {
        let trackName: String; let artistName: String; let albumName: String?
        let duration: Double; let syncedLyrics: String?; let plainLyrics: String?
    }
}
