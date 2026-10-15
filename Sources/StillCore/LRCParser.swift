import Foundation

public struct Lyrics: Equatable, Sendable, Codable {
    public struct Line: Equatable, Sendable, Codable {
        public let time: Double
        public let text: String
        public init(time: Double, text: String) { self.time = time; self.text = text }
    }
    public let lines: [Line]
    public let plainText: String
    public var isEmpty: Bool { lines.isEmpty && plainText.isEmpty }
    /// Upgrade plain local lyrics only when the online result has timestamps.
    public func preferringSynced(_ online: Lyrics) -> Lyrics {
        if !lines.isEmpty { return self }
        return !online.lines.isEmpty || isEmpty ? online : self
    }
    public init(lines: [Line] = [], plainText: String = "") {
        self.lines = lines.sorted { $0.time < $1.time }
        self.plainText = plainText
    }
    /// Last line at or before the playback position; nil before the first line.
    public func currentLine(at time: Double) -> Int? {
        guard time.isFinite else { return nil }
        var low = 0, high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time <= time { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? nil : low - 1
    }
}

public enum LRCParser {
    public static func parse(_ text: String) -> Lyrics {
        let timestamp = try! NSRegularExpression(pattern: #"\[(\d+):([0-5]\d)(?:\.(\d{1,3}))?\]"#)
        let metadata = try! NSRegularExpression(pattern: #"\[(?:ar|ti|al|by|re|ve|length|offset):[^\]]*\]"#, options: .caseInsensitive)
        let offsetTag = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        let fullRange = NSRange(text.startIndex..., in: text)
        var offset = 0.0
        if let match = offsetTag.matches(in: text, range: fullRange).last,
           let range = Range(match.range(at: 1), in: text), let ms = Double(text[range]), ms.isFinite { offset = ms / 1000 }
        var lines: [Lyrics.Line] = []
        var plain: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let clean = metadata.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
            let matches = timestamp.matches(in: clean, range: NSRange(clean.startIndex..., in: clean))
            let words = timestamp.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: "").trimmingCharacters(in: .whitespaces)
            if matches.isEmpty {
                if !clean.isEmpty || raw.trimmingCharacters(in: .whitespaces).isEmpty { plain.append(clean) }
                continue
            }
            for match in matches {
                func value(_ index: Int) -> String { Range(match.range(at: index), in: clean).map { String(clean[$0]) } ?? "" }
                let fraction = value(3)
                let time = (Double(value(1)) ?? 0) * 60 + (Double(value(2)) ?? 0) + (Double("0." + fraction) ?? 0) - offset
                if time.isFinite { lines.append(.init(time: time, text: words)) }
            }
        }
        return Lyrics(lines: lines, plainText: lines.isEmpty ? plain.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) : "")
    }
}
