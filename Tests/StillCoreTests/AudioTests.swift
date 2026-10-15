import AVFoundation
import CoreAudio
import AppKit
import Foundation
import StillCore

final class AudioTests {
    private var directory: URL!

    func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("StillTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func exportUIFixtures() throws {
        let target = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/metadata-fixtures")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for name in ["Tagged one.flac", "Tagged two.flac", "Native tags.m4a"] {
            try Data(contentsOf: directory.appendingPathComponent(name)).write(to: target.appendingPathComponent(name), options: .atomic)
        }
    }

    func testWatchedFolders() async throws {
        let folder = directory.appendingPathComponent("Watched", isDirectory: true)
        let nested = folder.appendingPathComponent("Album", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        var watched = WatchedFolders()
        watched.include([folder, nested])
        XCTAssertEqual(watched.paths.count, 1)
        let stateURL = directory.appendingPathComponent("folders.json")
        try watched.save(to: stateURL)
        watched = try WatchedFolders.load(from: stateURL)
        XCTAssertEqual((await LibraryImporter.scan(watched.urls, excluding: [])).tracks.count, 0)
        let first = nested.appendingPathComponent("First.wav")
        try FileManager.default.moveItem(at: makeWAV(name: "ScanFirst"), to: first)
        let initial = await LibraryImporter.scan(watched.urls, excluding: [])
        XCTAssertEqual(initial.tracks.count, 1)
        let ids = Set(initial.tracks.map(\.id))
        XCTAssertEqual((await LibraryImporter.scan(watched.urls, excluding: ids)).tracks.count, 0)
        let second = folder.appendingPathComponent("Second.wav")
        try FileManager.default.moveItem(at: makeWAV(name: "ScanSecond"), to: second)
        let added = await LibraryImporter.scan(watched.urls, excluding: ids)
        XCTAssertEqual(added.tracks.count, 1)
        watched.ignoredTrackIDs = ids
        try watched.save(to: stateURL)
        watched = try WatchedFolders.load(from: stateURL)
        let remaining = Set(added.tracks.map(\.id)).union(watched.ignoredTrackIDs)
        XCTAssertEqual((await LibraryImporter.scan(watched.urls, excluding: remaining)).tracks.count, 0)
        try FileManager.default.moveItem(at: folder, to: directory.appendingPathComponent("Offline"))
        XCTAssertEqual((await LibraryImporter.scan(watched.urls, excluding: remaining)).tracks.count, 0)
    }

    func testMovedLibraryPaths() async throws {
        let originalURL = try makeWAV(name: "MoveRepair", rate: 44100)
        let original = try await Track.read(originalURL)
        let movedURL = directory.appendingPathComponent("Moved.wav")
        try FileManager.default.moveItem(at: originalURL, to: movedURL)
        // Preserve tags as real tagged files do across a rename.
        func at(_ url: URL) throws -> Track {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
            object["url"] = url.absoluteString
            return try JSONDecoder().decode(Track.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let moved = try at(movedURL)
        XCTAssertEqual(LibraryReconciliation.replacements(in: [original, moved]), [original.id: moved.id])
        try FileManager.default.moveItem(at: movedURL, to: originalURL)
        XCTAssertEqual(LibraryReconciliation.replacements(in: [original, moved]), [moved.id: original.id])
        XCTAssertEqual(LibraryReconciliation.replacements(in: [moved]), [:])
        try FileManager.default.copyItem(at: originalURL, to: movedURL)
        XCTAssertEqual(LibraryReconciliation.replacements(in: [original, moved]), [:])
        let stale = try at(directory.appendingPathComponent("Stale.wav"))
        XCTAssertEqual(LibraryReconciliation.replacements(in: [original, moved, stale]), [:])
        let offline = try at(URL(fileURLWithPath: "/Volumes/StillChecks-\(UUID())/Offline.wav"))
        XCTAssertEqual(LibraryReconciliation.replacements(in: [original, offline]), [:])
        var queue = PlaybackQueue()
        queue.reset([stale.id, original.id], startingAt: stale.id)
        let occurrence = queue.current?.id
        queue.reconcilePaths([stale.id: original.id])
        XCTAssertEqual(queue.current?.id, occurrence)
        XCTAssertEqual(queue.current?.trackID, original.id)
        XCTAssertEqual(queue.upcoming.count, 1)
    }

    @MainActor func testEngineRendering() async throws {
        let url = try makeWAV(name: "Engine24", rate: 96000, bits: 24)
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let expected = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 512))
        try file.read(into: expected)
        file.framePosition = 0
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: file.processingFormat, maximumFrameCount: 512)
        let player = try EnginePlayback(file: file, engine: engine)
        XCTAssertEqual(player.outputRate, 96000)
        XCTAssertEqual(player.volume, 1)
        try player.play(from: 0)
        let rendered = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 512))
        XCTAssertEqual(try engine.renderOffline(512, to: rendered), .success)
        XCTAssertEqual(rendered.frameLength, expected.frameLength)
        for channel in 0..<2 {
            let actualSamples = try XCTUnwrap(rendered.floatChannelData?[channel])
            let expectedSamples = try XCTUnwrap(expected.floatChannelData?[channel])
            for frame in 0..<Int(expected.frameLength) { XCTAssertEqual(actualSamples[frame], expectedSamples[frame]) }
        }
        // Seek and stop invalidate the prior scheduled segment; neither changes hardware.
        try player.play(from: 0.1)
        XCTAssertEqual(try engine.renderOffline(512, to: rendered), .success)
        player.stop()
        XCTAssertEqual(engine.isRunning, false)
        try await player.playWithFade(from: 0)
        XCTAssertEqual(engine.mainMixerNode.outputVolume, 1)
        await player.fadeOutAndStop()
        XCTAssertEqual(engine.mainMixerNode.outputVolume, 0)
        XCTAssertEqual(engine.isRunning, false)
    }

    @MainActor func testGaplessOutput() async throws {
        for rate in [44100, 48000, 96000, 192000] {
            for bits in [16, 24] {
                let firstURL = try makeWAV(name: "BoundaryA-\(rate)-\(bits)", rate: rate, bits: bits)
                let secondURL = try makeWAV(name: "BoundaryB-\(rate)-\(bits)", rate: rate, bits: bits, frequency: 731)
                func open(_ url: URL) throws -> AVAudioFile {
                    try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
                }
                var playbackURLs = [firstURL, secondURL]
                if bits == 24 {
                    playbackURLs = try playbackURLs.map { source in
                        let destination = source.deletingPathExtension().appendingPathExtension("flac")
                        let convert = Process()
                        convert.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
                        convert.arguments = [source.path, destination.path, "-f", "flac", "-d", "flac"]
                        try convert.run(); convert.waitUntilExit()
                        XCTAssertEqual(convert.terminationStatus, 0)
                        return destination
                    }
                }
                let first = try open(playbackURLs[0]), second = try open(playbackURLs[1])
                let engine = AVAudioEngine()
                try engine.enableManualRenderingMode(.offline, format: first.processingFormat, maximumFrameCount: 512)
                let player = try EnginePlayback(file: first, engine: engine)
                var reference: [[Float]] = [[], []]
                for url in [firstURL, secondURL] {
                    let file = try open(url)
                    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
                    try file.read(into: buffer)
                    for channel in 0..<2 {
                        reference[channel] += Array(UnsafeBufferPointer(start: buffer.floatChannelData![channel], count: Int(buffer.frameLength)))
                    }
                }
                let successor = UUID()
                var advanced: [UUID] = []
                player.onAdvance = { advanced.append($0) }
                try player.play(from: 0)
                XCTAssertEqual(player.preload(second, id: successor), true)
                XCTAssertEqual(player.preload(second, id: successor), true)
                let rendered = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 512))
                var offset = 0, mismatches = 0
                while offset < reference[0].count {
                    let count = min(512, reference[0].count - offset)
                    XCTAssertEqual(try engine.renderOffline(AVAudioFrameCount(count), to: rendered), .success)
                    for channel in 0..<2 {
                        for frame in 0..<count {
                            if rendered.floatChannelData![channel][frame] != reference[channel][offset + frame] { mismatches += 1 }
                        }
                    }
                    offset += count
                }
                XCTAssertEqual(mismatches, 0, "\(rate) Hz / \(bits)-bit: all PCM samples across the track boundary must match")
                XCTAssertEqual(engine.isRunning, true)
                // Let completion callbacks update metadata without driving the audio boundary.
                for _ in 0..<20 where advanced.isEmpty { try await Task.sleep(nanoseconds: 5_000_000) }
                XCTAssertEqual(advanced, [successor])
                player.stop()
                print("Verified offline output: \(rate) Hz / \(bits)-bit \(playbackURLs[0].pathExtension), seamless boundary, \(reference[0].count) frames")
            }
        }
        let first = try AVAudioFile(forReading: makeWAV(name: "SameRate", rate: 44100))
        let different = try AVAudioFile(forReading: makeWAV(name: "DifferentRate", rate: 48000))
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: first.processingFormat, maximumFrameCount: 512)
        let player = try EnginePlayback(file: first, engine: engine)
        try player.play(from: 0)
        XCTAssertEqual(player.preload(different, id: UUID()), false)
        player.stop()
    }

    @MainActor func testQueueEditsPreserveAudio() async throws {
        for rate in [44100.0, 96000, 192000] {
            for keepNext in [true, false] {
                let urls = try [311.0, 523, 733, 997].enumerated().map { index, frequency in
                    try makeWAV(name: "Queue-\(rate)-\(keepNext)-\(index)", rate: Int(rate), bits: 24, frequency: frequency)
                }
                func open(_ index: Int) throws -> AVAudioFile {
                    try AVAudioFile(forReading: urls[index], commonFormat: .pcmFormatFloat32, interleaved: false)
                }
                let first = try open(0)
                let engine = AVAudioEngine()
                try engine.enableManualRenderingMode(.offline, format: first.processingFormat, maximumFrameCount: 512)
                let player = try EnginePlayback(file: first, engine: engine)
                let nextID = UUID(), thirdID = UUID()
                var advanced: [UUID] = [], completions = 0
                player.onAdvance = { advanced.append($0) }
                player.onCompletion = { completions += 1 }
                player.onNeedsNext = {
                    if advanced == [nextID] { _ = player.preload(try! open(3), id: thirdID) }
                }
                // A seeked start also has to preserve the correct boundary time.
                let startFrame: Int64 = 137
                try player.play(from: Double(startFrame) / rate)
                _ = player.preload(try open(1), id: UUID())
                var reference: [[Float]] = [[], []]
                for index in keepNext ? [0, 2, 3] : [0] {
                    let file = try open(index)
                    if index == 0 { file.framePosition = startFrame }
                    let count = AVAudioFrameCount(file.length - file.framePosition)
                    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count))
                    try file.read(into: buffer)
                    for channel in 0..<2 {
                        reference[channel] += Array(UnsafeBufferPointer(start: buffer.floatChannelData![channel], count: Int(buffer.frameLength)))
                    }
                }
                let currentFrames = Int(first.length - startFrame)
                let rendered = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: first.processingFormat, frameCapacity: 512))
                var renderedCount = 0, mismatches = 0, edits = 0
                let editPoints = [512, currentFrames / 2, currentFrames - 128]
                while renderedCount < reference[0].count {
                    if editPoints.contains(renderedCount) {
                        let time = player.currentTime
                        player.synchronizeQueueBoundary()
                        player.clearNext()
                        _ = player.preload(try open(1), id: UUID())
                        player.clearNext()
                        if keepNext { _ = player.preload(try open(2), id: nextID) }
                        XCTAssertEqual(player.currentTime, time)
                        XCTAssertEqual(engine.isRunning, true)
                        edits += 1
                    }
                    let nextEdit = editPoints.first { $0 > renderedCount } ?? reference[0].count
                    let count = min(512, reference[0].count - renderedCount, nextEdit - renderedCount)
                    XCTAssertEqual(try engine.renderOffline(AVAudioFrameCount(count), to: rendered), .success)
                    for channel in 0..<2 {
                        for frame in 0..<count {
                            if rendered.floatChannelData![channel][frame] != reference[channel][renderedCount + frame] { mismatches += 1 }
                        }
                    }
                    renderedCount += count
                    // Deliver metadata/standby callbacks, as the app run loop does.
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
                for _ in 0..<20 where completions == 0 { try await Task.sleep(nanoseconds: 2_000_000) }
                XCTAssertEqual(edits, 3)
                XCTAssertEqual(mismatches, 0, "Queue edits must not alter, skip, repeat, or silence PCM at \(rate) Hz")
                XCTAssertEqual(advanced, keepNext ? [nextID, thirdID] : [])
                XCTAssertEqual(completions, 1)
                player.stop()
                player.onNeedsNext = nil
            }
        }
    }

    @MainActor func testAudioDiagnostics() async throws {
        let url = directory.appendingPathComponent("private-library.audio-diagnostics.json")
        let log = AudioDiagnostics(storageURL: url, capacity: 4)
        for _ in 0..<10 { log.record(.queueEdited) }
        let secretError = NSError(domain: "/Users/private/Song.flac", code: -50,
                                  userInfo: [NSLocalizedDescriptionKey: "Private song title /Users/private/Song.flac"])
        log.record(.playbackFailed, status: AudioDiagnostics.statusCode(secretError))
        log.record(.rateConfirmed, device: 42, sourceRate: 44100, outputRate: 44100)
        await log.flush()
        let data = try log.exportData()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(text.contains("private"), false)
        XCTAssertEqual(text.contains("Song.flac"), false)
        XCTAssertEqual(log.entries.count, 4)
        XCTAssertEqual(try Data(contentsOf: url), data)
        let restored = AudioDiagnostics(storageURL: url, capacity: 4)
        XCTAssertEqual(restored.entries.count, 4)
        XCTAssertEqual(restored.entries.last?.event, .rateConfirmed)
        let hardware = MockRateHardware()
        let rates = OutputSampleRate(hardware: hardware, diagnostics: restored)
        _ = try await rates.match(source: 44100, enabled: true)
        XCTAssertEqual(restored.entries.suffix(3).map(\.event), [.rateObserved, .rateRequested, .rateConfirmed])
        try await rates.restore()
        XCTAssertEqual(restored.entries.last?.event, .rateRestored)
        hardware.fail = true
        do { _ = try await rates.match(source: 44100, enabled: true) } catch { }
        XCTAssertEqual(restored.entries.last?.event, .rateFailed)
        await restored.flush()
        try Data("corrupt log".utf8).write(to: url)
        XCTAssertEqual(AudioDiagnostics(storageURL: url).entries.count, 0)
    }

    @MainActor func verifyHardwareRates() async throws {
        let hardware = CoreAudioRateHardware()
        let device = try hardware.defaultDevice()
        let original = try hardware.rate(device)
        let ranges = try hardware.availableRates(device)
        print("Physical output device \(device): original \(original) Hz; supported \(ranges)")
        let matching = OutputSampleRate(hardware: hardware)
        do {
            for source in [44100.0, 48000, 96000, 192000] {
                let current = try hardware.rate(device)
                let expected = SampleRatePolicy.preferred(source: source, ranges: ranges) ?? current
                let actual = try await matching.match(source: source, enabled: true)
                XCTAssertEqual(actual, expected)
                print("Hardware rate confirmed: source \(source) Hz → nominal \(actual) Hz")
            }
            try await matching.restore()
            XCTAssertEqual(try hardware.rate(device), original)
            print("Hardware original rate restored: \(original) Hz. This is rate verification, not a DAC sample-capture test.")
        } catch {
            try await matching.restore()
            throw error
        }
    }

    @MainActor func testOutputSampleRates() async throws {
        XCTAssertEqual(SampleRatePolicy.preferred(source: 44100, ranges: [44100...44100, 88200...88200]), 44100)
        XCTAssertEqual(SampleRatePolicy.preferred(source: 44100, ranges: [48000...48000, 176400...176400, 88200...88200]), 88200)
        XCTAssertEqual(SampleRatePolicy.preferred(source: 48000, ranges: [96000...192000]), 96000)
        XCTAssertEqual(SampleRatePolicy.preferred(source: 44100, ranges: [48000...48000]), nil)
        XCTAssertEqual(SampleRatePolicy.preferred(source: 0, ranges: [44100...192000]), nil)
        let hardware = MockRateHardware()
        let matching = OutputSampleRate(hardware: hardware)
        let first = try await matching.match(source: 44100, enabled: true)
        XCTAssertEqual(first, 44100)
        _ = try await matching.match(source: 44100, enabled: true)
        XCTAssertEqual(hardware.writes.count, 1) // Same-rate transitions do not touch the device.
        // A mid-song device reset must recover without fighting its new rate.
        hardware.rates[1] = 96000
        let recovered = try await matching.match(source: 44100, enabled: false)
        XCTAssertEqual(recovered, 96000)
        XCTAssertEqual(hardware.writes.count, 1)
        // Recovery must retain the original rate for eventual stop/quit.
        try await matching.restore()
        XCTAssertEqual(hardware.rates[1], 48000)
        _ = try await matching.match(source: 96000, enabled: true)
        try await matching.restore()
        XCTAssertEqual(hardware.rates[1], 48000) // Original, not the preceding track's rate.
        let count = hardware.writes.count
        _ = try await matching.match(source: 44100, enabled: false)
        XCTAssertEqual(hardware.writes.count, count)
        hardware.supported = [48000...48000]
        let fallback = try await matching.match(source: 44100, enabled: true)
        XCTAssertEqual(fallback, 48000)
        XCTAssertEqual(hardware.writes.count, count)
        hardware.supported = [44100...192000]
        hardware.fail = true
        do { _ = try await matching.match(source: 44100, enabled: true); XCTAssertEqual(true, false) }
        catch { }
        hardware.fail = false
        _ = try await matching.match(source: 44100, enabled: true)
        hardware.device = 2
        try await matching.restorePreviousDevices()
        XCTAssertEqual(hardware.rates[1], 48000)
        XCTAssertEqual(hardware.rates[2], 96000)
        _ = try await matching.match(source: 44100, enabled: true)
        hardware.fail = true
        do { try await matching.restore(); XCTAssertEqual(true, false) } catch { }
        hardware.fail = false
        try await matching.restore()
        XCTAssertEqual(hardware.rates[1], 48000)
        XCTAssertEqual(hardware.rates[2], 96000)
        XCTAssertEqual(LibrarySnapshot().volume, 1)
    }

    func testPlaybackQueue() {
        var modes = PlaybackQueue()
        modes.reset(["a", "b"], startingAt: "a")
        modes.cycleMode()
        XCTAssertEqual(modes.isShuffled, true)
        modes.cycleMode()
        XCTAssertEqual(modes.isShuffled, false)
        XCTAssertEqual(modes.isLooping, true)
        XCTAssertEqual(modes.advance(), "b")
        XCTAssertEqual(modes.hasNext, true)
        XCTAssertEqual(modes.advance(), "a")
        modes.cycleMode()
        XCTAssertEqual(modes.isLooping, false)
        XCTAssertEqual(modes.advance(), "b")
        XCTAssertEqual(modes.advance(), nil)
        modes.reset(["solo"], startingAt: "solo")
        modes.cycleMode()
        modes.cycleMode()
        XCTAssertEqual(modes.advance(), "solo")
        modes.remove("solo")
        XCTAssertEqual(modes.hasNext, false)
        XCTAssertEqual(modes.advance(), nil)

        var queue = PlaybackQueue()
        queue.reset(["a", "b", "c"], startingAt: "a")
        queue.enqueue("a", next: true)
        queue.enqueue("d", next: false)
        XCTAssertEqual(queue.upcoming.map(\.trackID), ["a", "b", "c", "d"])
        XCTAssertEqual(queue.advance(), "a")
        XCTAssertEqual(queue.advance(), "b")
        XCTAssertEqual(queue.previous(), "a")
        let current = queue.current
        let upcoming = queue.upcoming
        queue.toggleShuffle()
        XCTAssertEqual(queue.current, current)
        XCTAssertEqual(Set(queue.upcoming.map(\.id)), Set(upcoming.map(\.id)))
        queue.toggleShuffle()
        XCTAssertEqual(queue.upcoming, upcoming)
        queue.enqueue("x", next: true)
        XCTAssertEqual(queue.upcoming.first?.trackID, "x")
        XCTAssertEqual(queue.advance(), "x")
        queue.remove("a")
        XCTAssertEqual(queue.current?.trackID, "x")
        XCTAssertEqual(queue.upcoming.map(\.trackID), ["b", "c", "d"])
        let last = queue.upcoming.last!
        XCTAssertEqual(queue.jump(to: last.id), "d")
        XCTAssertEqual(queue.hasNext, false)
        XCTAssertEqual(queue.advance(), nil)
    }

    func testQueueControls() {
        var queue = PlaybackQueue()
        queue.reset(["history", "current", "duplicate", "b", "duplicate", "c"], startingAt: "current")
        let current = queue.current
        let original = queue.upcoming
        queue.removeUpcoming(original[0].id)
        XCTAssertEqual(queue.upcoming.map(\.trackID), ["b", "duplicate", "c"])
        XCTAssertEqual(queue.upcoming[1].id, original[2].id)
        queue.removeUpcoming(current!.id)
        queue.removeUpcoming(queue.items[0].id)
        XCTAssertEqual(queue.current, current)
        XCTAssertEqual(queue.items.first?.trackID, "history")
        queue.moveUpcoming([original[3].id], before: original[1].id)
        XCTAssertEqual(queue.upcoming.map(\.trackID), ["c", "b", "duplicate"])
        queue.moveUpcoming([original[3].id], before: nil)
        XCTAssertEqual(queue.upcoming.map(\.trackID), ["b", "duplicate", "c"])
        queue.moveUpcoming([original[1].id, original[2].id], before: nil)
        XCTAssertEqual(queue.upcoming.map(\.trackID), ["c", "b", "duplicate"])
        queue.toggleShuffle()
        queue.moveUpcoming([original[3].id], before: nil)
        let manualOrder = queue.upcoming
        queue.toggleShuffle()
        XCTAssertEqual(queue.upcoming, manualOrder)
        XCTAssertEqual(queue.current, current)
        // Stale IDs cannot move/remove the current song or restore removed entries.
        queue.moveUpcoming([current!.id, original[0].id], before: nil)
        XCTAssertEqual(queue.current, current)
        XCTAssertEqual(queue.upcoming, manualOrder)
        queue.cycleMode()
        queue.cycleMode()
        XCTAssertEqual(queue.isLooping, true)
        queue.clearUpcoming()
        XCTAssertEqual(queue.current, current)
        XCTAssertEqual(queue.upcoming.count, 0)
        XCTAssertEqual(queue.hasNext, false)
        XCTAssertEqual(queue.isLooping, false)
        queue.enqueue("new", next: false)
        XCTAssertEqual(queue.nextEntry?.trackID, "new")
        queue.clearUpcoming()
        queue.clearUpcoming()
        XCTAssertEqual(queue.items.map(\.trackID), ["history", "current"])
        var empty = PlaybackQueue()
        empty.clearUpcoming()
        empty.removeUpcoming(UUID())
        empty.moveUpcoming([UUID()], before: nil)
        XCTAssertEqual(empty.items.isEmpty, true)
    }

    func testLyrics() async throws {
        let importedRoot = directory.appendingPathComponent("ImportedLyrics")
        let importSource = directory.appendingPathComponent("chosen.lrc")
        let importSong = directory.appendingPathComponent("song.flac")
        try Data("[00:02]Selected lyrics".utf8).write(to: importSource)
        try ImportedLyrics.save(from: importSource, for: importSong, root: importedRoot)
        let importedFile = ImportedLyrics.file(for: importSong, root: importedRoot)
        XCTAssertEqual(try ImportedLyrics.read(importedFile).lines.first?.time, 2)
        // Empty replacement must leave the previous saved lyrics intact.
        try Data().write(to: importSource)
        do {
            try ImportedLyrics.save(from: importSource, for: importSong, root: importedRoot)
            XCTAssertTrue(false)
        } catch { }
        XCTAssertEqual(try ImportedLyrics.read(importedFile).lines.first?.text, "Selected lyrics")
        try Data("Plain selected lyrics".utf8).write(to: importSource)
        try ImportedLyrics.save(from: importSource, for: importSong, root: importedRoot)
        XCTAssertEqual(try ImportedLyrics.read(importedFile).plainText, "Plain selected lyrics")
        XCTAssertEqual(try ImportedLyrics.mode(for: importSong, root: importedRoot), .draft)
        try ImportedLyrics.setMode(.deleted, for: importSong, root: importedRoot)
        XCTAssertTrue(!FileManager.default.fileExists(atPath: importedFile.path))
        XCTAssertEqual(try ImportedLyrics.mode(for: importSong, root: importedRoot), .deleted)
        try ImportedLyrics.save(LRCParser.parse("New draft"), for: importSong, root: importedRoot)
        XCTAssertEqual(try ImportedLyrics.mode(for: importSong, root: importedRoot), .draft)
        try ImportedLyrics.setMode(.written, for: importSong, root: importedRoot)
        XCTAssertTrue(!FileManager.default.fileExists(atPath: importedFile.path))
        XCTAssertEqual(try ImportedLyrics.mode(for: importSong, root: importedRoot), .written)
        // Replacing a draft repeatedly must retain the last committed source.
        try ImportedLyrics.save(LRCParser.parse("First draft"), for: importSong, root: importedRoot)
        try ImportedLyrics.save(LRCParser.parse("Second draft"), for: importSong, root: importedRoot)
        try ImportedLyrics.discard(for: importSong, root: importedRoot)
        XCTAssertEqual(try ImportedLyrics.mode(for: importSong, root: importedRoot), .written)
        XCTAssertTrue(!FileManager.default.fileExists(atPath: importedFile.path))
        try ImportedLyrics.setMode(.deleted, for: importSong, root: importedRoot)
        try ImportedLyrics.save(LRCParser.parse("Draft after deleting"), for: importSong, root: importedRoot)
        try ImportedLyrics.discard(for: importSong, root: importedRoot)
        XCTAssertEqual(try ImportedLyrics.mode(for: importSong, root: importedRoot), .deleted)
        let localSong = directory.appendingPathComponent("Local song.flac")
        let sidecar = localSong.deletingPathExtension().appendingPathExtension("txt")
        let localData = Data("Local lyrics".utf8)
        try localData.write(to: sidecar)
        try ImportedLyrics.save(LRCParser.parse("Online draft"), for: localSong, root: importedRoot)
        try ImportedLyrics.discard(for: localSong, root: importedRoot)
        XCTAssertEqual(try ImportedLyrics.mode(for: localSong, root: importedRoot), .local)
        XCTAssertEqual(try Data(contentsOf: sidecar), localData)

        let parsed = LRCParser.parse("[ar:Artist]\n[00:01.50][00:03]Repeated\n[00:02]Middle\n[offset:500]\n[00:xx]Bad\n[00:99]Bad")
        XCTAssertEqual(parsed.lines.map(\.time), [1, 1.5, 2.5])
        XCTAssertEqual(parsed.lines.map(\.text), ["Repeated", "Middle", "Repeated"])
        XCTAssertEqual(parsed.currentLine(at: 0.999), nil)
        XCTAssertEqual(parsed.currentLine(at: 1), 0)
        XCTAssertEqual(parsed.currentLine(at: 1.499), 0)
        XCTAssertEqual(parsed.currentLine(at: 1.5), 1)
        XCTAssertEqual(parsed.currentLine(at: 100), 2)
        XCTAssertEqual(parsed.currentLine(at: -.infinity), nil)
        XCTAssertEqual(Lyrics().currentLine(at: 0), nil)
        XCTAssertEqual(LRCParser.parse("[00:00.25]Start\n[offset:-250]").lines.first?.time, 0.5)
        XCTAssertEqual(LRCParser.parse("[ti:Title]\nPlain lyrics").plainText, "Plain lyrics")
        XCTAssertTrue(LRCParser.parse("[00:xx]Malformed").lines.isEmpty)
        let url = try makeTaggedFLAC(name: "Lyrics fixture", tags: ["LYRICS=Embedded words"])
        let original = try Data(contentsOf: url)
        XCTAssertEqual(await LyricsLoader.load(url).plainText, "Embedded words")
        let txt = url.deletingPathExtension().appendingPathExtension("txt")
        let lrc = url.deletingPathExtension().appendingPathExtension("lrc")
        try Data("Text sidecar".utf8).write(to: txt)
        XCTAssertEqual(await LyricsLoader.load(url).plainText, "Text sidecar")
        try Data("[00:01]LRC sidecar".utf8).write(to: lrc)
        XCTAssertEqual(await LyricsLoader.load(url).lines.first?.text, "LRC sidecar")
        try Data("UTF16 words".data(using: .utf16)!).write(to: lrc)
        XCTAssertEqual(await LyricsLoader.load(url).plainText, "UTF16 words")
        XCTAssertEqual(try Data(contentsOf: url), original, "Lyrics lookup must not modify audio")
        let embedded = try makeTaggedFLAC(name: "Synced embedded", tags: ["UNSYNCEDLYRICS=[00:02]Embedded timing"])
        XCTAssertEqual(await LyricsLoader.load(embedded).lines.first?.time, 2)
        let missing = try makeWAV(name: "No lyrics")
        XCTAssertTrue(await LyricsLoader.load(missing).isEmpty)
        let originalAudio = try Data(contentsOf: missing)
        let saved = Lyrics(lines: [.init(time: -0.5, text: "Before — စာသား"), .init(time: 1.234, text: "Timed words"), .init(time: 65.01, text: "")])
        try LyricsWriter.write(saved, beside: missing)
        XCTAssertEqual(await LyricsLoader.load(missing), saved)
        let savedBytes = try Data(contentsOf: LyricsWriter.sidecarURL(for: missing))
        do {
            try LyricsWriter.write(parsed, beside: missing)
            XCTAssertEqual(true, false, "Existing lyrics must require explicit replacement")
        } catch let error as CocoaError {
            XCTAssertEqual(error.code, .fileWriteFileExists)
        }
        XCTAssertEqual(try Data(contentsOf: LyricsWriter.sidecarURL(for: missing)), savedBytes)
        try LyricsWriter.write(parsed, beside: missing, replace: true)
        XCTAssertEqual(await LyricsLoader.load(missing), parsed)
        XCTAssertEqual(try Data(contentsOf: missing), originalAudio, "Saving lyrics must not modify audio")
        let override: LyricsLoader.Source = { _ in Lyrics(plainText: "Future local source") }
        XCTAssertEqual(await LyricsLoader.load(url, sources: [override] + LyricsLoader.sources).plainText, "Future local source")

        // Synthetic ID3v2.4 frames exercise USLT text and SYLT millisecond timing.
        func id3(_ id: String, _ body: [UInt8], name: String) throws -> URL {
            func big(_ n: Int) -> [UInt8] { [UInt8((n >> 24) & 255), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)] }
            let frame = Array(id.utf8) + big(body.count) + [0, 0] + body
            let n = frame.count
            let header: [UInt8] = [73, 68, 51, 4, 0, 0, UInt8((n >> 21) & 127), UInt8((n >> 14) & 127), UInt8((n >> 7) & 127), UInt8(n & 127)]
            let file = directory.appendingPathComponent(name + ".mp3")
            try Data(header + frame).write(to: file)
            return file
        }
        let uslt = try id3("USLT", [3, 101, 110, 103, 0] + Array("Local ID3 words".utf8), name: "USLT")
        XCTAssertEqual(await LyricsLoader.load(uslt).plainText, "Local ID3 words")
        let sylt = try id3("SYLT", [3, 101, 110, 103, 2, 1, 0] + Array("Timed words".utf8) + [0, 0, 0, 3, 232], name: "SYLT")
        XCTAssertEqual(await LyricsLoader.load(sylt).lines.first?.time, 1)
        XCTAssertEqual(await LyricsLoader.load(sylt).lines.first?.text, "Timed words")
    }

    func testAutomaticLyricsSaving() async throws {
        let audio = try makeWAV(name: "Automatic lyrics")
        let original = try Data(contentsOf: audio)
        let plain = Lyrics(plainText: "First line\nစာသား — café")
        XCTAssertTrue(try LyricsWriter.saveIfMissing(plain, beside: audio))
        let txt = LyricsWriter.sidecarURL(for: audio, lyrics: plain)
        XCTAssertEqual(txt.pathExtension, "txt")
        XCTAssertEqual(await LyricsLoader.load(audio), plain)
        let savedText = try Data(contentsOf: txt)
        XCTAssertEqual(try LyricsWriter.saveIfMissing(Lyrics(plainText: "Do not replace"), beside: audio), false)
        XCTAssertEqual(try Data(contentsOf: txt), savedText)
        let synced = Lyrics(lines: [.init(time: 1.25, text: "Synced words")])
        XCTAssertTrue(try LyricsWriter.saveIfMissing(synced, beside: audio))
        XCTAssertEqual(await LyricsLoader.load(audio), synced)
        XCTAssertEqual(try Data(contentsOf: txt), savedText, "Creating LRC must preserve an existing TXT")
        XCTAssertEqual(try LyricsWriter.saveIfMissing(synced, beside: audio), false)
        XCTAssertEqual(try LyricsWriter.saveIfMissing(Lyrics(), beside: audio), false)
        XCTAssertEqual(try Data(contentsOf: audio), original, "Auto-saving must leave audio unchanged")
        let other = try makeWAV(name: "Existing sidecar")
        let sidecar = LyricsWriter.sidecarURL(for: other)
        try Data().write(to: sidecar)
        XCTAssertEqual(try LyricsWriter.saveIfMissing(synced, beside: other), false)
        XCTAssertEqual(try Data(contentsOf: sidecar).count, 0, "Even empty existing files are preserved")
        try FileManager.default.removeItem(at: sidecar)
        try FileManager.default.createSymbolicLink(at: sidecar, withDestinationURL: audio)
        XCTAssertEqual(try LyricsWriter.saveIfMissing(synced, beside: other), false)
        XCTAssertEqual(try Data(contentsOf: audio), original, "Do not follow a sidecar symlink")
        let unavailable = directory.appendingPathComponent("No such folder/song.flac")
        do {
            try LyricsWriter.saveIfMissing(plain, beside: unavailable)
            XCTAssertEqual(true, false, "Write failures must be reported")
        } catch { }
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.contains { $0.hasPrefix(".still-lyrics-") }, false, "Temporary files must be cleaned up")
    }

    func testSavedPlaylists() throws {
        let url = directory.appendingPathComponent("library.playlists.json")
        XCTAssertEqual(try PlaylistStorage.load(from: url), [])
        var playlist = MusicPlaylist(name: "Evening music")
        playlist.add("a"); playlist.add("b"); playlist.add("a"); playlist.add("c")
        XCTAssertEqual(playlist.trackIDs, ["a", "b", "c"], "Adding twice must not duplicate a song")
        playlist.move("c", by: -1)
        XCTAssertEqual(playlist.trackIDs, ["a", "c", "b"])
        playlist.move("a", by: -1)
        playlist.move("b", by: 1)
        XCTAssertEqual(playlist.trackIDs, ["a", "c", "b"], "Boundary moves must do nothing")
        let originalID = playlist.id
        playlist.name = "Quiet evening"
        try PlaylistStorage.save([playlist], to: url)
        XCTAssertEqual(try PlaylistStorage.load(from: url), [playlist])
        XCTAssertEqual(try PlaylistStorage.load(from: url).first?.id, originalID)
        playlist.reconcilePaths(["a": "new-a", "b": "c"])
        XCTAssertEqual(playlist.trackIDs, ["new-a", "c"], "Path repair preserves order and deduplicates")
        playlist.remove("new-a")
        XCTAssertEqual(playlist.trackIDs, ["c"])
        try PlaylistStorage.save([], to: url)
        XCTAssertEqual(try PlaylistStorage.load(from: url), [])
        try Data("invalid json".utf8).write(to: url)
        do {
            _ = try PlaylistStorage.load(from: url)
            XCTAssertEqual(true, false, "A damaged playlist file must be reported, not silently erased")
        } catch { }
    }

    func testLibrarySorting() async throws {
        var ten = try await Track.read(makeWAV(name: "Song 10", rate: 192_000, bits: 24))
        var two = try await Track.read(makeWAV(name: "Song 2", rate: 44_100, bits: 16))
        var last = try await Track.read(makeWAV(name: "Z", rate: 96_000, bits: 24))
        ten.genre = "Rock"; two.genre = "Rock"; last.genre = "Jazz"
        ten.trackNumber = 2; two.trackNumber = 1; last.trackNumber = 1; last.discNumber = 2
        let tracks = [ten, last, two]
        XCTAssertEqual(LibrarySort(field: .title).tracks(tracks, library: tracks).map(\.title), ["Song 2", "Song 10", "Z"])
        XCTAssertEqual(LibrarySort(field: .quality, ascending: false).tracks(tracks, library: tracks).map(\.id), [ten.id, last.id, two.id])
        XCTAssertEqual(LibrarySort(field: .dateAdded, ascending: false).tracks([ten, two], library: tracks).map(\.id), [two.id, ten.id])
        XCTAssertEqual(LibrarySort(field: .trackNumber).tracks(tracks, library: tracks).map(\.id), [two.id, ten.id, last.id])
        let groups = LibraryGrouping.groups(tracks, by: .genres)
        XCTAssertEqual(LibrarySort(field: .songCount, ascending: false).groups(groups).map(\.title), ["Rock", "Jazz"])
        XCTAssertEqual(LibrarySort(field: .name).groups(groups).map(\.title), ["Jazz", "Rock"])
        // Equal-quality tracks still have a deterministic reversible order.
        let ties = [ten, two, last].map { track -> Track in
            var copy = track; copy.trackNumber = nil; copy.discNumber = nil; return copy
        }
        let forward = LibrarySort(field: .trackNumber).tracks(ties, library: tracks).map(\.id)
        XCTAssertEqual(LibrarySort(field: .trackNumber, ascending: false).tracks(ties, library: tracks).map(\.id), Array(forward.reversed()))
        let preferences = ["Songs": LibrarySort(field: .quality, ascending: false), "Albums": LibrarySort(field: .songCount)]
        let snapshot = LibrarySnapshot(tracks: tracks, sortPreferences: preferences)
        let decoded = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.sortPreferences, preferences)
        XCTAssertEqual(LibrarySortField.options(for: .albums), [.title, .songCount])
        XCTAssertTrue(LibrarySortField.options(for: .folders).contains(.path))
    }

    func testHighResolutionWAVPreservesSourceFormat() async throws {
        let url = try makeWAV(name: "High resolution", rate: 192_000, bits: 24)
        let track = try await Track.read(url)
        XCTAssertEqual(track.sampleRate, 192_000)
        XCTAssertEqual(track.bitDepth, 24)
        XCTAssertEqual(track.duration, 0.25, accuracy: 0.001)
        XCTAssertEqual(track.quality, "WAV · 24-bit · 192 kHz")
        XCTAssertEqual(track.bitRate, 9_216_000)
        XCTAssertEqual(track.bitRateLabel, "9216 kbps")
        XCTAssertEqual(track.title, "High resolution")
        let original = try Data(contentsOf: url)
        let encodedTrack = try JSONEncoder().encode(track)
        let details = await TrackDetails.read(for: track)
        XCTAssertEqual(details.channels, 2)
        XCTAssertEqual(details.fileSize, Int64(original.count))
        XCTAssertEqual(details.date, nil)
        XCTAssertEqual(details.taggedTitle, nil)
        XCTAssertEqual(details.taggedArtist, nil)
        XCTAssertEqual(try Data(contentsOf: url), original, "Details must not alter audio files")
        XCTAssertEqual(try JSONDecoder().decode(Track.self, from: encodedTrack), track)
        try assertDecodes(url)
    }

    func testNativeLosslessAndAACDecoders() async throws {
        let source = try makeWAV(name: "Source", rate: 96_000, bits: 24)
        let formats = [("flac", "flac", "flac", "FLAC"), ("m4a", "m4af", "alac", "ALAC"),
                       ("aiff", "AIFF", "BEI24", "AIFF"), ("aac", "adts", "aac", "AAC")]
        for (ext, container, codec, label) in formats {
            let destination = directory.appendingPathComponent("Converted.\(ext)")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            process.arguments = [source.path, destination.path, "-f", container, "-d", codec]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "Conversion to \(label)")
            let track = try await Track.read(destination)
            let details = await TrackDetails.read(for: track)
            XCTAssertEqual(details.channels, 2)
            XCTAssertGreaterThan(details.fileSize ?? 0, 0)
            XCTAssertEqual(track.codec, label)
            XCTAssertGreaterThan(track.bitRate ?? 0, 0, "Encoded bitrate for \(label)")
            if label != "AAC" {
                XCTAssertEqual(track.sampleRate, 96_000)
                XCTAssertEqual(track.bitDepth, 24, "Source depth for \(label)")
            } else { XCTAssertEqual(track.bitDepth, 0, "Lossy audio should not show a source PCM bit depth") }
            try assertDecodes(destination)
        }
    }

    func testFolderImportDeduplicatesAndReportsBrokenFiles() async throws {
        let first = try makeWAV(name: "01 First")
        let second = try makeWAV(name: "02 Second")
        let broken = directory.appendingPathComponent("Broken.flac")
        try Data("invalid audio".utf8).write(to: broken)
        try Data("not music".utf8).write(to: directory.appendingPathComponent("Notes.txt"))
        let result = await LibraryImporter.scan([directory, first], excluding: [second.path])
        XCTAssertEqual(result.tracks.map(\.title), ["01 First"])
        XCTAssertEqual(result.failed, ["Broken.flac"])
    }

    func testSnapshotRoundTripAndMissingFile() async throws {
        let track = try await Track.read(makeWAV(name: "Saved"))
        let location = directory.appendingPathComponent("nested/library.json")
        XCTAssertTrue(try LibraryStorage.load(from: location).tracks.isEmpty)
        try LibraryStorage.save(LibrarySnapshot(tracks: [track], currentID: track.id, position: 0.12, volume: 0.4), to: location)
        let restored = try LibraryStorage.load(from: location)
        XCTAssertEqual(restored.tracks, [track])
        XCTAssertEqual(restored.currentID, track.id)
        XCTAssertEqual(restored.position, 0.12)
        XCTAssertEqual(restored.volume, 0.4)
    }

    func testMissingAudioIsReported() async {
        let result = await LibraryImporter.scan([directory.appendingPathComponent("Missing.mp3")], excluding: [])
        XCTAssertEqual(result.failed, ["Missing.mp3"])
        XCTAssertTrue(result.tracks.isEmpty)
    }

    func testFLACMetadataAndGrouping() async throws {
        let first = try await Track.read(makeTaggedFLAC(name: "Tagged one", tags: ["TITLE=First song", "ARTIST=Singer One", "ALBUM=Shared title", "ALBUMARTIST=The Ensemble", "GENRE=Jazz", "COMPOSER=Jane Writer", "TRACKNUMBER=2/10", "DISCNUMBER=1", "DATE=2024-03-12"]))
        let second = try await Track.read(makeTaggedFLAC(name: "Tagged two", tags: ["TITLE=Second song", "ARTIST=Singer Two", "ALBUM=Shared title", "ALBUMARTIST=The Ensemble", "GENRE=Jazz", "TRACKNUMBER=1"]))
        let details = await TrackDetails.read(for: first)
        XCTAssertEqual(details.date, "2024-03-12")
        XCTAssertEqual(details.channels, 2)
        XCTAssertEqual(details.taggedTitle, "First song")
        XCTAssertEqual(first.title, "First song")
        XCTAssertEqual(first.artist, "Singer One")
        XCTAssertEqual(first.album, "Shared title")
        XCTAssertEqual(first.albumArtist, "The Ensemble")
        XCTAssertEqual(first.genre, "Jazz")
        XCTAssertEqual(first.composer, "Jane Writer")
        XCTAssertEqual(first.trackNumber, 2)
        XCTAssertEqual(first.discNumber, 1)
        let album = LibraryGrouping.groups([first, second], by: .albums)
        XCTAssertEqual(album.count, 1, "Album artist keeps compilation tracks together")
        XCTAssertEqual(album.first?.tracks.map(\.title), ["Second song", "First song"])
        var otherArtist = first
        otherArtist.albumArtist = "Another band"
        XCTAssertEqual(LibraryGrouping.groups([first, otherArtist], by: .albums).count, 2)
        XCTAssertEqual(LibraryGrouping.groups([first, second], by: .genres).first?.title, "Jazz")
        XCTAssertEqual(LibraryGrouping.groups([first, second], by: .composers).count, 2)
        XCTAssertEqual(LibraryGrouping.groups([first, second], by: .folders).count, 1)
        var tagged = first
        tagged.genre = "R&B"
        XCTAssertEqual(LibraryGrouping.groups([tagged], by: .genres).map(\.title), ["R&B"])
        tagged.genre = "R&B/Soul; r&b; R & B; Contemporary R&B; Rock & Pop"
        let genres = LibraryGrouping.groups([tagged], by: .genres)
        XCTAssertEqual(Set(genres.map(\.title)), Set(["R&B", "Soul", "Contemporary R&B", "Rock", "Pop"]))
        XCTAssertEqual(genres.first(where: { $0.title == "R&B" })?.tracks.count, 1)
        tagged.composer = "R & B; Jane/John"
        XCTAssertEqual(Set(LibraryGrouping.groups([tagged], by: .composers).map(\.title)), Set(["R", "B", "Jane", "John"]))
    }

    func testEmbeddedLyricsEditing() async throws {
        let flac = try makeTaggedFLAC(name: "Edit embedded", tags: ["TITLE=Keep title", "ARTIST=Keep artist", "LYRICS=Old lyrics", "UNSYNCEDLYRICS=Older lyrics", "COMMENT=Keep comment"])
        let cover = try makeCover(red: 130)
        try FLACArtworkWriter.write(cover, to: flac)
        let mp3 = directory.appendingPathComponent("Edit embedded.mp3")
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Vendor/taglib-2.2.1/tests/data/lame_cbr.mp3")
        try FileManager.default.copyItem(at: fixture, to: mp3)
        let m4a = directory.appendingPathComponent("Native tags.m4a")
        let synced = LRCParser.parse("[00:00.50]First line\n[00:01.25]မြန်မာ Unicode café 🎵")
        let plain = LRCParser.parse("New plain lyrics\nSecond line")
        func audioPayload(_ url: URL) throws -> Data {
            let data = try Data(contentsOf: url)
            if url.pathExtension == "flac" {
                var offset = 4
                while offset + 4 <= data.count {
                    let last = data[offset] & 0x80 != 0
                    let size = Int(data[offset + 1]) << 16 | Int(data[offset + 2]) << 8 | Int(data[offset + 3])
                    offset += 4 + size
                    if last { return Data(data[offset...]) }
                }
            } else if url.pathExtension == "mp3" {
                var start = 0
                while start + 10 <= data.count, data[start..<start + 3] == Data("ID3".utf8) {
                    let size = data[start + 6..<start + 10].reduce(0) { ($0 << 7) | Int($1 & 127) }
                    let footer = data[start + 3] == 4 && data[start + 5] & 0x10 != 0 ? 10 : 0
                    start += 10 + size + footer
                }
                var end = data.count
                if end >= 128, data[end - 128..<end - 125] == Data("TAG".utf8) { end -= 128 }
                return Data(data[start..<end])
            } else {
                var offset = 0, payload = Data()
                while offset + 8 <= data.count {
                    func number(_ range: Range<Int>) -> UInt64 { data[range].reduce(0) { ($0 << 8) | UInt64($1) } }
                    var size = Int(number(offset..<offset + 4)), header = 8
                    if size == 1 { size = Int(number(offset + 8..<offset + 16)); header = 16 }
                    if size == 0 { size = data.count - offset }
                    guard size >= header, offset + size <= data.count else { throw CocoaError(.fileReadCorruptFile) }
                    if data[offset + 4..<offset + 8] == Data("mdat".utf8) { payload.append(data[offset + header..<offset + size]) }
                    offset += size
                }
                return payload
            }
            throw CocoaError(.fileReadCorruptFile)
        }
        for url in [flac, mp3, m4a] {
            let originalPayload = try audioPayload(url)
            XCTAssertGreaterThan(originalPayload.count, 0)
            let tags = try await Track.read(url)
            let artwork = await Track.artwork(for: url)
            let originalFile = try Data(contentsOf: url)
            let drafts = directory.appendingPathComponent("Drafts")
            try ImportedLyrics.save(synced, for: url, root: drafts)
            XCTAssertEqual(try Data(contentsOf: url), originalFile, "Preparing lyrics must never write to audio")
            try EmbeddedLyricsWriter.write(synced, to: url)
            XCTAssertEqual(await LyricsLoader.embedded(url), synced, "Embedded synced lyrics round trip: \(url.pathExtension)")
            XCTAssertEqual(try audioPayload(url), originalPayload, "Encoded audio unchanged after writing: \(url.pathExtension)")
            try EmbeddedLyricsWriter.write(plain, to: url)
            XCTAssertEqual(await LyricsLoader.embedded(url), plain, "Replace synced with plain: \(url.pathExtension)")
            try EmbeddedLyricsWriter.write(nil, to: url)
            XCTAssertTrue((await LyricsLoader.embedded(url))?.isEmpty != false)
            XCTAssertEqual(try audioPayload(url), originalPayload, "Encoded audio unchanged after deletion: \(url.pathExtension)")
            let after = try await Track.read(url)
            XCTAssertEqual(after.title, tags.title)
            XCTAssertEqual(after.artist, tags.artist)
            XCTAssertEqual(after.album, tags.album)
            XCTAssertEqual(await Track.artwork(for: url), artwork)
            try assertDecodes(url)
            let unchanged = try Data(contentsOf: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
            do { try EmbeddedLyricsWriter.write(plain, to: url); XCTAssertTrue(false) } catch { }
            XCTAssertEqual(try Data(contentsOf: url), unchanged)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        }
        let invalid = directory.appendingPathComponent("Invalid write.flac")
        let invalidData = Data("not a flac".utf8)
        try invalidData.write(to: invalid)
        do { try EmbeddedLyricsWriter.write(plain, to: invalid); XCTAssertTrue(false) } catch { }
        XCTAssertEqual(try Data(contentsOf: invalid), invalidData)
        let unsupported = try makeWAV(name: "Unsupported write")
        let original = try Data(contentsOf: unsupported)
        do { try EmbeddedLyricsWriter.write(plain, to: unsupported); XCTAssertTrue(false) } catch { }
        XCTAssertEqual(try Data(contentsOf: unsupported), original)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".still-lyrics-") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testM4AMetadata() async throws {
        let source = try makeWAV(name: "Native metadata")
        let destination = directory.appendingPathComponent("Native tags.m4a")
        let exporter = try XCTUnwrap(AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetAppleM4A))
        exporter.outputURL = destination
        exporter.outputFileType = .m4a
        let values: [(AVMetadataIdentifier, String)] = [(.commonIdentifierTitle, "A tagged song"), (.commonIdentifierArtist, "Soloist"), (.commonIdentifierAlbumName, "Night Music"), (.iTunesMetadataAlbumArtist, "House Band"), (.iTunesMetadataUserGenre, "Ambient"), (.iTunesMetadataComposer, "A. Composer"), (.iTunesMetadataLyrics, "Embedded M4A words")]
        exporter.metadata = values.map { identifier, value in
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            return item
        }
        let coverData = try makeCover(red: 100)
        let cover = AVMutableMetadataItem()
        cover.identifier = .commonIdentifierArtwork
        cover.value = coverData as NSData
        cover.dataType = kCMMetadataBaseDataType_PNG as String
        exporter.metadata?.append(cover)
        await exporter.export()
        if let error = exporter.error { throw error }
        let track = try await Track.read(destination)
        XCTAssertEqual(track.title, "A tagged song")
        XCTAssertEqual(track.album, "Night Music")
        XCTAssertEqual(track.artist, "Soloist")
        XCTAssertEqual(track.albumArtist, "House Band")
        XCTAssertEqual(track.genre, "Ambient")
        XCTAssertEqual(track.composer, "A. Composer")
        XCTAssertEqual(await LyricsLoader.load(destination).plainText, "Embedded M4A words")
        XCTAssertEqual(await Track.artwork(for: destination), coverData)
    }

    func testFLACArtwork() async throws {
        let url = try makeTaggedFLAC(name: "Picture blocks", tags: ["TITLE=Artwork test"])
        let originalRate = try await Track.read(url).bitRate
        let back = try makeCover(red: 20)
        let front = try makeCover(red: 200)
        try appendPicture(url, type: 4, image: back)
        XCTAssertEqual(await Track.artwork(for: url), back, "Use another embedded image if no front cover exists")
        try appendPicture(url, type: 3, image: front)
        XCTAssertEqual(await Track.artwork(for: url), front, "Prefer the front cover over the back cover")
        let track = try await Track.read(url)
        XCTAssertEqual(track.title, "Artwork test", "Pictures must not break tag parsing")
        XCTAssertEqual(track.bitRate, originalRate, "Embedded pictures must not inflate audio bitrate")
        try assertDecodes(url)
        let missing = try makeWAV(name: "No artwork")
        XCTAssertTrue(await Track.artwork(for: missing) == nil)
        let malformed = directory.appendingPathComponent("Malformed picture.flac")
        try Data([0x66, 0x4c, 0x61, 0x43, 0x86, 0, 0, 4, 0xff, 0xff, 0xff, 0xff]).write(to: malformed)
        XCTAssertTrue(await Track.artwork(for: malformed) == nil)
    }

    func testFLACCoverWriting() async throws {
        let url = try makeTaggedFLAC(name: "Write cover", tags: ["TITLE=Preserve tags", "ARTIST=Artist", "LYRICS=Local words"])
        let back = try makeCover(red: 40)
        try appendPicture(url, type: 4, image: back)
        func parts(_ data: Data) throws -> (Data, [Data]) {
            var position = 4, blocks: [Data] = []
            while position + 4 <= data.count {
                let last = data[position] & 128 != 0
                let kind = data[position] & 127
                let length = Int(data[position + 1]) << 16 | Int(data[position + 2]) << 8 | Int(data[position + 3])
                let body = data.subdata(in: (position + 4)..<(position + 4 + length))
                if kind != 6 || body.prefix(4) != Data([0, 0, 0, 3]) { blocks.append(Data([kind]) + body) }
                position += length + 4
                if last { return (data.subdata(in: position..<data.count), blocks) }
            }
            throw FLACArtworkWriter.WriteError.invalidFile
        }
        let before = try parts(Data(contentsOf: url))
        let cover = try makeCover(red: 180)
        try FLACArtworkWriter.write(cover, to: url)
        XCTAssertEqual(await Track.artwork(for: url), cover)
        let after = try parts(Data(contentsOf: url))
        XCTAssertEqual(after.0, before.0, "FLAC audio frames must remain byte-for-byte identical")
        XCTAssertEqual(after.1, before.1, "Preserve tags, STREAMINFO, padding and other pictures")
        XCTAssertEqual(try await Track.read(url).title, "Preserve tags")
        try assertDecodes(url)
        try FLACArtworkWriter.write(back, to: url)
        XCTAssertEqual(await Track.artwork(for: url), back)
        XCTAssertEqual(try parts(Data(contentsOf: url)).0, before.0)
        let saved = try Data(contentsOf: url)
        do { try FLACArtworkWriter.write(Data("not an image".utf8), to: url); XCTAssertTrue(false) } catch { }
        XCTAssertEqual(try Data(contentsOf: url), saved)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        do { try FLACArtworkWriter.write(cover, to: url); XCTAssertTrue(false) } catch { }
        XCTAssertEqual(try Data(contentsOf: url), saved)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    }

    func testOnlineMetadata() async throws {
        let url = try makeTaggedFLAC(name: "Online fixture", tags: ["TITLE=Title", "ARTIST=Artist", "ALBUM=Album"])
        let track = try await Track.read(url)
        let transport = MetadataTransport(duration: track.duration)
        let service = OnlineMetadata(fetch: { request, _ in try await transport.fetch(request) })
        let lyrics = try await service.lyrics(for: track)
        XCTAssertEqual(lyrics.lines.count, 1)
        XCTAssertEqual(lyrics.lines.first?.text, "Timed words")
        let plainLocal = Lyrics(plainText: "Local words")
        XCTAssertEqual(plainLocal.preferringSynced(lyrics), lyrics)
        XCTAssertEqual(plainLocal.preferringSynced(Lyrics(plainText: "Online plain")), plainLocal)
        XCTAssertEqual(plainLocal.preferringSynced(Lyrics()), plainLocal)
        XCTAssertEqual(lyrics.preferringSynced(Lyrics(lines: [.init(time: 2, text: "Other")])), lyrics)
        XCTAssertEqual(Lyrics().preferringSynced(Lyrics(plainText: "Online plain")).plainText, "Online plain")
        _ = try await service.lyrics(for: track)
        XCTAssertEqual(await transport.count(), 1)
        let requests = await transport.urls()
        XCTAssertEqual(requests.contains { $0.contains(url.path) }, false)
        let lyricQuery = URLComponents(string: requests[0])!.queryItems!.map(\.name)
        XCTAssertEqual(Set(lyricQuery), Set(["track_name", "artist_name"]))
        let local = await LyricsLoader.load(url, sources: [{ _ in Lyrics(plainText: "Local") }, { _ in
            try? await service.lyrics(for: track)
        }])
        XCTAssertEqual(local.plainText, "Local")
        XCTAssertEqual(await transport.count(), 1)
        let cancelled = Task { try Task.checkCancellation(); return try await service.lyrics(for: track) }
        cancelled.cancel()
        _ = try? await cancelled.value
        XCTAssertEqual(await transport.count(), 1)
    }

    private func makeCover(red: UInt8) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 8, bitsPerPixel: 32))
        let bytes = try XCTUnwrap(bitmap.bitmapData)
        for offset in stride(from: 0, to: 16, by: 4) {
            bytes[offset] = red; bytes[offset + 1] = 80; bytes[offset + 2] = 120; bytes[offset + 3] = 255
        }
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func appendPicture(_ url: URL, type: Int, image: Data) throws {
        let original = try Data(contentsOf: url)
        var output = Data("fLaC".utf8)
        var offset = 4
        while offset + 4 <= original.count {
            let flag = original[offset]
            let size = Int(original[offset+1]) << 16 | Int(original[offset+2]) << 8 | Int(original[offset+3])
            output.append(flag & 0x7f)
            output.append(original[(offset+1)..<(offset+4+size)])
            offset += 4 + size
            if flag & 0x80 != 0 { break }
        }
        var payload = Data()
        func number(_ value: Int) { for shift in [24, 16, 8, 0] { payload.append(UInt8(truncatingIfNeeded: value >> shift)) } }
        func field(_ bytes: Data) { number(bytes.count); payload.append(bytes) }
        number(type); field(Data("image/png".utf8)); field(Data())
        number(2); number(2); number(32); number(0); field(image)
        output.append(0x86)
        for shift in [16, 8, 0] { output.append(UInt8(truncatingIfNeeded: payload.count >> shift)) }
        output.append(payload); output.append(original[offset...])
        try output.write(to: url)
    }

    func testLegacyLibraryAndPreferences() async throws {
        let track = try await Track.read(makeWAV(name: "Legacy"))
        let snapshot = LibrarySnapshot(tracks: [track], currentID: track.id, position: 0.1, favoriteIDs: [track.id], theme: "black")
        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        XCTAssertEqual(restored.theme, "black")
        XCTAssertEqual(restored.favoriteIDs, [track.id])
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "theme")
        legacy.removeValue(forKey: "favoriteIDs")
        var legacyTrack = try XCTUnwrap((legacy["tracks"] as? [[String: Any]])?.first)
        for key in ["albumArtist", "genre", "composer", "trackNumber", "discNumber", "metadataVersion", "bitRate"] { legacyTrack.removeValue(forKey: key) }
        legacy["tracks"] = [legacyTrack]
        let old = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(old.tracks.count, 1)
        XCTAssertEqual(old.currentID, track.id)
        XCTAssertTrue(old.tracks[0].metadataVersion == nil)
        XCTAssertTrue(old.tracks[0].bitRate == nil)
        XCTAssertTrue(old.favoriteIDs == nil)
    }

    private func makeTaggedFLAC(name: String, tags: [String]) throws -> URL {
        let source = try makeWAV(name: name)
        let destination = directory.appendingPathComponent("\(name).flac")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = [source.path, destination.path, "-f", "flac", "-d", "flac"]
        try process.run(); process.waitUntilExit()
        let original = try Data(contentsOf: destination)
        var output = Data("fLaC".utf8)
        var offset = 4
        while offset + 4 <= original.count {
            let flag = original[offset]
            let size = Int(original[offset+1]) << 16 | Int(original[offset+2]) << 8 | Int(original[offset+3])
            if flag & 0x7f != 4 {
                output.append(flag & 0x7f)
                output.append(original[(offset+1)..<(offset+4+size)])
            }
            offset += 4 + size
            if flag & 0x80 != 0 { break }
        }
        var payload = Data()
        func number(_ value: Int) { for shift in [0, 8, 16, 24] { payload.append(UInt8(truncatingIfNeeded: value >> shift)) } }
        func string(_ value: String) { let bytes = Data(value.utf8); number(bytes.count); payload.append(bytes) }
        string("Still test fixture"); number(tags.count)
        for tag in tags { string(tag) }
        output.append(0x84)
        for shift in [16, 8, 0] { output.append(UInt8(truncatingIfNeeded: payload.count >> shift)) }
        output.append(payload)
        output.append(original[offset...])
        try output.write(to: destination)
        return destination
    }

    private func assertDecodes(_ url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024))
        try file.read(into: buffer)
        XCTAssertGreaterThan(buffer.frameLength, 0)
        let player = try AVAudioPlayer(contentsOf: url)
        XCTAssertGreaterThan(player.duration, 0)
    }

    private func makeWAV(name: String, rate: Int = 44_100, bits: Int = 16, frequency: Double = 440) throws -> URL {
        let frames = rate / 4
        let bytesPerSample = bits / 8
        let dataSize = frames * 2 * bytesPerSample
        var data = Data()
        func append<T: FixedWidthInteger>(_ number: T) {
            var little = number.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8); append(UInt32(36 + dataSize))
        data.append(contentsOf: "WAVEfmt ".utf8); append(UInt32(16))
        append(UInt16(1)); append(UInt16(2)); append(UInt32(rate))
        append(UInt32(rate * 2 * bytesPerSample)); append(UInt16(2 * bytesPerSample)); append(UInt16(bits))
        data.append(contentsOf: "data".utf8); append(UInt32(dataSize))
        // A quiet synthetic sine wave; no copyrighted fixtures or user files.
        for frame in 0..<frames {
            let sample = Int32(sin(Double(frame) * 2 * .pi * frequency / Double(rate)) * Double((1 << (bits - 1)) - 1) * 0.01)
            for _ in 0..<2 {
                for byte in 0..<bytesPerSample { data.append(UInt8(truncatingIfNeeded: sample >> (byte * 8))) }
            }
        }
        let url = directory.appendingPathComponent("\(name).wav")
        try data.write(to: url)
        return url
    }
}

// A standalone harness keeps verification runnable with just Command Line
// Tools, which do not bundle XCTest on every macOS release.
private var failures = 0
private func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "") {
    if actual != expected { failures += 1; print("FAIL: \(actual) != \(expected). \(message)") }
}
private func XCTAssertEqual(_ actual: Double, _ expected: Double, accuracy: Double) {
    if abs(actual - expected) > accuracy { failures += 1; print("FAIL: \(actual) != \(expected) ± \(accuracy)") }
}
private func XCTAssertTrue(_ value: Bool) {
    if !value { failures += 1; print("FAIL: expected true") }
}
private func XCTAssertGreaterThan<T: Comparable>(_ actual: T, _ minimum: T, _ message: String = "") {
    if actual <= minimum { failures += 1; print("FAIL: \(actual) must exceed \(minimum). \(message)") }
}
private func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "StillChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected nil"]) }
    return value
}

@main
struct StillChecks {
    static func main() async {
        let suite = AudioTests()
        do {
            try suite.setUpWithError()
            defer { try? suite.tearDownWithError() }
            try await suite.testHighResolutionWAVPreservesSourceFormat()
            try await suite.testNativeLosslessAndAACDecoders()
            // Separate fixtures for folder enumeration.
            try suite.tearDownWithError()
            try suite.setUpWithError()
            try await suite.testFolderImportDeduplicatesAndReportsBrokenFiles()
            try await suite.testSnapshotRoundTripAndMissingFile()
            await suite.testMissingAudioIsReported()
            try await suite.testFLACMetadataAndGrouping()
            try await suite.testM4AMetadata()
            try await suite.testEmbeddedLyricsEditing()
            try await suite.testLegacyLibraryAndPreferences()
            try await suite.testFLACArtwork()
            try await suite.testFLACCoverWriting()
            try await suite.testOnlineMetadata()
            try await suite.testLibrarySorting()
            try await suite.testLyrics()
            try await suite.testAutomaticLyricsSaving()
            try suite.testSavedPlaylists()
            suite.testPlaybackQueue()
            suite.testQueueControls()
            try await suite.testOutputSampleRates()
            try await suite.testEngineRendering()
            try await suite.testGaplessOutput()
            try await suite.testQueueEditsPreserveAudio()
            try await suite.testAudioDiagnostics()
            try await suite.testWatchedFolders()
            try await suite.testMovedLibraryPaths()
            if CommandLine.arguments.contains("--verify-output-rates") { try await suite.verifyHardwareRates() }
            if CommandLine.arguments.contains("--export-fixtures") { try suite.exportUIFixtures() }
        } catch { failures += 1; print("FAIL: \(error)") }
        print(failures == 0 ? "PASS: all 25 audio, artwork, metadata, grouping, sorting, lyrics, queue, and library checks" : "FAILED: \(failures) checks")
        exit(failures == 0 ? 0 : 1)
    }
}

@MainActor private final class MockRateHardware: OutputRateHardware {
    var device: AudioDeviceID = 1
    var rates: [AudioDeviceID: Double] = [1: 48000, 2: 96000]
    var supported: [ClosedRange<Double>] = [44100...192000]
    var writes: [Double] = []
    var fail = false
    func defaultDevice() throws -> AudioDeviceID { device }
    func rate(_ device: AudioDeviceID) throws -> Double { rates[device]! }
    func availableRates(_ device: AudioDeviceID) throws -> [ClosedRange<Double>] { supported }
    func setRate(_ rate: Double, device: AudioDeviceID) async throws {
        if fail { throw RateError.timeout }
        await Task.yield()
        rates[device] = rate
        writes.append(rate)
    }
}

private actor MetadataTransport {
    let duration: Double
    var requests: [String] = []
    init(duration: Double) { self.duration = duration }
    func count() -> Int { requests.count }
    func urls() -> [String] { requests }
    func fetch(_ request: URLRequest) throws -> Data {
        let url = request.url!
        requests.append(url.absoluteString)
        if url.host == "lrclib.net" {
            return try JSONSerialization.data(withJSONObject: [
                ["trackName": "Different", "artistName": "Artist", "duration": duration, "plainLyrics": "Wrong"],
                ["trackName": "Title", "artistName": "Artist", "albumName": "Album", "duration": duration, "plainLyrics": "Plain album match"],
                ["trackName": "Title", "artistName": "Artist", "albumName": "Other album", "duration": duration, "syncedLyrics": "[00:01]Timed words"]])
        }
        throw URLError(.unsupportedURL)
    }
}
