import Foundation

/// Repair a stale path only when its full audio/tag identity has one live match.
/// This is not content deduplication: two existing copies are always retained.
public enum LibraryReconciliation {
    private struct Identity: Hashable {
        let title: String
        let artist: String
        let album: String
        let albumArtist: String?
        let duration: Double
        let sampleRate: Double
        let bitDepth: Int
        let codec: String
        let track: Int?
        let disc: Int?
        init(_ value: Track) {
            title = value.title; artist = value.artist; album = value.album
            albumArtist = value.albumArtist; duration = value.duration
            sampleRate = value.sampleRate; bitDepth = value.bitDepth; codec = value.codec
            track = value.trackNumber; disc = value.discNumber
        }
    }
    private enum Availability { case present, missing, unavailable }
    private static func availability(_ url: URL) -> Availability {
        // An unmounted external volume is unavailable, not a moved/deleted file.
        let components = url.pathComponents
        if components.count > 2, components[1] == "Volumes" {
            let volume = "/Volumes/" + components[2]
            guard FileManager.default.isReadableFile(atPath: volume) else { return .unavailable }
        }
        do {
            // URL resource values can remain cached after a move is reversed.
            let values = try FileManager.default.attributesOfItem(atPath: url.path)
            return values[.type] as? FileAttributeType == .typeRegular ? .present : .unavailable
        } catch {
            let error = error as NSError
            guard error.domain == NSCocoaErrorDomain,
                  [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(error.code) else { return .unavailable }
            return .missing
        }
    }
    public static func replacements(in tracks: [Track]) -> [String: String] {
        var live: [Identity: Set<String>] = [:]
        var missing: [Track] = []
        for track in tracks {
            if Task.isCancelled { return [:] }
            switch availability(track.url) {
            case .present: live[Identity(track), default: []].insert(track.id)
            case .missing: missing.append(track)
            case .unavailable: break
            }
        }
        var result: [String: String] = [:]
        for track in missing {
            if let candidates = live[Identity(track)], candidates.count == 1, let replacement = candidates.first {
                result[track.id] = replacement
            }
        }
        return result
    }
}
