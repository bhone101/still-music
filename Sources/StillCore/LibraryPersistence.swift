import Foundation

public struct PlaybackPosition: Codable, Sendable {
    public var currentID: String?
    public var position: Double
    public init(currentID: String?, position: Double) {
        self.currentID = currentID
        self.position = position
    }
    public static func file(beside library: URL) -> URL {
        library.deletingPathExtension().appendingPathExtension("position.json")
    }
    public static func load(beside library: URL) throws -> Self? {
        let url = file(beside: library)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

/// One writer preserves submission order. Playhead checkpoints never encode the
/// library. A flush waits for pending writes without blocking the main actor.
public final class LibraryPersistence: @unchecked Sendable {
    private let writer = DispatchQueue(label: "Still.library-writer", qos: .utility)
    private let url: URL
    public init(url: URL) { self.url = url }
    public func submit(
        library: LibrarySnapshot?, position: PlaybackPosition,
        completion: @escaping @Sendable (String?) -> Void = { _ in }
    ) {
        writer.async { [url] in
            do {
                if let library { try LibraryStorage.save(library, to: url) }
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(position).write(to: PlaybackPosition.file(beside: url), options: .atomic)
                completion(nil)
            } catch { completion(error.localizedDescription) }
        }
    }
    public func flush() async {
        await withCheckedContinuation { continuation in writer.async { continuation.resume() } }
    }
}
