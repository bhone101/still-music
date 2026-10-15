import Foundation
import ImageIO

public enum FLACArtworkWriter {
    public enum WriteError: LocalizedError {
        case unsupported, invalidFile, invalidImage, changed, readOnly
        public var errorDescription: String? {
            switch self {
            case .unsupported: return "Writing covers is supported for FLAC files only."
            case .invalidFile: return "The FLAC metadata is invalid or too large."
            case .invalidImage: return "Choose a JPEG or PNG cover smaller than 16 MB."
            case .changed: return "The song changed during the write. Its cover was not replaced."
            case .readOnly: return "The song is read-only."
            }
        }
    }
    /// Replace only front-cover PICTURE blocks. STREAMINFO, tags, other pictures,
    /// and audio frames are copied byte-for-byte to an adjacent temporary file.
    public static func write(_ image: Data, to url: URL) throws {
        guard url.pathExtension.lowercased() == "flac" else { throw WriteError.unsupported }
        guard image.count < 16 * 1024 * 1024 - 128,
              let source = CGImageSourceCreateWithData(image as CFData, nil),
              let type = CGImageSourceGetType(source) as String?, ["public.jpeg", "public.png"].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192 else { throw WriteError.invalidImage }
        let fm = FileManager.default
        let attributes = try fm.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard permissions & 0o222 != 0, fm.isWritableFile(atPath: url.path) else { throw WriteError.readOnly }
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        guard try input.read(upToCount: 4) == Data("fLaC".utf8) else { throw WriteError.invalidFile }
        var blocks: [(UInt8, Data)] = []
        var last = false, total = 0
        while !last {
            guard blocks.count < 1024, let header = try input.read(upToCount: 4), header.count == 4 else { throw WriteError.invalidFile }
            let kind = header[0] & 0x7f
            last = header[0] & 0x80 != 0
            let size = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            total += size
            guard total <= 64 * 1024 * 1024, let body = try input.read(upToCount: size), body.count == size else { throw WriteError.invalidFile }
            let front = kind == 6 && body.count >= 4 && body.prefix(4) == Data([0, 0, 0, 3])
            if !front { blocks.append((kind, body)) }
        }
        guard blocks.first?.0 == 0, blocks.first?.1.count == 34 else { throw WriteError.invalidFile }
        var picture = Data()
        func number(_ n: Int) { var value = UInt32(n).bigEndian; withUnsafeBytes(of: &value) { picture.append(contentsOf: $0) } }
        number(3)
        let mime = Data((type == "public.png" ? "image/png" : "image/jpeg").utf8)
        number(mime.count); picture.append(mime); number(0)
        let depth = properties[kCGImagePropertyDepth] as? Int ?? 8
        let channels = (properties[kCGImagePropertyColorModel] as? String == "Gray" ? 1 : 3) + ((properties[kCGImagePropertyHasAlpha] as? Bool == true) ? 1 : 0)
        number(width); number(height); number(depth * channels); number(0); number(image.count); picture.append(image)
        blocks.append((6, picture))
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".still-cover-\(UUID().uuidString)")
        guard fm.createFile(atPath: temporary.path, contents: nil) else { throw WriteError.readOnly }
        defer { try? fm.removeItem(at: temporary) }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        try output.write(contentsOf: Data("fLaC".utf8))
        for (index, block) in blocks.enumerated() {
            let size = block.1.count
            try output.write(contentsOf: Data([block.0 | (index == blocks.count - 1 ? 0x80 : 0), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255)]))
            try output.write(contentsOf: block.1)
        }
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            if Task.isCancelled { throw CancellationError() }
            try output.write(contentsOf: chunk)
        }
        try output.synchronize()
        try output.close()
        let now = try fm.attributesOfItem(atPath: url.path)
        guard now[.size] as? NSNumber == attributes[.size] as? NSNumber,
              now[.modificationDate] as? Date == attributes[.modificationDate] as? Date else { throw WriteError.changed }
        try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path)
        if Task.isCancelled { throw CancellationError() }
        _ = try fm.replaceItemAt(url, withItemAt: temporary)
    }
}
