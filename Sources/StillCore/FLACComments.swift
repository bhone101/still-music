import Foundation

/// Read Vorbis comments directly because AVFoundation does not expose all FLAC
/// tags consistently. Audio frames and large embedded pictures are never loaded.
enum FLACComments {
    static func read(_ url: URL) throws -> [String: [String]] {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard try file.read(upToCount: 4) == Data("fLaC".utf8) else { return [:] }
        for _ in 0..<1024 {
            guard let header = try file.read(upToCount: 4), header.count == 4 else { return [:] }
            let size = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            if header[0] & 0x7f == 4 {
                guard size <= 8 * 1024 * 1024, let payload = try file.read(upToCount: size), payload.count == size else { return [:] }
                return parse(payload)
            }
            if header[0] & 0x80 != 0 { break }
            try file.seek(toOffset: file.offset() + UInt64(size))
        }
        return [:]
    }

    static func parse(_ data: Data) -> [String: [String]] {
        var cursor = 0
        func length() -> Int? {
            guard cursor <= data.count - 4 else { return nil }
            let n = (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[cursor + $1]) << ($1 * 8) }
            cursor += 4
            return Int(n)
        }
        func string() -> String? {
            guard let count = length(), count <= data.count - cursor else { return nil }
            defer { cursor += count }
            return String(data: data[cursor..<(cursor + count)], encoding: .utf8)
        }
        guard string() != nil, let count = length(), count <= 100_000 else { return [:] }
        var tags: [String: [String]] = [:]
        for _ in 0..<count {
            guard let value = string() else { return tags }
            guard let separator = value.firstIndex(of: "=") else { continue }
            let key = value[..<separator].uppercased()
            let text = value[value.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { tags[key, default: []].append(text) }
        }
        return tags
    }
}
