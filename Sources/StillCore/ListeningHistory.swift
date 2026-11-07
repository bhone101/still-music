import Foundation

/// Local qualified listens, retained for the rolling On Repeat window.
public struct ListeningHistory: Codable {
    public struct Play: Codable {
        public var trackID: String
        public var date: Date
    }
    public private(set) var plays: [Play] = []
    public init() {}
    public mutating func record(_ trackID: String, at now: Date = Date()) {
        prune(at: now)
        plays.append(Play(trackID: trackID, date: now))
    }
    public mutating func prune(at now: Date = Date()) {
        plays.removeAll { $0.date <= now.addingTimeInterval(-30 * 86400) || $0.date > now }
    }
    public mutating func reconcilePaths(_ replacements: [String: String]) {
        for index in plays.indices { plays[index].trackID = replacements[plays[index].trackID] ?? plays[index].trackID }
    }
    public func rankedIDs(available: Set<String>, at now: Date = Date(), limit: Int = 30) -> [String] {
        let recent = plays.filter {
            available.contains($0.trackID) && $0.date > now.addingTimeInterval(-30 * 86400) && $0.date <= now
        }
        let groups = Dictionary(grouping: recent, by: \.trackID)
        return groups.keys.sorted {
            let left = groups[$0]!, right = groups[$1]!
            if left.count != right.count { return left.count > right.count }
            let a = left.map(\.date).max()!, b = right.map(\.date).max()!
            return a == b ? $0 < $1 : a > b
        }.prefix(max(0, limit)).map { $0 }
    }
}

/// Counts audible progress once per playback session; skips, pauses and seeks add no time.
public struct ListenSession {
    private var seconds: Double = 0
    private var counted = false
    private var previous: (position: Double, uptime: Double)?
    public init() {}
    public mutating func reset() { self = ListenSession() }
    public mutating func interrupt() { previous = nil }
    public mutating func observe(position: Double, duration: Double, playing: Bool, uptime: Double) -> Bool {
        guard playing, position.isFinite, duration.isFinite, duration > 0 else {
            interrupt()
            return false
        }
        defer { previous = (position, uptime) }
        guard !counted, let previous else { return false }
        let progress = position - previous.position, elapsed = uptime - previous.uptime
        guard elapsed > 0, elapsed < 2, progress > 0, progress <= elapsed + 0.5 else { return false }
        seconds += min(progress, elapsed)
        if seconds >= min(30, duration / 2) {
            counted = true
            return true
        }
        return false
    }
}
