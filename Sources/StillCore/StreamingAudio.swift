import AVFoundation
import Foundation
import Darwin

/// A bounded pipe applies back pressure to the decoder; no decoded song is stored on disk.
public final class StreamingAudio: @unchecked Sendable {
    public let format: AVAudioFormat
    private let process = Process()
    private let pipe = Pipe()
    private let worker = DispatchQueue(label: "Still.decoder-reader", qos: .userInitiated)
    private let lock = NSLock()
    private var cancelled = false
    private var timedOut = false
    public init(source: URL, seconds: Double = 0) throws {
        let rate = Double(FileMetadata.read("_RATE", from: source) ?? "") ?? 0
        let channels = UInt32(FileMetadata.read("_CHANNELS", from: source) ?? "") ?? 0
        guard rate > 0, channels > 0, channels <= 32,
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)
        else {
            throw NSError(
                domain: "StillDecoder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio format."])
        }
        self.format = format
        process.executableURL = ExtendedAudio.executable
        process.arguments = [
            "-nostdin", "-v", "error", "-ss", String(max(0, seconds)), "-i", source.path,
            "-map", "0:a:0", "-vn", "-ar", String(Int(rate)), "-ac", String(channels),
            "-c:a", "pcm_f32le", "-f", "f32le", "pipe:1",
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        try? pipe.fileHandleForWriting.close()
    }
    public func cancel() {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        if process.isRunning {
            process.terminate()
            let child = process
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
        lock.unlock()
    }
    public func read() async throws -> AVAudioPCMBuffer? {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                worker.async { [self] in
                    do {
                        self.lock.lock()
                        let cancelled = self.cancelled
                        self.lock.unlock()
                        if cancelled { throw CancellationError() }
                        let frameBytes = Int(self.format.channelCount) * 4
                        let wanted = 16384 * frameBytes
                        var data = Data()
                        // A stalled/corrupt decoder cannot leave playback waiting indefinitely.
                        let timeout = DispatchWorkItem { [weak self] in
                            guard let self else { return }
                            self.lock.lock()
                            self.timedOut = true
                            self.lock.unlock()
                            self.cancel()
                        }
                        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
                        defer { timeout.cancel() }
                        while data.count < wanted {
                            let chunk =
                                try self.pipe.fileHandleForReading.read(upToCount: wanted - data.count) ?? Data()
                            if chunk.isEmpty { break }
                            data.append(chunk)
                        }
                        self.lock.lock()
                        let stopped = self.cancelled
                        let timedOut = self.timedOut
                        self.lock.unlock()
                        if timedOut {
                            throw NSError(
                                domain: "StillDecoder", code: 3,
                                userInfo: [NSLocalizedDescriptionKey: "The audio decoder stopped responding."])
                        }
                        if stopped { throw CancellationError() }
                        guard !data.isEmpty else {
                            self.process.waitUntilExit()
                            guard self.process.terminationStatus == 0 else {
                                throw NSError(
                                    domain: "StillDecoder", code: 2,
                                    userInfo: [
                                        NSLocalizedDescriptionKey: "The audio decoder could not finish this file."
                                    ])
                            }
                            continuation.resume(returning: nil)
                            return
                        }
                        guard data.count % frameBytes == 0,
                            let buffer = AVAudioPCMBuffer(
                                pcmFormat: self.format, frameCapacity: AVAudioFrameCount(data.count / frameBytes))
                        else { throw RateError.status(-50) }
                        buffer.frameLength = buffer.frameCapacity
                        data.withUnsafeBytes { bytes in
                            for frame in 0..<Int(buffer.frameLength) {
                                for channel in 0..<Int(self.format.channelCount) {
                                    buffer.floatChannelData![channel][frame] = Float(
                                        bitPattern: UInt32(
                                            littleEndian: bytes.loadUnaligned(
                                                fromByteOffset: frame * frameBytes + channel * 4, as: UInt32.self)))
                                }
                            }
                        }
                        continuation.resume(returning: buffer)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: {
            self.cancel()
        }
    }
    deinit {
        cancel()
        try? pipe.fileHandleForReading.close()
    }
}

@MainActor public protocol AudioPlayback: AnyObject {
    var onNeedsNext: (() -> Void)? { get set }
    var onAdvance: ((UUID) -> Void)? { get set }
    var onCompletion: (() -> Void)? { get set }
    var onConfigurationChange: (() -> Void)? { get set }
    var currentTime: Double { get }
    var duration: Double { get }
    var outputRate: Double { get }
    var volume: Float { get set }
    var upcomingEntryID: UUID? { get }
    func updateEqualizer(_ settings: EqualizerSettings) -> Bool
    func clearNext()
    func synchronizeQueueBoundary()
    func preload(_ file: AVAudioFile, id: UUID) -> Bool
    func playWithFade(from seconds: Double) async throws
    func fadeOutAndStop() async
}
extension EnginePlayback: AudioPlayback {}

@MainActor public final class StreamPlayback: AudioPlayback {
    public var onNeedsNext: (() -> Void)?
    public var onAdvance: ((UUID) -> Void)?
    public var onCompletion: (() -> Void)?
    public var onConfigurationChange: (() -> Void)?
    public var onFailure: ((Error) -> Void)?
    public let duration: Double
    public let outputRate: Double
    public var volume: Float = 1 { didSet { node.volume = volume } }
    public var upcomingEntryID: UUID? { nil }
    private let decoder: StreamingAudio
    private var first: AVAudioPCMBuffer?
    private let engine: AVAudioEngine
    private let node = AVAudioPlayerNode()
    private var pump: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private var queued = 0
    private var ended = false
    private var stopped = false
    private var offset: Double = 0
    public func updateEqualizer(_ settings: EqualizerSettings) -> Bool {
        EqualizerGraph.update(engine, settings: settings)
    }
    public var currentTime: Double {
        guard let render = node.lastRenderTime, let time = node.playerTime(forNodeTime: render) else { return offset }
        return min(duration, max(0, offset + Double(time.sampleTime) / time.sampleRate))
    }
    public init(
        decoder: StreamingAudio, first: AVAudioPCMBuffer?, duration: Double, engine: AVAudioEngine = AVAudioEngine(), equalizer: EqualizerSettings = .init()
    ) throws {
        self.engine = engine
        self.decoder = decoder
        self.first = first
        self.duration = duration
        let output =
            engine.isInManualRenderingMode ? engine.manualRenderingFormat : engine.outputNode.inputFormat(forBus: 0)
        guard output.sampleRate > 0, output.channelCount > 0 else { throw RateError.deviceChanged }
        outputRate = output.sampleRate
        engine.attach(node)
        EqualizerGraph.connect(engine, sources: [node], format: decoder.format, settings: equalizer)
        if !engine.isInManualRenderingMode {
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: output)
        }
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onConfigurationChange?() }
        }
    }
    public func clearNext() {}
    public func synchronizeQueueBoundary() {}
    public func preload(_ file: AVAudioFile, id: UUID) -> Bool { false }
    private func schedule(_ buffer: AVAudioPCMBuffer) {
        queued += 1
        node.scheduleBuffer(
            buffer, completionCallbackType: engine.isInManualRenderingMode ? .dataRendered : .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                self.queued -= 1
                if self.ended && self.queued == 0 { self.onCompletion?() } else { self.fill() }
            }
        }
    }
    private func fill() {
        guard pump == nil, !ended, !stopped else { return }
        pump = Task { [weak self] in
            guard let self else { return }
            defer { self.pump = nil }
            do {
                while self.queued < 4 && !self.stopped {
                    guard let buffer = try await self.decoder.read() else {
                        self.ended = true
                        if self.queued == 0 { self.onCompletion?() }
                        return
                    }
                    try Task.checkCancellation()
                    self.schedule(buffer)
                }
            } catch {
                if !self.stopped { self.onFailure?(error) }
            }
        }
    }
    public func play(from seconds: Double) async throws {
        offset = seconds
        if let first {
            schedule(first)
            self.first = nil
        }
        while queued < 3 {
            guard let buffer = try await decoder.read() else {
                ended = true
                break
            }
            try Task.checkCancellation()
            schedule(buffer)
        }
        guard queued > 0 else { throw RateError.status(-50) }
        engine.prepare()
        try engine.start()
        node.play()
        fill()
        onNeedsNext?()
    }
    public func playWithFade(from seconds: Double) async throws {
        engine.mainMixerNode.outputVolume = 0
        try await play(from: seconds)
        for step in 1...8 {
            try Task.checkCancellation()
            engine.mainMixerNode.outputVolume = Float(step) / 8
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
    public func fadeOutAndStop() async {
        stopped = true
        pump?.cancel()
        decoder.cancel()
        let initial = engine.mainMixerNode.outputVolume
        for step in 1...8 {
            engine.mainMixerNode.outputVolume = initial * (1 - Float(step) / 8)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { continuation.resume() }
            }
        }
        node.stop()
        engine.stop()
    }
    deinit {
        pump?.cancel()
        decoder.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
