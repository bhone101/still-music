import Foundation

/// Read only the ID3 tag, including SYLT timestamps not exposed by AVFoundation.
enum ID3Lyrics {
    static func read(_ url: URL) -> Lyrics? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let header = try? file.read(upToCount: 10), header.count == 10,
              header.prefix(3) == Data("ID3".utf8), (2...4).contains(header[3]) else { return nil }
        let version = header[3]
        let size = number(Array(header[6..<10]), syncsafe: true)
        guard size <= 16 * 1024 * 1024, let raw = try? file.read(upToCount: size), raw.count == size else { return nil }
        var bytes = Array(raw)
        if version < 4, header[5] & 0x80 != 0 { bytes = unsynchronize(bytes) }
        if version == 2, header[5] & 0x40 != 0 { return nil }
        var cursor = 0
        if version > 2, header[5] & 0x40 != 0 {
            guard bytes.count >= 4 else { return nil }
            cursor = number(Array(bytes[0..<4]), syncsafe: version == 4) + (version == 3 ? 4 : 0)
            guard cursor >= 4, cursor <= bytes.count else { return nil }
        }
        var plain: Lyrics?
        let frameHeader = version == 2 ? 6 : 10
        let audioPrefix = Array((try? file.read(upToCount: 4096)) ?? Data())
        while cursor + frameHeader <= bytes.count {
            let idLength = version == 2 ? 3 : 4
            let id = String(bytes: bytes[cursor..<cursor + idLength], encoding: .ascii) ?? ""
            if bytes[cursor] == 0 { break }
            let length = number(Array(bytes[cursor + idLength..<cursor + (version == 2 ? 6 : 8)]), syncsafe: version == 4)
            let flags = version == 2 ? 0 : bytes[cursor + 9]
            cursor += frameHeader
            guard length > 0, length <= bytes.count - cursor else { break }
            var body = Array(bytes[cursor..<cursor + length]); cursor += length
            guard ["USLT", "SYLT", "ULT", "SLT"].contains(id) else { continue }
            // Compressed/encrypted lyrics aren't safe to interpret as text.
            if version == 3, flags & 0xc0 != 0 { continue }
            if version == 4, flags & 0x0c != 0 { continue }
            if version == 4, flags & 0x02 != 0 || header[5] & 0x80 != 0 { body = unsynchronize(body) }
            if (version == 3 && flags & 0x20 != 0) || (version == 4 && flags & 0x40 != 0) { if !body.isEmpty { body.removeFirst() } }
            if version == 4, flags & 0x01 != 0 { guard body.count >= 4 else { continue }; body.removeFirst(4) }
            guard body.count >= 4, body[0] <= 3 else { continue }
            let encoding = body[0]
            let synced = id == "SYLT" || id == "SLT"
            var index = synced ? 6 : 4
            guard index <= body.count else { continue }
            var utf16: String.Encoding = .utf16LittleEndian
            func decode(_ bytes: [UInt8]) -> String {
                if encoding == 1, bytes.starts(with: [0xfe, 0xff]) { utf16 = .utf16BigEndian }
                if encoding == 1, bytes.starts(with: [0xff, 0xfe]) { utf16 = .utf16LittleEndian }
                let charset: String.Encoding = encoding == 0 ? .isoLatin1 : encoding == 3 ? .utf8 : encoding == 2 ? .utf16BigEndian : utf16
                return (String(data: Data(bytes), encoding: charset) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
            }
            func terminated() -> String? {
                let start = index
                let step = encoding == 1 || encoding == 2 ? 2 : 1
                while index + step <= body.count {
                    if body[index] == 0 && (step == 1 || body[index + 1] == 0) {
                        let text = decode(Array(body[start..<index])); index += step; return text
                    }
                    index += step
                }
                return nil
            }
            guard terminated() != nil else { continue } // content descriptor
            if synced {
                let unit = body[4]
                guard unit == 1 || unit == 2 else { continue }
                let secondsPerFrame = unit == 1 ? frameDuration(audioPrefix) : 0.001
                guard let secondsPerFrame else { continue }
                var lines: [Lyrics.Line] = []
                while index < body.count {
                    guard let text = terminated(), index + 4 <= body.count else { break }
                    let time = Double(number(Array(body[index..<index + 4]), syncsafe: false)) * secondsPerFrame
                    index += 4
                    lines.append(.init(time: time, text: text.trimmingCharacters(in: .newlines)))
                }
                if !lines.isEmpty { return Lyrics(lines: lines) }
            } else {
                let lyrics = LRCParser.parse(decode(Array(body[index...])))
                if !lyrics.isEmpty { plain = plain ?? lyrics }
            }
        }
        return plain
    }
    private static func number(_ bytes: [UInt8], syncsafe: Bool) -> Int {
        bytes.reduce(0) { ($0 << (syncsafe ? 7 : 8)) | Int($1 & (syncsafe ? 0x7f : 0xff)) }
    }
    private static func unsynchronize(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        for (i, byte) in bytes.enumerated() {
            if byte == 0, i > 0, bytes[i - 1] == 0xff { continue }
            result.append(byte)
        }
        return result
    }
    private static func frameDuration(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 4 else { return nil }
        for i in 0..<bytes.count - 3 {
            guard bytes[i] == 0xff, bytes[i + 1] & 0xe0 == 0xe0 else { continue }
            let version = (bytes[i + 1] >> 3) & 3, layer = (bytes[i + 1] >> 1) & 3
            let rateIndex = Int((bytes[i + 2] >> 2) & 3)
            guard version != 1, layer != 0, rateIndex < 3, bytes[i + 2] >> 4 != 15 else { continue }
            let rate = Double([44100, 48000, 32000][rateIndex]) / (version == 3 ? 1 : version == 2 ? 2 : 4)
            let samples = layer == 3 ? 384 : layer == 1 && version != 3 ? 576 : 1152
            return Double(samples) / rate
        }
        return nil
    }
}
