import AVFoundation
import Foundation

public enum LyricsLoader {
    public typealias Source = @Sendable (URL) async -> Lyrics?
    // A user-supplied local source can later be prepended without changing lookup.
    public static let sources: [Source] = [{ await sidecar($0) }, { await embedded($0) }]
    public static func load(_ url: URL, sources: [Source] = Self.sources) async -> Lyrics {
        guard url.isFileURL else { return Lyrics() }
        for source in sources {
            if Task.isCancelled { return Lyrics() }
            if let lyrics = await source(url), !lyrics.isEmpty { return lyrics }
        }
        return Lyrics()
    }
    static func decode(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}")) }
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) { return String(data: data, encoding: .utf16) }
        for encoding in [String.Encoding.windowsCP1252, .isoLatin1] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return nil
    }
    private static func sidecar(_ url: URL) async -> Lyrics? {
        for ext in ["lrc", "txt"] {
            let path = url.deletingPathExtension().appendingPathExtension(ext)
            guard let size = try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8 * 1024 * 1024,
                  let data = try? Data(contentsOf: path), let text = decode(data) else { continue }
            let lyrics = LRCParser.parse(text)
            if !lyrics.isEmpty { return lyrics }
        }
        return nil
    }
    public static func embedded(_ url: URL) async -> Lyrics? {
        if let tags = try? FLACComments.read(url) {
            for key in ["LYRICS", "UNSYNCEDLYRICS"] {
                if let text = tags[key]?.joined(separator: "\n") {
                    let lyrics = LRCParser.parse(text)
                    if !lyrics.isEmpty { return lyrics }
                }
            }
        }
        if url.pathExtension.lowercased() == "mp3", let lyrics = ID3Lyrics.read(url), !lyrics.isEmpty { return lyrics }
        let asset = AVURLAsset(url: url)
        if let text = try? await asset.load(.lyrics), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LRCParser.parse(text)
        }
        // iTunes ©lyr and ID3 USLT are exposed as native metadata on some files.
        for format in (try? await asset.load(.availableMetadataFormats)) ?? [] {
            for item in (try? await asset.loadMetadata(for: format)) ?? [] {
                let key = item.identifier?.rawValue ?? String(describing: item.key)
                guard key.contains("©lyr") || key.contains("USLT") || key.lowercased().contains("lyrics") else { continue }
                if let text = try? await item.load(.stringValue) {
                    let lyrics = LRCParser.parse(text)
                    if !lyrics.isEmpty { return lyrics }
                }
            }
        }
        return nil
    }
}
