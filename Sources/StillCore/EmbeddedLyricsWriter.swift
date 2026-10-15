import Foundation
import StillTagBridge

public enum EmbeddedLyricsWriter {
    public enum WriteError: LocalizedError {
        case unsupported, readOnly, changed, invalidText, library(String)
        public var errorDescription: String? {
            switch self {
            case .unsupported: return "Embedded lyrics editing supports FLAC, MP3 and M4A files."
            case .readOnly: return "The audio file is read-only."
            case .changed: return "The audio file changed during the edit. It was not replaced."
            case .invalidText: return "Lyrics must be valid text smaller than 8 MB without null characters."
            case .library(let message): return message
            }
        }
    }

    public static func supports(_ url: URL) -> Bool {
        ["flac", "mp3", "m4a", "mp4"].contains(url.pathExtension.lowercased())
    }

    /// TagLib edits only a disposable copy. Publish it atomically after success.
    /// No decoding, encoding, normalization, or changes to audio samples occur.
    public static func write(_ lyrics: Lyrics?, to source: URL) throws {
        guard source.isFileURL, supports(source) else { throw WriteError.unsupported }
        let url = source.resolvingSymlinksInPath()
        let format = source.pathExtension.lowercased()
        let text: String?
        if let lyrics {
            let data = try LyricsWriter.encode(lyrics)
            guard data.count <= 8 * 1024 * 1024, !data.contains(0),
                  let value = String(data: data, encoding: .utf8) else { throw WriteError.invalidText }
            text = value
        } else { text = nil }
        let fm = FileManager.default
        let before = try fm.attributesOfItem(atPath: url.path)
        let mode = (before[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard mode & 0o222 != 0, fm.isWritableFile(atPath: url.path) else { throw WriteError.readOnly }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".still-lyrics-\(UUID().uuidString).\(format)")
        defer { try? fm.removeItem(at: temporary) }
        try Task.checkCancellation()
        try fm.copyItem(at: url, to: temporary)
        var error = [CChar](repeating: 0, count: 512)
        let success = temporary.path.withCString { path in
            format.withCString { format in
                if let text {
                    return text.withCString { still_write_lyrics(path, format, $0, &error, error.count) }
                }
                return still_write_lyrics(path, format, nil, &error, error.count)
            }
        }
        guard success == 1 else { throw WriteError.library(String(cString: error)) }
        let output = try FileHandle(forWritingTo: temporary)
        try output.synchronize()
        try output.close()
        try Task.checkCancellation()
        let after = try fm.attributesOfItem(atPath: url.path)
        guard before[.size] as? NSNumber == after[.size] as? NSNumber,
              before[.modificationDate] as? Date == after[.modificationDate] as? Date,
              before[.systemFileNumber] as? NSNumber == after[.systemFileNumber] as? NSNumber else { throw WriteError.changed }
        _ = try fm.replaceItemAt(url, withItemAt: temporary)
    }
}
