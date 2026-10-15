import CryptoKit
import Foundation

/// User-selected lyrics stay in app storage, ahead of sidecars and embedded tags.
public enum ImportedLyrics {
    public static func file(for song: URL, root: URL) -> URL {
        let hash = SHA256.hash(data: Data(song.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(hash).appendingPathExtension("txt")
    }

    public enum Mode: String, Codable, Sendable { case draft, written, deleted, local }

    private static func modeFile(for song: URL, root: URL) -> URL {
        file(for: song, root: root).deletingPathExtension().appendingPathExtension("mode.json")
    }

    public static func mode(for song: URL, root: URL) throws -> Mode? {
        let url = modeFile(for: song, root: root)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Mode.self, from: Data(contentsOf: url))
    }

    public static func setMode(_ mode: Mode, for song: URL, root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(mode).write(to: modeFile(for: song, root: root), options: .atomic)
        // Old restoration snapshots are no longer used by the simplified system.
        let legacy = file(for: song, root: root).deletingPathExtension().appendingPathExtension("json")
        if FileManager.default.fileExists(atPath: legacy.path) { try FileManager.default.removeItem(at: legacy) }
        if mode != .draft {
            let baseline = baselineFile(for: song, root: root)
            if FileManager.default.fileExists(atPath: baseline.path) { try FileManager.default.removeItem(at: baseline) }
            let imported = file(for: song, root: root)
            if FileManager.default.fileExists(atPath: imported.path) { try FileManager.default.removeItem(at: imported) }
        }
    }

    private static func baselineFile(for song: URL, root: URL) -> URL {
        file(for: song, root: root).deletingPathExtension().appendingPathExtension("baseline.json")
    }

    /// Discard only the draft; never write or delete audio/sidecar files.
    public static func discard(for song: URL, root: URL) throws {
        let baseline = baselineFile(for: song, root: root)
        let previous: Mode
        if FileManager.default.fileExists(atPath: baseline.path) {
            previous = try JSONDecoder().decode(Mode.self, from: Data(contentsOf: baseline))
        } else { previous = .local }
        try setMode(previous == .draft ? .local : previous, for: song, root: root)
    }

    public static func save(_ lyrics: Lyrics, for song: URL, root: URL) throws {
        let data = try LyricsWriter.encode(lyrics)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if try mode(for: song, root: root) != .draft {
            let previous = try mode(for: song, root: root) ?? .local
            try JSONEncoder().encode(previous).write(to: baselineFile(for: song, root: root), options: .atomic)
        }
        try data.write(to: file(for: song, root: root), options: .atomic)
        try setMode(.draft, for: song, root: root)
    }

    public static func read(_ url: URL) throws -> Lyrics {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 8 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
        let data = try Data(contentsOf: url)
        guard let text = LyricsLoader.decode(data) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        let lyrics = LRCParser.parse(text)
        guard !lyrics.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        return lyrics
    }

    public static func save(from source: URL, for song: URL, root: URL) throws {
        try save(read(source), for: song, root: root)
    }
}
