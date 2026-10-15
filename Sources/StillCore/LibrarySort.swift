import Foundation

public enum LibrarySortField: String, Codable, CaseIterable, Identifiable {
    case title = "Title", name = "Name", artist = "Artist", album = "Album"
    case dateAdded = "Date Added", quality = "Quality", trackNumber = "Track Number"
    case songCount = "Number of Songs", path = "Folder Path"
    public var id: String { rawValue }

    public static func options(for section: LibrarySection, inGroup: Bool = false) -> [Self] {
        if inGroup || section == .songs || section == .favorites || section == .playlist {
            return [.title, .artist, .album, .dateAdded, .quality] + (inGroup ? [.trackNumber] : [])
        }
        switch section {
        case .albums: return [.title, .songCount]
        case .folders: return [.name, .path, .songCount]
        case .artists, .genres, .composers: return [.name, .songCount]
        default: return []
        }
    }
}

public struct LibrarySort: Codable, Equatable {
    public var field: LibrarySortField
    public var ascending: Bool
    public init(field: LibrarySortField, ascending: Bool = true) {
        self.field = field
        self.ascending = ascending
    }

    public func tracks(_ items: [Track], library: [Track]) -> [Track] {
        // The library is append-only on import. Its saved order also preserves
        // date-added ordering for libraries created before sorting was available.
        let added = Dictionary(uniqueKeysWithValues: library.enumerated().map { ($0.element.id, $0.offset) })
        return items.sorted { a, b in
            var comparison: ComparisonResult
            switch field {
            case .artist: comparison = a.artist.localizedStandardCompare(b.artist)
            case .album: comparison = a.album.localizedStandardCompare(b.album)
            case .dateAdded: comparison = compare(added[a.id] ?? 0, added[b.id] ?? 0)
            case .trackNumber:
                comparison = compare(a.discNumber ?? 1, b.discNumber ?? 1)
                if comparison == .orderedSame { comparison = compare(a.trackNumber ?? Int.max, b.trackNumber ?? Int.max) }
            case .quality:
                // Source fidelity: lossless first, then depth, sample rate and bitrate.
                comparison = compare(a.bitDepth > 0 ? 1 : 0, b.bitDepth > 0 ? 1 : 0)
                if comparison == .orderedSame { comparison = compare(a.bitDepth, b.bitDepth) }
                if comparison == .orderedSame { comparison = compare(a.sampleRate, b.sampleRate) }
                if comparison == .orderedSame { comparison = compare(a.bitRate ?? 0, b.bitRate ?? 0) }
            default: comparison = a.title.localizedStandardCompare(b.title)
            }
            if comparison == .orderedSame { comparison = a.title.localizedStandardCompare(b.title) }
            if comparison == .orderedSame { comparison = a.id.compare(b.id) }
            return comparison == (ascending ? .orderedAscending : .orderedDescending)
        }
    }

    public func groups(_ items: [LibraryGroup]) -> [LibraryGroup] {
        items.sorted { a, b in
            var comparison: ComparisonResult
            switch field {
            case .songCount: comparison = compare(a.tracks.count, b.tracks.count)
            case .path: comparison = a.id.localizedStandardCompare(b.id)
            default: comparison = a.title.localizedStandardCompare(b.title)
            }
            if comparison == .orderedSame { comparison = a.title.localizedStandardCompare(b.title) }
            if comparison == .orderedSame { comparison = a.id.compare(b.id) }
            return comparison == (ascending ? .orderedAscending : .orderedDescending)
        }
    }

    private func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
    }
}
