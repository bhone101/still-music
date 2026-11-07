import AVFoundation
import Foundation

public enum ExtendedAudio {
    public static let extensions: Set<String> = ["opus", "ogg", "oga", "ape", "wv"]
    public static var executable: URL {
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "StillDecoder") { return bundled }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/decoder/ffmpeg")
    }
    public static func readyFile(_ source: URL) throws -> AVAudioFile {
        return try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
    }
}

/// Transfers a newly opened file from the I/O worker to its sole playback owner.
/// The worker never reads or mutates the file after returning this container.
public struct OpenedAudioFile: @unchecked Sendable {
    public let file: AVAudioFile
    public init(url: URL) throws { file = try ExtendedAudio.readyFile(url) }
}
