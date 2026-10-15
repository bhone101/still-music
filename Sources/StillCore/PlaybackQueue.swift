import Foundation

public struct PlaybackQueue {
    public struct Entry: Identifiable, Equatable {
        public let id = UUID()
        public fileprivate(set) var trackID: String
    }
    public private(set) var items: [Entry] = []
    public private(set) var currentIndex = 0
    public private(set) var isShuffled = false
    public private(set) var isLooping = false
    private var order: [UUID] = []
    public var current: Entry? { items.indices.contains(currentIndex) ? items[currentIndex] : nil }
    public var upcoming: [Entry] { Array(items.dropFirst(currentIndex + 1)) }
    public var nextEntry: Entry? { hasNext ? items[(currentIndex + 1) % items.count] : nil }
    public var hasNext: Bool { currentIndex + 1 < items.count || (isLooping && !items.isEmpty) }

    public init() {}
    public mutating func reset(_ ids: [String], startingAt id: String) {
        items = ids.map { Entry(trackID: $0) }
        if !ids.contains(id) { items.insert(Entry(trackID: id), at: 0) }
        currentIndex = items.firstIndex { $0.trackID == id } ?? 0
        order = items.map(\.id)
        if isShuffled {
            let selected = items.remove(at: currentIndex)
            items.shuffle()
            items.insert(selected, at: 0)
            currentIndex = 0
        }
    }
    public mutating func enqueue(_ id: String, next: Bool) {
        let entry = Entry(trackID: id)
        let index = next ? min(currentIndex + 1, items.count) : items.count
        items.insert(entry, at: index)
        if next, let current, let original = order.firstIndex(of: current.id) { order.insert(entry.id, at: original + 1) }
        else { order.append(entry.id) }
    }
    public mutating func cycleMode() {
        if isShuffled {
            toggleShuffle()
            isLooping = true
        } else if isLooping {
            isLooping = false
        } else {
            toggleShuffle()
        }
    }
    public mutating func toggleShuffle() {
        isShuffled.toggle()
        guard current != nil else { return }
        var tail = upcoming
        if isShuffled { tail.shuffle() }
        else {
            let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
            tail.sort { positions[$0.id, default: 0] < positions[$1.id, default: 0] }
        }
        items = Array(items.prefix(currentIndex + 1)) + tail
    }
    @discardableResult public mutating func advance() -> String? {
        guard hasNext else { return nil }
        currentIndex = (currentIndex + 1) % items.count
        return current?.trackID
    }
    @discardableResult public mutating func previous() -> String? {
        guard currentIndex > 0 else { return nil }
        currentIndex -= 1
        return current?.trackID
    }
    public mutating func jump(to entryID: UUID) -> String? {
        guard let index = items.firstIndex(where: { $0.id == entryID }) else { return nil }
        currentIndex = index
        return current?.trackID
    }
    public mutating func removeUpcoming(_ entryID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == entryID }), index > currentIndex else { return }
        items.remove(at: index)
        order.removeAll { $0 == entryID }
    }
    public mutating func reconcilePaths(_ replacements: [String: String]) {
        // Keep occurrence IDs, queue order, and intentionally repeated entries.
        for index in items.indices {
            if let replacement = replacements[items[index].trackID] { items[index].trackID = replacement }
        }
    }
    public mutating func clearUpcoming() {
        items = Array(items.prefix(currentIndex + 1))
        let remaining = Set(items.map(\.id))
        order.removeAll { !remaining.contains($0) }
        // Clear All means playback ends after this song, even in loop mode.
        isLooping = false
    }
    public mutating func moveUpcoming(_ entryIDs: [UUID], before destination: UUID?) {
        let ids = Set(entryIDs)
        let moving = upcoming.filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return }
        var tail = upcoming.filter { !ids.contains($0.id) }
        let index: Int
        if let destination {
            guard let target = tail.firstIndex(where: { $0.id == destination }) else { return }
            index = target
        } else { index = tail.count }
        tail.insert(contentsOf: moving, at: index)
        items = Array(items.prefix(currentIndex + 1)) + tail
        // A manual order becomes the baseline when shuffle is switched off.
        order = items.map(\.id)
    }
    public mutating func remove(_ trackID: String) {
        let before = items.prefix(currentIndex).filter { $0.trackID == trackID }.count
        items.removeAll { $0.trackID == trackID }
        currentIndex = max(0, currentIndex - before)
        let remaining = Set(items.map(\.id))
        order.removeAll { !remaining.contains($0) }
    }
}
