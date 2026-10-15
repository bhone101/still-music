import AVFoundation
import Foundation

public struct Track: Codable, Identifiable, Equatable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double
    public let sampleRate: Double
    public let bitDepth: Int
    public let codec: String
    public var albumArtist: String? = nil
    public var genre: String? = nil
    public var composer: String? = nil
    public var trackNumber: Int? = nil
    public var discNumber: Int? = nil
    public var metadataVersion: Int? = nil
    public var bitRate: Int? = nil
    public var bitRateLabel: String {
        guard let bitRate, bitRate > 0 else { return "—" }
        return "\(Int((Double(bitRate) / 1000).rounded())) kbps"
    }
    public var displayAlbumArtist: String { albumArtist ?? artist }

    public var quality: String {
        var parts = [codec]
        if bitDepth > 0 { parts.append("\(bitDepth)-bit") }
        if sampleRate > 0 {
            parts.append(String(format: sampleRate.truncatingRemainder(dividingBy: 1000) == 0 ? "%.0f kHz" : "%.1f kHz", sampleRate / 1000))
        }
        return parts.joined(separator: " · ")
    }

    public static let extensions: Set<String> = ["flac", "mp3", "m4a", "aac", "wav", "wave", "aif", "aiff", "aifc", "caf", "mp4"]

    public static func read(_ url: URL) async throws -> Track {
        let file = try AVAudioFile(forReading: url)
        let format = file.fileFormat
        let description = format.streamDescription.pointee
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard duration.isFinite, duration > 0 else { throw AudioError.emptyFile }

        let asset = AVURLAsset(url: url)
        var metadata = (try? await asset.load(.commonMetadata)) ?? []
        for metadataFormat in (try? await asset.load(.availableMetadataFormats)) ?? [] {
            metadata += (try? await asset.loadMetadata(for: metadataFormat)) ?? []
        }
        let comments = (try? FLACComments.read(url)) ?? [:]
        func tag(_ names: String...) -> String? {
            names.compactMap { comments[$0]?.joined(separator: "; ") }.first
        }
        func identified(_ identifiers: AVMetadataIdentifier...) async -> String? {
            for identifier in identifiers {
                for item in metadata where item.identifier == identifier {
                    if let value = try? await item.load(.stringValue) {
                        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty { return clean }
                    }
                }
            }
            return nil
        }
        func text(_ key: AVMetadataKey) async -> String? {
            guard let item = metadata.first(where: { $0.commonKey == key }),
                  let value = try? await item.load(.stringValue) else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let nativeTitle = await text(.commonKeyTitle)
        let nativeArtist = await text(.commonKeyArtist)
        let nativeAlbum = await text(.commonKeyAlbumName)
        let nativeAlbumArtist = await identified(.iTunesMetadataAlbumArtist, .id3MetadataBand)
        let nativeGenre = await identified(.iTunesMetadataUserGenre, .id3MetadataContentType, .quickTimeMetadataGenre, .quickTimeUserDataGenre)
        let nativeComposer = await identified(.iTunesMetadataComposer, .id3MetadataComposer, .quickTimeMetadataComposer, .quickTimeUserDataComposer)
        let nativeTrack = await identified(.id3MetadataTrackNumber)
        let title = tag("TITLE") ?? nativeTitle ?? url.deletingPathExtension().lastPathComponent
        let artist = tag("ARTIST") ?? nativeArtist ?? "Unknown artist"
        let album = tag("ALBUM") ?? nativeAlbum ?? ""
        let codec: String
        switch description.mFormatID {
        case kAudioFormatAppleLossless: codec = "ALAC"
        case kAudioFormatFLAC: codec = "FLAC"
        case kAudioFormatMPEGLayer3: codec = "MP3"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2: codec = "AAC"
        default: codec = url.pathExtension.uppercased()
        }
        // Compressed formats may report zero bits per channel. Read their source
        // depth from AudioFile; never label the decoded float buffer as source depth.
        var depth = description.mBitsPerChannel
        var bitRate: Int?
        var audioFile: AudioFileID?
        if AudioFileOpenURL(url as CFURL, .readPermission, 0, &audioFile) == noErr, let audioFile {
            defer { AudioFileClose(audioFile) }
            var size = UInt32(MemoryLayout<UInt32>.size)
            var sourceDepth: UInt32 = 0
            if AudioFileGetProperty(audioFile, kAudioFilePropertySourceBitDepth, &size, &sourceDepth) == noErr, sourceDepth > 0 {
                depth = sourceDepth
            }
            // Average encoded bitrate excludes artwork/tags, unlike total file size.
            var audioBytes: UInt64 = 0
            size = UInt32(MemoryLayout<UInt64>.size)
            if AudioFileGetProperty(audioFile, kAudioFilePropertyAudioDataByteCount, &size, &audioBytes) == noErr, audioBytes > 0 {
                let average = Double(audioBytes) * 8 / duration
                if average.isFinite, average > 0, average < Double(Int.max) { bitRate = Int(average.rounded()) }
            }
            if bitRate == nil {
                var rate: UInt32 = 0
                size = UInt32(MemoryLayout<UInt32>.size)
                if AudioFileGetProperty(audioFile, kAudioFilePropertyBitRate, &size, &rate) == noErr, rate > 0 {
                    bitRate = Int(rate)
                }
            }
        }
        if codec == "MP3" || codec == "AAC" { depth = 0 }
        var track = Track(url: url, title: title, artist: artist, album: album, duration: duration,
                     sampleRate: format.sampleRate, bitDepth: Int(depth), codec: codec)
        track.albumArtist = tag("ALBUMARTIST", "ALBUM ARTIST", "ALBUM_ARTIST") ?? nativeAlbumArtist
        track.genre = tag("GENRE") ?? nativeGenre
        track.composer = tag("COMPOSER") ?? nativeComposer
        track.trackNumber = (tag("TRACKNUMBER") ?? nativeTrack).flatMap { Int($0.split(separator: "/").first.map(String.init) ?? "") }
        track.discNumber = tag("DISCNUMBER").flatMap { Int($0.split(separator: "/").first.map(String.init) ?? "") }
        track.metadataVersion = 2
        track.bitRate = bitRate
        return track
    }

    public static func artwork(for url: URL) async -> Data? {
        if let picture = try? EmbeddedArtwork.flac(url) { return picture }
        let asset = AVURLAsset(url: url)
        var metadata = (try? await asset.load(.commonMetadata)) ?? []
        for format in (try? await asset.load(.availableMetadataFormats)) ?? [] {
            metadata += (try? await asset.loadMetadata(for: format)) ?? []
        }
        for item in metadata where item.commonKey == .commonKeyArtwork || item.identifier == .iTunesMetadataCoverArt || item.identifier == .id3MetadataAttachedPicture {
            if let data = try? await item.load(.dataValue), !data.isEmpty { return data }
        }
        return nil
    }
}

public enum AudioError: LocalizedError {
    case emptyFile
    public var errorDescription: String? { "This file contains no playable audio." }
}

public struct ImportResult: Sendable {
    public var tracks: [Track] = []
    public var failed: [String] = []
}

public enum LibraryImporter {
    public static func scan(_ urls: [URL], excluding existing: Set<String>) async -> ImportResult {
        let discovery = discover(urls)
        var result = ImportResult()
        result.failed = discovery.failed
        var seen = existing
        for candidate in discovery.candidates.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
            if Task.isCancelled { break }
            let url = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard seen.insert(url.path).inserted else { continue }
            do { result.tracks.append(try await Track.read(url)) }
            catch { result.failed.append(url.lastPathComponent) }
        }
        return result
    }

    private static func discover(_ urls: [URL]) -> (candidates: [URL], failed: [String]) {
        var candidates: [URL] = []
        var result = ImportResult()
        for url in urls {
            if Task.isCancelled { break }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                result.failed.append(url.lastPathComponent)
                continue
            }
            if isDirectory.boolValue {
                if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { failedURL, _ in
                    result.failed.append(failedURL.lastPathComponent)
                    return true
                }) {
                    for case let child as URL in enumerator {
                        if Task.isCancelled { break }
                        if Track.extensions.contains(child.pathExtension.lowercased()) { candidates.append(child) }
                    }
                }
            } else {
                candidates.append(url)
            }
        }
        return (candidates, result.failed)
    }
}

public struct LibrarySnapshot: Codable {
    public var tracks: [Track]
    public var currentID: String?
    public var position: Double
    public var volume: Float
    public var favoriteIDs: Set<String>? = nil
    public var theme: String? = nil
    public var sortPreferences: [String: LibrarySort]? = nil

    public init(tracks: [Track] = [], currentID: String? = nil, position: Double = 0, volume: Float = 1, favoriteIDs: Set<String> = [], theme: String = "light", sortPreferences: [String: LibrarySort] = [:]) {
        self.tracks = tracks
        self.currentID = currentID
        self.position = position
        self.volume = volume
        self.favoriteIDs = favoriteIDs
        self.theme = theme
        self.sortPreferences = sortPreferences
    }
}

public enum LibraryStorage {
    public static func load(from url: URL) throws -> LibrarySnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return LibrarySnapshot() }
        return try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: url))
    }

    public static func save(_ snapshot: LibrarySnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }
}

public func timeLabel(_ seconds: Double) -> String {
    let value = seconds.isFinite ? max(0, Int(seconds)) : 0
    return String(format: "%d:%02d", value / 60, value % 60)
}
