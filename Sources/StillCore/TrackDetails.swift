import AVFoundation
import Foundation

/// On-demand information for the read-only sheet; never persisted to the library.
public struct TrackDetails: Sendable {
    public var channels: Int?
    public var fileSize: Int64?
    public var date: String?
    public var taggedTitle: String?
    public var taggedArtist: String?

    public static func read(for track: Track) async -> Self {
        var result = Self()
        result.fileSize = (try? FileManager.default.attributesOfItem(atPath: track.url.path)[.size] as? NSNumber)?.int64Value
        if let file = try? AVAudioFile(forReading: track.url) {
            let channels = Int(file.fileFormat.channelCount)
            if channels > 0 { result.channels = channels }
        }
        // Date isn't in Track. Reuse the existing Vorbis reader and native
        // metadata APIs without changing Track's Codable representation.
        let comments = (try? FLACComments.read(track.url)) ?? [:]
        let asset = AVURLAsset(url: track.url)
        var metadata = (try? await asset.load(.commonMetadata)) ?? []
        for format in (try? await asset.load(.availableMetadataFormats)) ?? [] {
            metadata += (try? await asset.loadMetadata(for: format)) ?? []
        }
        func text(_ identifiers: [AVMetadataIdentifier], commonKey: AVMetadataKey? = nil) async -> String? {
            for item in metadata where identifiers.contains(item.identifier ?? AVMetadataIdentifier(rawValue: "")) || (commonKey != nil && item.commonKey == commonKey) {
                if let value = try? await item.load(.stringValue) {
                    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty { return clean }
                }
            }
            return nil
        }
        result.date = comments["DATE"]?.first ?? comments["YEAR"]?.first
        if result.date == nil {
            result.date = await text([.iTunesMetadataReleaseDate, .id3MetadataRecordingTime, .id3MetadataYear], commonKey: .commonKeyCreationDate)
        }
        // Resolve only the two model fallbacks so absent tags can be omitted.
        if track.title == track.url.deletingPathExtension().lastPathComponent {
            result.taggedTitle = comments["TITLE"]?.joined(separator: "; ")
            if result.taggedTitle == nil { result.taggedTitle = await text([], commonKey: .commonKeyTitle) }
        } else { result.taggedTitle = track.title }
        if track.artist == "Unknown artist" {
            result.taggedArtist = comments["ARTIST"]?.joined(separator: "; ")
            if result.taggedArtist == nil { result.taggedArtist = await text([], commonKey: .commonKeyArtist) }
        } else { result.taggedArtist = track.artist }
        return result
    }
}
