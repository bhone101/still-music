import AppKit
import ImageIO
import CryptoKit
import StillCore

@MainActor
final class ArtworkStore {
    static let shared = ArtworkStore()
    private final class Entry: NSObject {
        let image: NSImage?
        init(_ image: NSImage?) { self.image = image }
    }
    private let cache = NSCache<NSString, Entry>()
    private var pending: [String: Task<NSImage?, Never>] = [:]

    private var generation = 0
    private var albumFiles: [String: URL] = [:]

    func configure(tracks: [Track], root: URL) {
        albumFiles = Dictionary(tracks.map { track in
            let key = track.album.isEmpty ? track.id : track.album + "\u{001f}" + track.displayAlbumArtist
            let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
            return (track.id, root.appendingPathComponent(hash + ".cover"))
        }, uniquingKeysWith: { first, _ in first })
    }
    func setCover(_ data: Data, tracks: [Track]) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) != nil else {
            throw FLACArtworkWriter.WriteError.invalidImage
        }
        for url in Set(tracks.compactMap { albumFiles[$0.id] }) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        clear()
    }

    private init() {

        cache.totalCostLimit = 64 * 1024 * 1024
        cache.countLimit = 400
    }

    func image(for url: URL) async -> NSImage? {
        let key = url.path
        if let entry = cache.object(forKey: key as NSString) { return entry.image }
        if let task = pending[key] { return await task.value }
        let generation = generation
        let albumFile = albumFiles[key]
        let task = Task {
            let thumbnail = await Task.detached(priority: .utility) { () -> CGImage? in
                let selected = albumFile.flatMap { try? Data(contentsOf: $0) }
                let data: Data?
                if let selected { data = selected } else { data = await Track.artwork(for: url) }
                guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }.value
            return thumbnail.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        }
        pending[key] = task
        let image = await task.value
        if self.generation == generation {
            cache.setObject(Entry(image), forKey: key as NSString, cost: image == nil ? 1 : 512 * 512 * 4)
            pending[key] = nil
        }
        return image
    }

    func clear() {
        generation += 1
        for task in pending.values { task.cancel() }
        pending.removeAll()
        cache.removeAllObjects()
    }
}
