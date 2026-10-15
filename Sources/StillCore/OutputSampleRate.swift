import CoreAudio
import Foundation

public enum SampleRatePolicy {
    /// Select the source rate, or the smallest supported integer multiple. Ranges may be continuous.
    public static func preferred(source: Double, ranges: [ClosedRange<Double>]) -> Double? {
        guard source.isFinite, source > 0 else { return nil }
        return ranges.compactMap { range -> Double? in
            guard range.lowerBound.isFinite, range.upperBound.isFinite else { return nil }
            let multiple = max(1, ceil((range.lowerBound - 0.01) / source))
            let candidate = multiple * source
            return candidate <= range.upperBound + 0.01 ? candidate : nil
        }.min()
    }
}

@MainActor public protocol OutputRateHardware: AnyObject {
    func defaultDevice() throws -> AudioDeviceID
    func rate(_ device: AudioDeviceID) throws -> Double
    func availableRates(_ device: AudioDeviceID) throws -> [ClosedRange<Double>]
    func setRate(_ rate: Double, device: AudioDeviceID) async throws
}

@MainActor public final class OutputSampleRate {
    private let hardware: OutputRateHardware
    private let diagnostics: AudioDiagnostics?
    private var originals: [AudioDeviceID: Double] = [:]
    public init(hardware: OutputRateHardware? = nil, diagnostics: AudioDiagnostics? = nil) {
        self.hardware = hardware ?? CoreAudioRateHardware()
        self.diagnostics = diagnostics
    }

    /// Callers serialize match and restore, including cancelled playback requests.
    public func match(source: Double, enabled: Bool) async throws -> Double {
        do { return try await matchRate(source: source, enabled: enabled) }
        catch {
            if !(error is CancellationError) {
                diagnostics?.record(.rateFailed, sourceRate: source, status: AudioDiagnostics.statusCode(error))
            }
            throw error
        }
    }
    private func matchRate(source: Double, enabled: Bool) async throws -> Double {
        let device = try hardware.defaultDevice()
        try? await restorePreviousDevices()
        try Task.checkCancellation()
        guard try hardware.defaultDevice() == device else { throw RateError.deviceChanged }
        let current = try hardware.rate(device)
        diagnostics?.record(.rateObserved, device: device, sourceRate: source, outputRate: current)
        guard enabled else { return current }
        guard abs(source - current) > 0.01 else { return current }
        let target = SampleRatePolicy.preferred(source: source, ranges: try hardware.availableRates(device)) ?? current
        guard abs(target - current) > 0.01 else { return current }
        if originals[device] == nil { originals[device] = current }
        diagnostics?.record(.rateRequested, device: device, sourceRate: source, outputRate: target)
        try await hardware.setRate(target, device: device)
        guard try hardware.defaultDevice() == device else { throw RateError.deviceChanged }
        let actual = try hardware.rate(device)
        diagnostics?.record(.rateConfirmed, device: device, sourceRate: source, outputRate: actual)
        return actual
    }

    public func restorePreviousDevices() async throws {
        let current = try? hardware.defaultDevice()
        try await restore(excluding: current)
    }
    public func restore() async throws { try await restore(excluding: nil) }
    private func restore(excluding deviceToKeep: AudioDeviceID?) async throws {
        var failure: Error?
        for (device, rate) in originals where device != deviceToKeep {
            do {
                if abs(try hardware.rate(device) - rate) > 0.01 { try await hardware.setRate(rate, device: device) }
                originals.removeValue(forKey: device)
                diagnostics?.record(.rateRestored, device: device, outputRate: rate)
            } catch {
                diagnostics?.record(.restoreFailed, device: device, outputRate: rate, status: AudioDiagnostics.statusCode(error))
                failure = error
            } // Keep unsuccessful restorations for a later retry.
        }
        if let failure { throw failure }
    }
}

public enum RateError: LocalizedError {
    case status(OSStatus), timeout, deviceChanged
    public var errorDescription: String? {
        switch self {
        case .status(let code): return "CoreAudio error \(code)."
        case .timeout: return "The output device did not confirm its sample rate in time."
        case .deviceChanged: return "The audio output device changed during setup."
        }
    }
}

@MainActor public final class CoreAudioRateHardware: OutputRateHardware {
    public init() {}
    private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    public func defaultDevice() throws -> AudioDeviceID {
        var property = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout.size(ofValue: device))
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &device))
        guard device != 0 else { throw RateError.deviceChanged }
        return device
    }
    public func rate(_ device: AudioDeviceID) throws -> Double {
        var property = address(kAudioDevicePropertyNominalSampleRate)
        var value = Float64(0)
        var size = UInt32(MemoryLayout.size(ofValue: value))
        try check(AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value))
        return value
    }
    public func availableRates(_ device: AudioDeviceID) throws -> [ClosedRange<Double>] {
        var property = address(kAudioDevicePropertyAvailableNominalSampleRates)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size))
        var values = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.stride)
        guard !values.isEmpty else { return [] }
        try values.withUnsafeMutableBytes { bytes in
            try check(AudioObjectGetPropertyData(device, &property, 0, nil, &size, bytes.baseAddress!))
        }
        return values.filter { $0.mMinimum > 0 && $0.mMaximum >= $0.mMinimum }.map { $0.mMinimum...$0.mMaximum }
    }
    public func setRate(_ value: Double, device: AudioDeviceID) async throws {
        if abs(try rate(device) - value) < 0.01 { return }
        var property = address(kAudioDevicePropertyNominalSampleRate)
        var settable: DarwinBoolean = false
        try check(AudioObjectIsPropertySettable(device, &property, &settable))
        guard settable.boolValue else { throw RateError.status(kAudioHardwareIllegalOperationError) }
        let wait = RateConfirmation()
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let actual = try? self.rate(device), abs(actual - value) < 0.01 { wait.finish(nil) }
            }
        }
        try check(AudioObjectAddPropertyListenerBlock(device, &property, .main, listener))
        defer { AudioObjectRemovePropertyListenerBlock(device, &property, .main, listener) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            wait.continuation = continuation
            var target = value
            let status = AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout.size(ofValue: target)), &target)
            if status != noErr { wait.finish(RateError.status(status)); return }
            // Some devices complete synchronously; the listener was installed before the write.
            if let actual = try? rate(device), abs(actual - value) < 0.01 { wait.finish(nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { wait.finish(RateError.timeout) }
        }
    }
    private func check(_ status: OSStatus) throws { if status != noErr { throw RateError.status(status) } }
}

@MainActor private final class RateConfirmation {
    var continuation: CheckedContinuation<Void, Error>?
    func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
}

/// Observe default-device changes even while paused, when no engine is running.
@MainActor public final class OutputDeviceMonitor {
    private var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private let listener: AudioObjectPropertyListenerBlock
    private var installed = false
    public init(onChange: @escaping @MainActor () -> Void) {
        listener = { _, _ in MainActor.assumeIsolated { onChange() } }
        installed = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &property, .main, listener) == noErr
    }
    deinit {
        if installed { AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &property, .main, listener) }
    }
}
