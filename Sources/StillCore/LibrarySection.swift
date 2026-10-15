import Foundation

public enum LibrarySection: String, CaseIterable, Identifiable {
    case songs = "Songs", albums = "Albums", artists = "Artists", genres = "Genres"
    case composers = "Composers", folders = "Folders", favorites = "Favorites", playlist = "Create a playlist", settings = "Settings"
    public var id: String { rawValue }
    public var icon: String {
        switch self {
        case .songs: return "music.note"
        case .albums: return "square.stack"
        case .artists: return "mic"
        case .genres: return "guitars"
        case .composers: return "music.quarternote.3"
        case .folders: return "folder"
        case .favorites: return "heart.fill"
        case .playlist: return "plus.circle"
        case .settings: return "gearshape"
        }
    }
    public var isGrouped: Bool { [.albums, .artists, .genres, .composers, .folders].contains(self) }
}

public func songCountLabel(_ count: Int) -> String { "\(count) \(count == 1 ? "song" : "songs")" }

public struct MusicPlaylist: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var trackIDs: [String]
    public init(name: String, trackIDs: [String] = []) {
        id = UUID(); self.name = name; self.trackIDs = trackIDs
    }
    public mutating func add(_ id: String) { if !trackIDs.contains(id) { trackIDs.append(id) } }
}

public struct LibraryGroup: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let tracks: [Track]
}

public enum LibraryGrouping {
    // Match R&B first so its ampersand is never treated as a genre separator.
    private static let genreTokens = try! NSRegularExpression(pattern: #"\bR\s*&\s*B\b|[;/&]"#, options: .caseInsensitive)
    private static let rhythmAndBlues = try! NSRegularExpression(pattern: #"\bR\s*&\s*B\b"#, options: .caseInsensitive)

    private static func tagNames(_ raw: String, isGenre: Bool) -> [String] {
        guard isGenre else { return raw.components(separatedBy: CharacterSet(charactersIn: ";/&")) }
        let text = raw as NSString
        var start = 0
        var names: [String] = []
        for token in genreTokens.matches(in: raw, range: NSRange(location: 0, length: text.length)) where token.range.length == 1 {
            names.append(text.substring(with: NSRange(location: start, length: token.range.location - start)))
            start = NSMaxRange(token.range)
        }
        names.append(text.substring(from: start))
        return names.map {
            rhythmAndBlues.stringByReplacingMatches(in: $0, range: NSRange($0.startIndex..., in: $0), withTemplate: "R&B")
        }
    }

    public static func groups(_ tracks: [Track], by section: LibrarySection) -> [LibraryGroup] {
        guard section.isGrouped else { return [] }
        if section == .genres || section == .composers {
            var buckets: [String: (name: String, tracks: [Track])] = [:]
            for track in tracks {
                let raw = section == .genres ? track.genre : track.composer
                var names = tagNames(raw ?? "", isGenre: section == .genres)
                    .map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }.filter { !$0.isEmpty }
                if names.isEmpty { names = [section == .genres ? "Unknown genre" : "Unknown composer"] }
                var seen = Set<String>()
                for var name in names {
                    var key = name.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                    if section == .genres {
                        // Explicitly repair the known Pop typo without transliterating other names.
                        if ["pop", "пon", "поп"].contains(key) { name = "Pop"; key = "pop" }
                        if ["hip-hop", "hip hop", "hiphop"].contains(key) { name = "Hip-Hop"; key = "hip-hop" }
                    }
                    guard seen.insert(key).inserted else { continue }
                    if buckets[key] == nil { buckets[key] = (name, []) }
                    if !buckets[key]!.tracks.contains(where: { $0.id == track.id }) { buckets[key]!.tracks.append(track) }
                }
            }
            return buckets.map { LibraryGroup(id: $0.key, title: $0.value.name, subtitle: "", tracks: $0.value.tracks) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        func labels(_ track: Track) -> (key: String, title: String, subtitle: String) {
            switch section {
            case .albums:
                let title = track.album.isEmpty ? "Unknown album" : track.album
                return (title + "\u{001f}" + track.displayAlbumArtist, title, track.displayAlbumArtist)
            case .artists: return (track.displayAlbumArtist, track.displayAlbumArtist, "")
            case .genres: let name = track.genre ?? "Unknown genre"; return (name, name, "")
            case .composers: let name = track.composer ?? "Unknown composer"; return (name, name, "")
            case .folders:
                let folder = track.url.deletingLastPathComponent()
                return (folder.path, folder.lastPathComponent, folder.deletingLastPathComponent().path)
            default: return ("", "", "")
            }
        }
        return Dictionary(grouping: tracks, by: { labels($0).key }).map { key, items in
            let label = labels(items[0])
            let sorted = section == .albums ? items.sorted {
                if ($0.discNumber ?? 1) != ($1.discNumber ?? 1) { return ($0.discNumber ?? 1) < ($1.discNumber ?? 1) }
                if ($0.trackNumber ?? Int.max) != ($1.trackNumber ?? Int.max) { return ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max) }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            } : items
            return LibraryGroup(id: key, title: label.title, subtitle: label.subtitle, tracks: sorted)
        }.sorted { $0.title == $1.title ? $0.id < $1.id : $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

public extension MusicPlaylist {
    mutating func remove(_ trackID: String) { trackIDs.removeAll { $0 == trackID } }
    mutating func move(_ trackID: String, by offset: Int) {
        guard let index = trackIDs.firstIndex(of: trackID), trackIDs.indices.contains(index + offset) else { return }
        trackIDs.swapAt(index, index + offset)
    }
    mutating func reconcilePaths(_ replacements: [String: String]) {
        var seen = Set<String>()
        trackIDs = trackIDs.map { replacements[$0] ?? $0 }.filter { seen.insert($0).inserted }
    }
}

public enum PlaylistStorage {
    public static func load(from url: URL) throws -> [MusicPlaylist] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([MusicPlaylist].self, from: Data(contentsOf: url))
    }
    public static func save(_ playlists: [MusicPlaylist], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(playlists).write(to: url, options: .atomic)
    }
}
