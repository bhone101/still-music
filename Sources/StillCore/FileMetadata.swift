import Foundation
import ImageIO
import StillTagBridge

public enum FileMetadata {
    public static let fields = [
        "TITLE", "ARTIST", "ALBUM", "ALBUMARTIST", "TRACKNUMBER", "DISCNUMBER", "GENRE", "DATE", "COMPOSER",
    ]
    public static func supports(_ url: URL) -> Bool { EmbeddedLyricsWriter.supports(url) }
    public static func read(_ key: String, from url: URL) -> String? {
        var buffer = [CChar](repeating: 0, count: 65536)
        let ok = url.path.withCString { path in key.withCString { still_read_property(path, $0, &buffer, buffer.count) }
        }
        guard ok == 1 else { return nil }
        let value = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    public static func write(_ fields: [String: String], to url: URL) throws {
        guard supports(url), fields.keys.allSatisfy({ Self.fields.contains($0) }),
            fields.values.allSatisfy({ !$0.contains("\0") && $0.utf8.count < 65536 })
        else {
            throw failure("Unsupported file or invalid metadata. Edit FLAC, MP3 or M4A files.")
        }
        for key in ["TRACKNUMBER", "DISCNUMBER", "DATE"] {
            if let value = fields[key], !value.isEmpty, (Int(value) == nil || Int(value)! < 0) {
                throw failure("Track, disc and year must be nonnegative whole numbers.")
            }
        }
        try editCopy(of: url) { copy in
            for (key, value) in fields {
                let ok = copy.path.withCString { path in
                    key.withCString { key in value.withCString { still_write_property(path, key, $0) } }
                }
                guard ok == 1 else { throw failure("Couldn’t write \(key). The original file was kept.") }
            }
        }
    }
    public static func writeArtwork(_ data: Data, to url: URL) throws {
        guard supports(url), data.count <= 16 * 1024 * 1024,
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let type = CGImageSourceGetType(source) as String?, ["public.jpeg", "public.png"].contains(type)
        else {
            throw failure("Choose a JPEG or PNG under 16 MB for a FLAC, MP3 or M4A file.")
        }
        try editCopy(of: url) { copy in
            let ok = data.withUnsafeBytes { raw in
                copy.path.withCString { path in
                    url.pathExtension.lowercased().withCString {
                        still_write_artwork(
                            path, $0, raw.bindMemory(to: UInt8.self).baseAddress, data.count,
                            type == "public.png" ? 1 : 0)
                    }
                }
            }
            guard ok == 1 else { throw failure("Couldn’t write artwork. The original file was kept.") }
        }
    }
    private static func failure(_ text: String) -> NSError {
        NSError(domain: "StillMetadata", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
    private static func editCopy(of source: URL, edit: (URL) throws -> Void) throws {
        let url = source.resolvingSymlinksInPath(), fm = FileManager.default
        let before = try fm.attributesOfItem(atPath: url.path)
        guard ((before[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o222 != 0,
            fm.isWritableFile(atPath: url.path)
        else { throw EmbeddedLyricsWriter.WriteError.readOnly }
        let copy = url.deletingLastPathComponent().appendingPathComponent(
            ".still-edit-\(UUID()).\(source.pathExtension)")
        defer { try? fm.removeItem(at: copy) }
        try Task.checkCancellation()
        try fm.copyItem(at: url, to: copy)
        try edit(copy)
        let handle = try FileHandle(forWritingTo: copy)
        try handle.synchronize()
        try handle.close()
        try Task.checkCancellation()
        let after = try fm.attributesOfItem(atPath: url.path)
        guard before[.size] as? NSNumber == after[.size] as? NSNumber,
            before[.modificationDate] as? Date == after[.modificationDate] as? Date,
            before[.systemFileNumber] as? NSNumber == after[.systemFileNumber] as? NSNumber
        else {
            throw EmbeddedLyricsWriter.WriteError.changed
        }
        _ = try fm.replaceItemAt(url, withItemAt: copy)
    }
}
