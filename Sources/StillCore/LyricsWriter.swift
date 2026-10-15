import Foundation
import Darwin

public enum LyricsWriter {
    public static func sidecarURL(for audioURL: URL, lyrics: Lyrics? = nil) -> URL {
        audioURL.deletingPathExtension().appendingPathExtension(lyrics?.lines.isEmpty == true ? "txt" : "lrc")
    }

    public static func write(_ lyrics: Lyrics, beside audioURL: URL, replace: Bool = false) throws {
        guard audioURL.isFileURL else { throw CocoaError(.fileWriteInvalidFileName) }
        try writeData(encode(lyrics), to: sidecarURL(for: audioURL, lyrics: lyrics), replace: replace)
    }

    public static func encode(_ lyrics: Lyrics) throws -> Data {
        guard !lyrics.isEmpty,
              lyrics.lines.allSatisfy({ $0.time.isFinite && abs($0.time) < 1_000_000_000 }) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        if lyrics.lines.isEmpty {
            guard !lyrics.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            return Data((lyrics.plainText + "\n").utf8)
        }
        let milliseconds = lyrics.lines.map { Int64(($0.time * 1000).rounded()) }
        let offset = max(0, -(milliseconds.min() ?? 0))
        var rows = offset > 0 ? ["[offset:\(offset)]"] : []
        for (line, milliseconds) in zip(lyrics.lines, milliseconds) {
            let time = milliseconds + offset
            let stamp = String(format: "[%02lld:%02lld.%03lld]", time / 60_000, (time / 1000) % 60, time % 1000)
            rows.append(stamp + line.text.components(separatedBy: .newlines).joined(separator: " "))
        }
        return Data((rows.joined(separator: "\n") + "\n").utf8)
    }

    /// Automatic saves never replace an existing sidecar, including empty files and symlinks.
    @discardableResult
    public static func saveIfMissing(_ lyrics: Lyrics, beside audioURL: URL) throws -> Bool {
        guard !lyrics.isEmpty else { return false }
        do {
            try write(lyrics, beside: audioURL)
            return true
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            return false
        }
    }

    private static func writeData(_ data: Data, to destination: URL, replace: Bool) throws {
        if replace { try data.write(to: destination, options: .atomic); return }
        // Publish a complete sidecar without an existence-check/overwrite race.
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".still-lyrics-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        if renamex_np(temporary.path, destination.path, UInt32(RENAME_EXCL)) != 0 {
            let code = errno
            if code == EEXIST { throw CocoaError(.fileWriteFileExists) }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
    }
}
