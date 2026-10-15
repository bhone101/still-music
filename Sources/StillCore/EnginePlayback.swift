import AVFoundation

@MainActor public final class EnginePlayback {
    private let engine: AVAudioEngine
    private var node = AVAudioPlayerNode()
    private var standby = AVAudioPlayerNode()
    private var file: AVAudioFile
    private var scheduledFrames: AVAudioFramePosition = 0
    private var nextFile: (id: UUID, file: AVAudioFile, token: UUID, start: AVAudioTime)?
    private var activeToken = UUID()
    private var startTime: AVAudioTime?
    public var onNeedsNext: (() -> Void)?
    public var onAdvance: ((UUID) -> Void)?
    private var offset: Double = 0
    private var generation = 0
    public var onCompletion: (() -> Void)?
    public var onConfigurationChange: (() -> Void)?
    private var observer: NSObjectProtocol?
    public let outputRate: Double
    public var upcomingEntryID: UUID? { nextFile?.id }
    public var duration: Double { Double(file.length) / file.processingFormat.sampleRate }
    public var volume: Float = 1 { didSet { node.volume = volume; standby.volume = volume } }
    public var currentTime: Double {
        guard node.isPlaying, let render = node.lastRenderTime, render.isSampleTimeValid || render.isHostTimeValid, let time = node.playerTime(forNodeTime: render) else { return offset }
        return min(duration, max(0, offset + Double(time.sampleTime) / time.sampleRate))
    }

    public init(file: AVAudioFile, engine: AVAudioEngine = AVAudioEngine()) throws {
        self.file = file
        self.engine = engine
        let output = engine.isInManualRenderingMode ? engine.manualRenderingFormat : engine.outputNode.inputFormat(forBus: 0)
        guard output.sampleRate > 0, output.channelCount > 0 else { throw RateError.deviceChanged }
        outputRate = output.sampleRate
        engine.attach(node)
        engine.attach(standby)
        // The graph uses 32-bit float internally, which represents up to 24-bit PCM exactly.
        // 32-bit integer sources are not claimed to be bit-exact. No EQ, normalization or dithering.
        // At matching rates, source -> mixer -> output has no sample-rate conversion node.
        engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
        engine.connect(standby, to: engine.mainMixerNode, format: file.processingFormat)
        if !engine.isInManualRenderingMode { engine.connect(engine.mainMixerNode, to: engine.outputNode, format: output) }
        engine.mainMixerNode.outputVolume = 1
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onConfigurationChange?() }
        }
    }
    public func play(from seconds: Double) throws {
        generation += 1
        node.stop()
        standby.stop()
        nextFile = nil
        activeToken = UUID()
        offset = min(max(0, seconds), duration)
        let start = AVAudioFramePosition(offset * file.processingFormat.sampleRate)
        guard start < file.length else { onCompletion?(); return }
        guard file.length - start <= Int64(UInt32.max) else { throw RateError.status(-50) }
        scheduledFrames = file.length - start
        schedule(file, on: node, start: start, token: activeToken)
        engine.prepare()
        try engine.start()
        // Both nodes use the engine clock. Offline rendering has an exact sample
        // origin; a short host-time lead lets hardware start the graph silently.
        let anchor = engine.isInManualRenderingMode
            ? AVAudioTime(sampleTime: engine.manualRenderingSampleTime, atRate: outputRate)
            : AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.02))
        startTime = anchor
        node.play(at: anchor)
        onNeedsNext?()
    }

    /// Only the standby node is replaced. The current node, engine clock, and
    /// mixer gain stay untouched when the queue or playback mode changes.
    public func clearNext() {
        nextFile = nil
        standby.stop()
    }

    /// Deliver a boundary already rendered before the UI mutates the queue.
    /// A scheduled successor that has started is now the current song.
    public func synchronizeQueueBoundary() {
        guard nextFile != nil, let render = standby.lastRenderTime,
              let time = standby.playerTime(forNodeTime: render), time.sampleTime >= 0 else { return }
        complete(token: activeToken)
    }

    @discardableResult public func preload(_ next: AVAudioFile, id: UUID) -> Bool {
        guard next.length > 0, next.length <= Int64(UInt32.max),
              file.processingFormat.isEqual(next.processingFormat), let anchor = startTime else {
            clearNext()
            return false
        }
        if nextFile?.id == id { return true }
        clearNext()
        let end = AVAudioTime(sampleTime: scheduledFrames, atRate: file.processingFormat.sampleRate)
        let when: AVAudioTime
        if let converted = node.nodeTime(forPlayerTime: end) {
            when = converted
        } else if anchor.isSampleTimeValid {
            when = AVAudioTime(sampleTime: anchor.sampleTime + AVAudioFramePosition(Double(scheduledFrames) * anchor.sampleRate / file.processingFormat.sampleRate), atRate: anchor.sampleRate)
        } else {
            when = AVAudioTime(hostTime: anchor.hostTime + AVAudioTime.hostTime(forSeconds: Double(scheduledFrames) / file.processingFormat.sampleRate))
        }
        let token = UUID()
        nextFile = (id, next, token, when)
        schedule(next, on: standby, start: 0, token: token)
        standby.play(at: when)
        return true
    }

    private func schedule(_ scheduled: AVAudioFile, on player: AVAudioPlayerNode, start: AVAudioFramePosition, token: UUID) {
        let generation = generation
        player.scheduleSegment(scheduled, startingFrame: start, frameCount: AVAudioFrameCount(scheduled.length - start), at: nil,
                               completionCallbackType: engine.isInManualRenderingMode ? .dataRendered : .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == generation else { return }
                self.complete(token: token)
            }
        }
    }
    private func complete(token: UUID) {
        guard token == activeToken else { return }
        if let next = nextFile {
            swap(&node, &standby)
            activeToken = next.token
            startTime = next.start
            file = next.file
            offset = 0
            scheduledFrames = file.length
            nextFile = nil
            standby.stop()
            onAdvance?(next.id)
            onNeedsNext?()
        } else {
            // Invalidate duplicate callbacks after an explicit boundary sync.
            activeToken = UUID()
            offset = duration
            onCompletion?()
        }
    }
    /// Fade only this app's mixer, never the shared device volume. Unity is restored
    /// after the short transition; no gain processing is applied during steady playback.
    public func fadeOutAndStop() async {
        if engine.isRunning {
            let initial = engine.mainMixerNode.outputVolume
            for step in 1...8 {
                engine.mainMixerNode.outputVolume = initial * (1 - Float(step) / 8)
                // Complete the fade even if the playback request was superseded.
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { continuation.resume() }
                }
            }
        }
        stop()
    }
    public func playWithFade(from seconds: Double) async throws {
        engine.mainMixerNode.outputVolume = 0
        try play(from: seconds)
        // Allow the output to start while silent before fading the newly configured graph in.
        try await Task.sleep(nanoseconds: engine.isInManualRenderingMode ? 8_000_000 : 28_000_000)
        for step in 1...8 {
            try Task.checkCancellation()
            engine.mainMixerNode.outputVolume = Float(step) / 8
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        engine.mainMixerNode.outputVolume = 1
    }
    public func stop() {
        offset = currentTime
        generation += 1
        nextFile = nil
        node.stop()
        standby.stop()
        startTime = nil
        engine.stop()
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
