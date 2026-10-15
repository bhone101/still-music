import Foundation

/// An allowlist of numeric audio state, never URLs, tags, device names, or error
/// descriptions. Keep privacy at collection time, not just during export.
@MainActor public final class AudioDiagnostics {
    public enum Event: String, Codable {
        case sessionStarted, engineStarted, engineConfigurationChanged, deviceChanged
        case playbackPaused, playbackStopped, playbackFailed, gaplessAdvance, queueEdited
        case rateObserved, rateRequested, rateConfirmed, rateFailed, rateRestored, restoreFailed
    }
    public struct Entry: Codable {
        public let time: Date
        public let event: Event
        public let device: UInt32?
        public let sourceRate: Double?
        public let outputRate: Double?
        public let status: Int?
    }
    public struct Report: Codable {
        public let schemaVersion: Int
        public let entries: [Entry]
    }
    public private(set) var entries: [Entry] = []
    private let capacity: Int
    private let storageURL: URL?
    private let writer = DispatchQueue(label: "Still.audioDiagnostics", qos: .utility)

    public init(storageURL: URL? = nil, capacity: Int = 256) {
        self.storageURL = storageURL
        self.capacity = max(1, min(capacity, 256))
        // Reject oversized/corrupt logs; diagnostics must never prevent playback.
        if let storageURL,
           let size = try? storageURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 131072,
           let data = try? Data(contentsOf: storageURL),
           let report = try? JSONDecoder().decode(Report.self, from: data), report.schemaVersion == 1 {
            entries = Array(report.entries.suffix(self.capacity))
        }
    }

    public func record(_ event: Event, device: UInt32? = nil, sourceRate: Double? = nil,
                       outputRate: Double? = nil, status: Int? = nil) {
        entries.append(Entry(time: Date(), event: event, device: device,
                             sourceRate: sourceRate.flatMap { $0.isFinite ? $0 : nil },
                             outputRate: outputRate.flatMap { $0.isFinite ? $0 : nil }, status: status))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
        guard let storageURL, let data = try? exportData() else { return }
        // Serial atomic writes keep snapshots ordered and disk I/O off the audio/UI threads.
        writer.async {
            try? FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    public static func statusCode(_ error: Error) -> Int {
        if let rate = error as? RateError {
            switch rate {
            case .status(let value): return Int(value)
            case .timeout: return -1
            case .deviceChanged: return -2
            }
        }
        return (error as NSError).code
    }

    public func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Report(schemaVersion: 1, entries: entries))
    }

    public func flush() async {
        await withCheckedContinuation { continuation in writer.async { continuation.resume() } }
    }
}
