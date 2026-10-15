import Foundation

enum EmbeddedArtwork {
    /// FLAC PICTURE blocks, preferring the front cover (type 3). Skip audio and
    /// unrelated metadata rather than reading a high-resolution song into RAM.
    static func flac(_ url: URL) throws -> Data? {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard try file.read(upToCount: 4) == Data("fLaC".utf8) else { return nil }
        var fallback: Data?
        for _ in 0..<1024 {
            guard let header = try file.read(upToCount: 4), header.count == 4 else { break }
            let size = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            if header[0] & 0x7f == 6 {
                guard let block = try file.read(upToCount: size), block.count == size else { break }
                if let picture = picture(block) {
                    if picture.type == 3 { return picture.data }
                    if fallback == nil { fallback = picture.data }
                }
            } else {
                try file.seek(toOffset: file.offset() + UInt64(size))
            }
            if header[0] & 0x80 != 0 { break }
        }
        return fallback
    }

    private static func picture(_ block: Data) -> (type: Int, data: Data)? {
        var cursor = 0
        func number() -> Int? {
            guard cursor <= block.count - 4 else { return nil }
            let result = (0..<4).reduce(0) { ($0 << 8) | Int(block[cursor + $1]) }
            cursor += 4
            return result
        }
        func bytes() -> Data? {
            guard let size = number(), size <= block.count - cursor else { return nil }
            defer { cursor += size }
            return block.subdata(in: cursor..<(cursor + size))
        }
        guard let type = number(), let mime = bytes(), mime != Data("-->".utf8),
              bytes() != nil else { return nil }
        for _ in 0..<4 { guard number() != nil else { return nil } }
        guard let image = bytes(), !image.isEmpty else { return nil }
        return (type, image)
    }
}
