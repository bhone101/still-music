import AVFoundation

/// Stored independently of the library. Disabled means no EQ node in the graph.
public struct EqualizerSettings: Codable, Equatable, Sendable {
    public static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    public var enabled: Bool
    public var gains: [Float]
    public var automaticPreamp: Bool
    public var manualPreamp: Float
    public init(enabled: Bool = false, gains: [Float] = Array(repeating: 0, count: 10), automaticPreamp: Bool = true, manualPreamp: Float = 0) {
        self.automaticPreamp = automaticPreamp
        self.manualPreamp = manualPreamp.isFinite ? min(12, max(-12, manualPreamp)) : 0
        self.enabled = enabled
        self.gains = (0..<10).map { index in
            let value = gains.indices.contains(index) ? gains[index] : 0
            return value.isFinite ? min(12, max(-12, value)) : 0
        }
    }
    private enum CodingKeys: String, CodingKey { case enabled, gains, automaticPreamp, manualPreamp }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(enabled: try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
                  gains: try values.decodeIfPresent([Float].self, forKey: .gains) ?? [],
                  automaticPreamp: try values.decodeIfPresent(Bool.self, forKey: .automaticPreamp) ?? true,
                  manualPreamp: try values.decodeIfPresent(Float.self, forKey: .manualPreamp) ?? 0)
    }
    public var normalized: Self { Self(enabled: enabled, gains: gains, automaticPreamp: automaticPreamp, manualPreamp: manualPreamp) }
    /// Leave headroom for boosted bands; this is not a peak limiter.
    public var preamp: Float { automaticPreamp ? -max(0, normalized.gains.max() ?? 0) : normalized.manualPreamp }
}

public enum EqualizerPreset: String, CaseIterable, Identifiable {
    case flat = "Flat", bass = "Bass Boost", vocals = "Vocal", treble = "Treble Boost", shaped = "V-shaped", soft = "Softer highs"
    public var id: String { rawValue }
    public var gains: [Float] {
        switch self {
        case .flat: return Array(repeating: 0, count: 10)
        case .bass: return [4, 4, 3, 1, 0, 0, 0, 0, 0, 0]
        case .vocals: return [-2, -2, -1, 0, 1, 3, 3, 2, 0, 0]
        case .treble: return [0, 0, 0, 0, 0, 0, 1, 2, 3, 3]
        case .shaped: return [4, 3, 2, 0, -2, -2, 0, 2, 3, 4]
        case .soft: return [0, 0, 0, 0, 0, 0, -1, -2, -3, -4]
        }
    }
}

@MainActor enum EqualizerGraph {
    static func connect(_ engine: AVAudioEngine, sources: [AVAudioPlayerNode], format: AVAudioFormat,
                        settings: EqualizerSettings) {
        guard settings.enabled else {
            for source in sources { engine.connect(source, to: engine.mainMixerNode, format: format) }
            return
        }
        // Mix both gapless player nodes before filtering so they share one EQ state.
        let input = AVAudioMixerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 10)
        engine.attach(input)
        engine.attach(eq)
        for source in sources { engine.connect(source, to: input, format: format) }
        configure(eq, format: format, settings: settings)
        engine.connect(input, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
    }
    /// Updating an existing EQ leaves the engine, playback position, and queue intact.
    static func update(_ engine: AVAudioEngine, settings: EqualizerSettings) -> Bool {
        guard settings.enabled, let eq = engine.attachedNodes.compactMap({ $0 as? AVAudioUnitEQ }).first else { return false }
        configure(eq, format: eq.inputFormat(forBus: 0), settings: settings)
        return true
    }

    private static func configure(_ eq: AVAudioUnitEQ, format: AVAudioFormat, settings: EqualizerSettings) {
        let normalized = settings.normalized
        // Establish extra headroom before raising any band during a live update.
        if normalized.preamp < eq.globalGain { eq.globalGain = normalized.preamp }
        for (index, band) in eq.bands.enumerated() {
            let frequency = EqualizerSettings.frequencies[index]
            band.filterType = .parametric
            band.frequency = min(frequency, Float(format.sampleRate * 0.45))
            band.bandwidth = 1
            band.gain = normalized.gains[index]
            band.bypass = normalized.gains[index] == 0 || Double(frequency) >= format.sampleRate * 0.45
        }
        eq.globalGain = normalized.preamp
    }

}
