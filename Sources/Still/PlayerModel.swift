import AppKit
import AVFoundation
import MediaPlayer
import StillCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PlayerModel: NSObject, ObservableObject {
    @Published private(set) var tracks: [Track] = [] {
        didSet { ArtworkStore.shared.configure(tracks: tracks, root: storageURL.deletingPathExtension().appendingPathExtension("covers")) }
    }
    @Published var findLyricsOnline = UserDefaults.standard.bool(forKey: "StillFindLyricsOnline") {
        didSet {
            UserDefaults.standard.set(findLyricsOnline, forKey: "StillFindLyricsOnline")
            if let current { loadLyrics(current) }
        }
    }
    @Published var writeCoversIntoFiles = UserDefaults.standard.bool(forKey: "StillWriteCoversIntoFiles") {
        didSet { UserDefaults.standard.set(writeCoversIntoFiles, forKey: "StillWriteCoversIntoFiles") }
    }
    @Published private(set) var savingCover = false
    private var choosingCover = false
    private let onlineMetadata = OnlineMetadata()

    @Published private(set) var currentID: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var artwork: NSImage?
    @Published private(set) var lyrics = Lyrics()
    @Published private(set) var loadingLyrics = false
    @Published private(set) var savingLyrics = false
    @Published private(set) var uploadingLyrics = false
    @Published private(set) var canDeleteLyrics = false
    @Published private(set) var hasUnsavedLyrics = false
    private var importedLyricsRoot: URL { storageURL.deletingPathExtension().appendingPathExtension("lyrics") }
    @Published private(set) var savedLyricsTrackID: String?
    private var savedLyricsNoticeTask: Task<Void, Never>?
    @Published private(set) var importing = false
    @Published var message: String?
    @Published var search = ""
    @Published var section: LibrarySection = .songs { didSet { selectedGroupID = nil; selectedPlaylistID = nil; search = "" } }
    @Published var selectedGroupID: String?
    @Published private(set) var playlists: [MusicPlaylist] = []
    @Published private(set) var selectedPlaylistID: UUID?
    private var playlistsReadable = true
    private var playlistsURL: URL { storageURL.deletingPathExtension().appendingPathExtension("playlists.json") }
    var selectedPlaylist: MusicPlaylist? { playlists.first { $0.id == selectedPlaylistID } }
    func openPlaylist(_ id: UUID) { section = .playlist; selectedPlaylistID = id }
    private func commitPlaylists(_ updated: [MusicPlaylist]) throws {
        guard playlistsReadable else { throw NSError(domain: "StillPlaylists", code: 1, userInfo: [NSLocalizedDescriptionKey: "The saved playlists could not be read. Restore the playlist file before editing it."]) }
        try PlaylistStorage.save(updated, to: playlistsURL)
        playlists = updated
    }
    func editPlaylistName(_ name: String, id: UUID? = nil, adding track: Track? = nil) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw NSError(domain: "StillPlaylists", code: 2, userInfo: [NSLocalizedDescriptionKey: "Enter a playlist name."]) }
        guard !playlists.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(clean) == .orderedSame }) else {
            throw NSError(domain: "StillPlaylists", code: 3, userInfo: [NSLocalizedDescriptionKey: "A playlist with that name already exists."])
        }
        var updated = playlists
        if let id {
            guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
            updated[index].name = clean
            try commitPlaylists(updated)
        } else {
            let playlist = MusicPlaylist(name: clean, trackIDs: track.map { [$0.id] } ?? [])
            updated.append(playlist)
            try commitPlaylists(updated)
            openPlaylist(playlist.id)
        }
    }
    func deletePlaylist(_ id: UUID) {
        do {
            try commitPlaylists(playlists.filter { $0.id != id })
            if selectedPlaylistID == id { section = .favorites }
        } catch { message = "Couldn’t delete playlist. \(error.localizedDescription)" }
    }
    func updatePlaylistSongs(_ id: UUID, selected: Set<String>) throws {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        var updated = playlists
        updated[index].trackIDs.removeAll { !selected.contains($0) }
        for track in tracks where selected.contains(track.id) { updated[index].add(track.id) }
        try commitPlaylists(updated)
    }
    func addToPlaylist(_ track: Track, id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        var updated = playlists
        updated[index].add(track.id)
        do { try commitPlaylists(updated) } catch { message = "Couldn’t add song to playlist. \(error.localizedDescription)" }
    }
    func removeFromPlaylist(_ track: Track, id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        var updated = playlists
        updated[index].remove(track.id)
        do { try commitPlaylists(updated) } catch { message = "Couldn’t update playlist. \(error.localizedDescription)" }
    }
    func movePlaylistSong(_ track: Track, by offset: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == selectedPlaylistID }) else { return }
        var updated = playlists
        updated[index].move(track.id, by: offset)
        do { try commitPlaylists(updated) } catch { message = "Couldn’t reorder playlist. \(error.localizedDescription)" }
    }
    @Published private var sortPreferences: [String: LibrarySort] = [:]
    @Published private(set) var favoriteIDs: Set<String> = []
    @Published private(set) var refreshing = false
    @Published private(set) var artworkRevision = 0
    @Published var theme = "light" { didSet { save() } }

    @Published private(set) var preparingPlayback = false
    // Hidden debugging override; existing UI preferences no longer disable matching.
    private var matchOutputRate: Bool { UserDefaults.standard.object(forKey: "StillDebugMatchOutputSampleRate") as? Bool ?? true }
    private var retiringPlayers: [EnginePlayback] = []
    private var deviceMonitor: OutputDeviceMonitor?
    private var shuttingDown = false
    private var player: EnginePlayback?
    private let diagnostics: AudioDiagnostics
    private let outputRate: OutputSampleRate
    private var audioOperation: Task<Void, Never>?

    private func enqueueAudioOperation(_ operation: @escaping @MainActor () async -> Void) {
        let previous = audioOperation
        previous?.cancel()
        audioOperation = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await self.drainPlayers()
            guard !Task.isCancelled else { return }
            await operation()
        }
    }
    private func stopRendering() {
        position = player?.currentTime ?? position
        if let player {
            player.onConfigurationChange = nil
            player.onCompletion = nil
            player.onAdvance = nil
            player.onNeedsNext = nil
            retiringPlayers.append(player)
        }
        player = nil
        isPlaying = false
        preparingPlayback = false
    }
    private func drainPlayers() async {
        let retiring = retiringPlayers
        retiringPlayers.removeAll()
        for audio in retiring { await audio.fadeOutAndStop() }
    }
    private func restoreOutputRate() async { try? await outputRate.restore() }

    private func outputDeviceChanged(matchRate: Bool = true) {
        guard !shuttingDown else { return }
        diagnostics.record(matchRate ? .deviceChanged : .engineConfigurationChanged)
        let resume = isPlaying || preparingPlayback
        // A configuration change can invalidate the engine's render timeline.
        // Keep the last observed position if its clock has already reset.
        let time = matchRate ? (player?.currentTime ?? position) : max(position, player?.currentTime ?? position)
        stopRendering()
        preparingPlayback = resume
        enqueueAudioOperation { [weak self] in
            guard let self else { return }
            try? await self.outputRate.restorePreviousDevices()
            guard !Task.isCancelled else { return }
            if resume, let track = self.current { await self.startPlayback(track, at: time, matchRate: matchRate) }
        }
    }
    func shutdown() async {
        shuttingDown = true
        folderScanTimer?.invalidate()
        folderScanTask?.cancel()
        deviceMonitor = nil
        stopRendering()
        audioOperation?.cancel()
        await audioOperation?.value
        await drainPlayers()
        await restoreOutputRate()
        diagnostics.record(.playbackStopped)
        await diagnostics.flush()
        save()
    }
    private var watchedFolders = WatchedFolders()
    @Published private(set) var scanningFolders = false
    private var folderScanTask: Task<Void, Never>?
    private var folderScanTimer: Timer?
    private var lastFolderScan = Date.distantPast
    private var foldersURL: URL { storageURL.deletingPathExtension().appendingPathExtension("folders.json") }
    private var timer: Timer?
    private var artworkTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private let storageURL: URL
    private var ticks = 0
    @Published private(set) var queue = PlaybackQueue()
    private var choosingFiles = false
    var current: Track? { tracks.first { $0.id == currentID } }
    var groups: [LibraryGroup] { LibraryGrouping.groups(tracks, by: section) }
    var selectedGroup: LibraryGroup? { groups.first { $0.id == selectedGroupID } }
    private var sortKey: String { section.rawValue + (selectedGroupID == nil ? "" : ".tracks") }
    var sortOptions: [LibrarySortField] { LibrarySortField.options(for: section, inGroup: selectedGroupID != nil) }
    var librarySort: LibrarySort {
        sortPreferences[sortKey] ?? LibrarySort(field: selectedGroupID != nil && section == .albums ? .trackNumber
            : (section.isGrouped && selectedGroupID == nil ? (section == .albums ? .title : .name) : .dateAdded))
    }
    func setSortField(_ field: LibrarySortField) {
        guard sortOptions.contains(field) else { return }
        sortPreferences[sortKey] = LibrarySort(field: field, ascending: librarySort.ascending)
        save()
    }
    func setSortAscending(_ ascending: Bool) {
        sortPreferences[sortKey] = LibrarySort(field: librarySort.field, ascending: ascending)
        save()
    }
    var visibleGroups: [LibraryGroup] {
        librarySort.groups(groups.filter { search.isEmpty || "\($0.title) \($0.subtitle)".localizedCaseInsensitiveContains(search)
            || $0.tracks.contains(where: matchesSearch) })
    }
    private func matchesSearch(_ track: Track) -> Bool {
        search.isEmpty || "\(track.title) \(track.artist) \(track.album) \(track.albumArtist ?? "") \(track.genre ?? "") \(track.composer ?? "")".localizedCaseInsensitiveContains(search)
    }
    var visibleTracks: [Track] {
        if section == .playlist {
            let indexed = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return (selectedPlaylist?.trackIDs ?? []).compactMap { indexed[$0] }.filter(matchesSearch)
        }
        let base = selectedGroup?.tracks ?? (section == .favorites ? tracks.filter { favoriteIDs.contains($0.id) } : tracks)
        return librarySort.tracks(base.filter(matchesSearch), library: tracks)
    }
    func play(_ track: Track) {
        queue.reset(visibleTracks.map(\.id), startingAt: track.id)
        select(track)
    }
    func enqueue(_ track: Track, next: Bool) {
        player?.synchronizeQueueBoundary()
        if let current, queue.current?.trackID != current.id { queue.reset(tracks.map(\.id), startingAt: current.id) }
        queue.enqueue(track.id, next: next)
        refreshScheduledNext()
    }
    func cyclePlaybackMode() { player?.synchronizeQueueBoundary(); queue.cycleMode(); refreshScheduledNext() }
    func removeQueueEntry(_ id: UUID) {
        player?.synchronizeQueueBoundary()
        queue.removeUpcoming(id)
        refreshScheduledNext()
    }
    func clearQueue() {
        player?.synchronizeQueueBoundary()
        queue.clearUpcoming()
        refreshScheduledNext()
    }
    func moveQueueEntries(from offsets: IndexSet, to destination: Int) {
        // Capture stable IDs before a just-rendered boundary advances the queue.
        let upcoming = queue.upcoming
        let ids = offsets.compactMap { upcoming.indices.contains($0) ? upcoming[$0].id : nil }
        let target = upcoming.indices.contains(destination) ? upcoming[destination].id : nil
        player?.synchronizeQueueBoundary()
        queue.moveUpcoming(ids, before: target)
        refreshScheduledNext()
    }
    func playQueueEntry(_ id: UUID) {
        if let trackID = queue.jump(to: id), let track = tracks.first(where: { $0.id == trackID }) { select(track) }
    }
    private func preloadNext(on audio: EnginePlayback) {
        guard let entry = queue.nextEntry else { audio.clearNext(); return }
        guard audio.upcomingEntryID != entry.id else { return }
        guard let track = tracks.first(where: { $0.id == entry.trackID }),
              let file = try? AVAudioFile(forReading: track.url, commonFormat: .pcmFormatFloat32, interleaved: false) else { audio.clearNext(); return }
        _ = audio.preload(file, id: entry.id)
    }
    private func refreshScheduledNext() {
        guard let player, isPlaying || preparingPlayback else { return }
        preloadNext(on: player)
        diagnostics.record(.queueEdited)
    }

    func exportAudioDiagnostics() {
        let panel = NSSavePanel()
        panel.title = "Export Audio Diagnostics"
        panel.nameFieldStringValue = "Still-Music-audio-diagnostics.json"
        panel.allowedContentTypes = [.json]
        panel.message = "Contains recent audio events and numeric device/rate information. No song names or file paths. Nothing is uploaded."
        panel.begin { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            do { try self.diagnostics.exportData().write(to: url, options: .atomic) }
            catch { self.message = "Couldn’t export audio diagnostics. \(error.localizedDescription)" }
        }
    }

    func toggleFavorite(_ track: Track) {
        if favoriteIDs.contains(track.id) { favoriteIDs.remove(track.id) } else { favoriteIDs.insert(track.id) }
        save()
    }

    func refreshMetadata(onlyUnindexed: Bool = false) {
        guard !refreshing else { return }
        let candidates = tracks.filter { !onlyUnindexed || $0.metadataVersion != 2 }
        guard !candidates.isEmpty else { return }
        refreshing = true
        Task {
            let updated = await Task.detached(priority: .utility) {
                var results: [String: Track] = [:]
                for track in candidates {
                    if let refreshed = try? await Track.read(track.url) { results[track.id] = refreshed }
                }
                return results
            }.value
            tracks = tracks.map { updated[$0.id] ?? $0 }
            ArtworkStore.shared.clear()
            artworkRevision += 1
            if let current { loadArtwork(current) }
            refreshing = false
            if !onlyUnindexed, updated.count < candidates.count {
                message = "Updated \(updated.count) songs. Some files are unavailable; their saved details were kept."
            }
            updateNowPlaying()
            save()
        }
    }

    override init() {
        if let override = ProcessInfo.processInfo.environment["STILL_LIBRARY_PATH"] {
            storageURL = URL(fileURLWithPath: override)
        } else {
            // Preserve the original storage location across the Still Music rename.
            storageURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Still/library.json")
        }
        diagnostics = AudioDiagnostics(storageURL: storageURL.deletingPathExtension().appendingPathExtension("audio-diagnostics.json"))
        outputRate = OutputSampleRate(diagnostics: diagnostics)
        super.init()
        diagnostics.record(.sessionStarted)
        do { playlists = try PlaylistStorage.load(from: playlistsURL) }
        catch { playlistsReadable = false; message = "Your playlists couldn’t be opened. \(error.localizedDescription)" }
        do {
            let saved = try LibraryStorage.load(from: storageURL)
            tracks = saved.tracks
            sortPreferences = saved.sortPreferences ?? [:]
            favoriteIDs = saved.favoriteIDs ?? []
            theme = saved.theme == "black" ? "black" : "light"
            // Volume is controlled by macOS now. Ignore legacy app-volume values
            // so a removed control cannot silently attenuate playback.
            if let track = tracks.first(where: { $0.id == saved.currentID }) ?? tracks.first {
                select(track, autoplay: false, startAt: saved.currentID == track.id ? saved.position : 0)
            }
        } catch { message = "Your saved library couldn’t be opened. \(error.localizedDescription)" }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        if FileManager.default.fileExists(atPath: foldersURL.path) {
            watchedFolders = (try? WatchedFolders.load(from: foldersURL)) ?? WatchedFolders()
        } else {
            watchedFolders.include(tracks.map(\.url))
            try? watchedFolders.save(to: foldersURL)
        }
        rescanFoldersIfNeeded()
        folderScanTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescanFoldersIfNeeded() }
        }
        folderScanTimer?.tolerance = 15
        deviceMonitor = OutputDeviceMonitor { [weak self] in self?.outputDeviceChanged() }
        configureRemoteCommands()
        refreshMetadata(onlyUnindexed: true)
    }

    func rescanFoldersIfNeeded(force: Bool = false) {
        guard !shuttingDown, !importing, folderScanTask == nil,
              (force || Date().timeIntervalSince(lastFolderScan) >= 300), !watchedFolders.paths.isEmpty else { return }
        scanningFolders = true
        lastFolderScan = Date()
        let urls = watchedFolders.urls
        let excluded = Set(tracks.map(\.id)).union(watchedFolders.ignoredTrackIDs)
        folderScanTask = Task {
            let worker = Task.detached(priority: .utility) { await LibraryImporter.scan(urls, excluding: excluded) }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            defer { folderScanTask = nil; scanningFolders = false }
            guard !Task.isCancelled, !shuttingDown else { return }
            // Recheck at merge time: a manual import/removal can happen during the scan.
            let existing = Set(tracks.map(\.id)).union(watchedFolders.ignoredTrackIDs)
            let additions = result.tracks.filter { !existing.contains($0.id) }
            tracks.append(contentsOf: additions)
            let snapshot = tracks
            let repair = Task.detached(priority: .utility) { LibraryReconciliation.replacements(in: snapshot) }
            let replacements = await withTaskCancellationHandler { await repair.value } onCancel: { repair.cancel() }
            guard !Task.isCancelled, !shuttingDown else { return }
            if !preparingPlayback { reconcileLibraryPaths(replacements, snapshot: snapshot) }
            if currentID == nil, let first = tracks.first { select(first, autoplay: false) }
            save()
        }
    }

    private func reconcileLibraryPaths(_ replacements: [String: String], snapshot: [Track]) {
        // A manual import/removal or metadata refresh may have run during disk checks.
        let checked = Dictionary(snapshot.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let live = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let valid = replacements.filter { old, new in
            live[old] != nil && live[new] != nil && live[old] == checked[old] && live[new] == checked[new]
        }
        guard !valid.isEmpty else { return }
        let backup = storageURL.deletingPathExtension().appendingPathExtension("before-path-repair.json")
        do {
            if !FileManager.default.fileExists(atPath: backup.path) {
                try LibraryStorage.save(LibrarySnapshot(tracks: tracks, currentID: currentID, position: position,
                    volume: 1, favoriteIDs: favoriteIDs, theme: theme, sortPreferences: sortPreferences), to: backup)
            }
        } catch { message = "Couldn’t back up the library before repairing moved songs."; return }
        var updatedPlaylists = playlists
        for index in updatedPlaylists.indices { updatedPlaylists[index].reconcilePaths(valid) }
        do { try commitPlaylists(updatedPlaylists) }
        catch { message = "Couldn’t update playlists for moved songs. \(error.localizedDescription)"; return }
        favoriteIDs = Set(favoriteIDs.map { valid[$0] ?? $0 })
        queue.reconcilePaths(valid)
        if let id = currentID, let replacement = valid[id] { currentID = replacement }
        tracks.removeAll { valid[$0.id] != nil }
        // The currently open audio file can continue playing; no graph restart.
        refreshScheduledNext()
    }

    func chooseFiles() {
        guard !choosingFiles, !importing else { return }
        choosingFiles = true
        let panel = NSOpenPanel()
        panel.title = "Add music"
        panel.message = "Choose audio files or a folder. Your files stay where they are."
        panel.prompt = "Add music"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .folder]
        panel.begin { [weak self] response in
            Task { @MainActor in
                self?.choosingFiles = false
                if response == .OK { self?.add(panel.urls) }
            }
        }
    }

    func add(_ urls: [URL]) {
        guard !importing, !urls.isEmpty else { return }
        watchedFolders.include(urls)
        try? watchedFolders.save(to: foldersURL)
        importing = true
        message = nil
        let existing = Set(tracks.map(\.id))
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                await LibraryImporter.scan(urls, excluding: existing)
            }.value
            guard !shuttingDown else { importing = false; return }
            let currentIDs = Set(tracks.map(\.id))
            tracks.append(contentsOf: result.tracks.filter { !currentIDs.contains($0.id) })
            watchedFolders.ignoredTrackIDs.subtract(result.tracks.map(\.id))
            try? watchedFolders.save(to: foldersURL)
            importing = false
            if currentID == nil, let first = tracks.first { select(first, autoplay: false) }
            if !result.failed.isEmpty {
                let names = result.failed.prefix(3).joined(separator: ", ")
                message = "Couldn’t read \(names)\(result.failed.count > 3 ? " and \(result.failed.count - 3) more" : ""). Use FLAC, MP3, AAC, ALAC, WAV, or AIFF files."
            } else if result.tracks.isEmpty {
                message = "No new music found. These files may already be in your library."
            }
            save()
        }
    }

    func select(_ track: Track, autoplay: Bool = true, startAt: Double = 0) {
        if queue.current?.trackID != track.id { queue.reset(tracks.map(\.id), startingAt: track.id) }
        loadLyrics(track)
        stopRendering()
        currentID = track.id
        position = min(max(0, startAt), track.duration)
        artwork = nil
        artworkTask?.cancel()
        loadArtwork(track)
        preparingPlayback = autoplay
        enqueueAudioOperation { [weak self] in
            guard let self else { return }
            if autoplay { await self.startPlayback(track, at: startAt) }
            else { await self.restoreOutputRate() }
        }
        updateNowPlaying()
        save()
    }

    private func startPlayback(_ track: Track, at seconds: Double, matchRate: Bool = true) async {
        preparingPlayback = true
        do {
            // Decode to float at the source rate, not the device rate.
            let file = try AVAudioFile(forReading: track.url, commonFormat: .pcmFormatFloat32, interleaved: false)
            let sourceRate = file.processingFormat.sampleRate
            if !matchOutputRate { await restoreOutputRate() }
            guard !Task.isCancelled else { return }
            // Rendering is stopped and faded to silence before any device write.
            // Failure leaves us using the device's current format without user-facing noise.
            // Recover at the current hardware rate after a mid-song configuration
            // change. Reasserting our rate here can fight another client/device
            // change and provoke another reset. New tracks/routes still match.
            _ = try? await outputRate.match(source: sourceRate, enabled: matchOutputRate && matchRate)
            guard !Task.isCancelled, currentID == track.id else { return }
            let audio = try EnginePlayback(file: file)
            audio.volume = 1
            audio.onNeedsNext = { [weak self, weak audio] in
                guard let self, let audio, self.player === audio else { return }
                self.preloadNext(on: audio)
            }
            audio.onAdvance = { [weak self, weak audio] entryID in
                guard let self, let audio, self.player === audio, self.queue.nextEntry?.id == entryID,
                      let id = self.queue.advance(), let track = self.tracks.first(where: { $0.id == id }) else { return }
                self.diagnostics.record(.gaplessAdvance)
                self.currentID = track.id
                self.position = audio.currentTime
                self.artwork = nil
                self.loadArtwork(track)
                self.loadLyrics(track)
                self.updateNowPlaying()
                self.save()
            }
            audio.onCompletion = { [weak self, weak audio] in
                guard let self, let audio, self.player === audio else { return }
                self.isPlaying = false
                if self.hasNext { self.next() }
                else {
                    self.stopRendering()
                    self.position = audio.duration
                    self.enqueueAudioOperation { [weak self] in await self?.restoreOutputRate() }
                    self.updateNowPlaying()
                    self.save()
                }
            }
            audio.onConfigurationChange = { [weak self, weak audio] in
                guard let self, let audio, self.player === audio, self.isPlaying || self.preparingPlayback else { return }
                self.outputDeviceChanged(matchRate: false)
            }
            player = audio
            let start = seconds >= audio.duration - 0.05 ? 0 : seconds
            try await audio.playWithFade(from: max(0, start))
            guard !Task.isCancelled, player === audio else { return }
            position = start
            isPlaying = true
            preparingPlayback = false
            diagnostics.record(.engineStarted, sourceRate: sourceRate, outputRate: audio.outputRate)
        } catch is CancellationError {
            // A newer operation decides whether to restore; do not bounce the rate between tracks.
            stopRendering()
            await drainPlayers()
        } catch {
            diagnostics.record(.playbackFailed, status: AudioDiagnostics.statusCode(error))
            stopRendering()
            await drainPlayers()
            await restoreOutputRate()
        }
        updateNowPlaying()
        save()
    }

    func togglePlayback() {
        if isPlaying || preparingPlayback { pause(); return }
        if let track = current ?? tracks.first { select(track, startAt: position) }
    }

    var canWriteEmbeddedLyrics: Bool {
        current.map { EmbeddedLyricsWriter.supports($0.url) } ?? false
    }

    func uploadLyrics() {
        guard let track = current, !uploadingLyrics, !savingLyrics else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose lyrics for \(track.title)"
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        uploadingLyrics = true
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else { self.uploadingLyrics = false; return }
            let root = self.importedLyricsRoot
            Task { @MainActor in
                defer { self.uploadingLyrics = false }
                do {
                    try await Task.detached(priority: .utility) {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        try ImportedLyrics.save(from: url, for: track.url, root: root)
                    }.value
                    if self.currentID == track.id { self.loadLyrics(track) }
                } catch {
                    self.message = "Couldn’t import lyrics. Choose a nonempty .lrc or .txt file under 8 MB. \(error.localizedDescription)"
                }
            }
        }
    }

    func deleteLyrics() {
        guard let track = current, canWriteEmbeddedLyrics, !lyrics.isEmpty,
              !savingLyrics, !uploadingLyrics, !savingCover, !loadingLyrics else { return }
        let alert = NSAlert()
        alert.messageText = "Delete lyrics?"
        alert.informativeText = "Remove embedded lyrics from \(track.url.lastPathComponent) and clear this song’s lyrics in Still Music? This cannot be undone. Separate .lrc and .txt files will remain on disk and may still show lyrics in other players. To remove only your unsaved changes, use Discard changes instead."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard currentID == track.id, !savingLyrics, !uploadingLyrics, !savingCover else { return }
        editEmbeddedLyrics(nil, track: track)
    }

    func writeLyricsToFile() {
        guard let track = current, canWriteEmbeddedLyrics, !lyrics.isEmpty,
              !savingLyrics, !uploadingLyrics, !savingCover, !loadingLyrics else { return }
        let snapshot = lyrics
        let alert = NSAlert()
        alert.messageText = "Write lyrics to file?"
        alert.informativeText = "Replace all embedded lyrics in \(track.url.lastPathComponent) with the lyrics currently displayed? Existing embedded lyrics will be overwritten. Audio and other song tags are preserved."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Write lyrics")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard currentID == track.id, !savingLyrics, !uploadingLyrics, !savingCover else { return }
        editEmbeddedLyrics(snapshot, track: track)
    }

    private func editEmbeddedLyrics(_ replacement: Lyrics?, track: Track) {
        lyricsTask?.cancel()
        savedLyricsNoticeTask?.cancel()
        savedLyricsTrackID = nil
        loadingLyrics = false
        savingLyrics = true
        let root = importedLyricsRoot
        Task { [self] in
            defer { savingLyrics = false }
            do {
                try await Task.detached(priority: .utility) {
                    try EmbeddedLyricsWriter.write(replacement, to: track.url)
                }.value
                do {
                    try ImportedLyrics.setMode(replacement == nil ? .deleted : .written, for: track.url, root: root)
                } catch {
                    message = "The audio file was updated, but Still couldn’t update its lyrics preference. \(error.localizedDescription)"
                }
                if currentID == track.id {
                    lyrics = replacement ?? Lyrics()
                    hasUnsavedLyrics = false
                    canDeleteLyrics = replacement != nil
                    if replacement != nil {
                        savedLyricsTrackID = track.id
                        savedLyricsNoticeTask = Task { [weak self] in
                            do { try await Task.sleep(for: .seconds(3)) }
                            catch { return }
                            self?.savedLyricsTrackID = nil
                        }
                    }
                }
            } catch {
                message = "Couldn’t \(replacement == nil ? "delete" : "write") embedded lyrics. \(error.localizedDescription)"
            }
        }
    }

    func discardLyricsChanges() {
        guard let track = current, hasUnsavedLyrics, !loadingLyrics,
              !savingLyrics, !uploadingLyrics else { return }
        lyricsTask?.cancel()
        do {
            try ImportedLyrics.discard(for: track.url, root: importedLyricsRoot)
            loadLyrics(track)
        } catch {
            message = "Couldn’t discard the lyrics draft. \(error.localizedDescription)"
        }
    }

    func findCurrentLyricsOnline() {
        guard let track = current, !loadingLyrics, !savingLyrics, !uploadingLyrics else { return }
        loadLyrics(track, requestedOnline: true)
    }

    private func loadLyrics(_ track: Track, requestedOnline: Bool = false) {
        savedLyricsNoticeTask?.cancel()
        savedLyricsTrackID = nil
        lyricsTask?.cancel()
        lyrics = Lyrics()
        canDeleteLyrics = false
        hasUnsavedLyrics = false
        loadingLyrics = true
        let root = importedLyricsRoot
        let importedURL = ImportedLyrics.file(for: track.url, root: root)
        lyricsTask = Task {
            let worker = Task.detached(priority: .utility) {
                let mode = try? ImportedLyrics.mode(for: track.url, root: root)
                if mode == .deleted { return (Lyrics(), true, false) }
                if mode == .written { return (await LyricsLoader.embedded(track.url) ?? Lyrics(), true, false) }
                if mode == .local { return (await LyricsLoader.load(track.url), true, false) }
                if let imported = try? ImportedLyrics.read(importedURL) { return (imported, true, true) }
                return (await LyricsLoader.load(track.url), false, false)
            }
            let (loaded, skipAutomaticLookup, loadedDraft) = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            var result = loaded
            var isDraft = loadedDraft
            guard !Task.isCancelled, currentID == track.id else { return }
            if requestedOnline || (!skipAutomaticLookup && result.lines.isEmpty && findLyricsOnline) {
                let online = (try? await onlineMetadata.lyrics(for: track)) ?? Lyrics()
                guard !Task.isCancelled, currentID == track.id else { return }
                if findLyricsOnline || requestedOnline {
                    let replacement = requestedOnline && !online.isEmpty ? online : result.preferringSynced(online)
                    if replacement != result {
                        do {
                            try ImportedLyrics.save(replacement, for: track.url, root: root)
                            result = replacement
                            isDraft = true
                        } catch {
                            message = "Couldn’t save these lyrics in Still Music. \(error.localizedDescription)"
                        }
                    }
                }
            }
            guard !Task.isCancelled, currentID == track.id else { return }
            lyrics = result
            hasUnsavedLyrics = isDraft
            canDeleteLyrics = !result.isEmpty
            loadingLyrics = false
        }
    }

    private func loadArtwork(_ track: Track) {
        artworkTask?.cancel()
        artworkTask = Task {
            let image = await ArtworkStore.shared.image(for: track.url)
            guard !Task.isCancelled, currentID == track.id else { return }
            guard !Task.isCancelled, currentID == track.id else { return }
            artwork = image
            updateNowPlaying()
        }
    }

    private func albumTracks(_ track: Track) -> [Track] {
        guard !track.album.isEmpty else { return [track] }
        return tracks.filter { $0.album == track.album && $0.displayAlbumArtist == track.displayAlbumArtist }
    }

    func chooseAlbumCover(_ track: Track) {
        guard !savingCover, !choosingCover else { return }
        choosingCover = true
        let panel = NSOpenPanel()
        panel.title = "Choose Album Cover"
        panel.allowedContentTypes = [.jpeg, .png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard let self else { return }
            self.choosingCover = false
            guard response == .OK, let url = panel.url else { return }
            Task {
                do {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size < 16 * 1024 * 1024 else { throw FLACArtworkWriter.WriteError.invalidImage }
                    let data = try Data(contentsOf: url)
                    await self.applySelectedCover(data, for: track)
                } catch { self.message = error.localizedDescription }
            }
        }
    }
    private func applySelectedCover(_ data: Data, for track: Track) async {
        guard !savingCover else { return }
        savingCover = true
        defer { savingCover = false }
        let album = albumTracks(track)
        do { try ArtworkStore.shared.setCover(data, tracks: album) }
        catch { message = "Couldn’t save the selected cover. \(error.localizedDescription)"; return }
        if writeCoversIntoFiles {
            var failures = 0
            for song in album where song.url.pathExtension.lowercased() == "flac" {
                guard writeCoversIntoFiles, !shuttingDown else { break }
                let succeeded = await Task.detached(priority: .utility) {
                    do { try FLACArtworkWriter.write(data, to: song.url); return true } catch { return false }
                }.value
                if !succeeded { failures += 1 }
            }
            if failures > 0 { message = "The cover is saved in Still Music, but couldn’t be written to \(failures) FLAC file(s). Check file permissions and available disk space." }
        }
        ArtworkStore.shared.clear()
        artworkRevision += 1
        if let current { loadArtwork(current) }
    }

    func pause() {
        diagnostics.record(.playbackPaused)
        stopRendering()
        // A temporary pause retains the matched rate; terminal stop restores it.
        enqueueAudioOperation { }
        updateNowPlaying()
        save()
    }

    func stop() {
        diagnostics.record(.playbackStopped)
        stopRendering()
        enqueueAudioOperation { [weak self] in await self?.restoreOutputRate() }
        updateNowPlaying()
        save()
    }

    func next() {
        if let id = queue.advance(), let track = tracks.first(where: { $0.id == id }) { select(track) }
    }

    func previous() {
        if position > 3 { seek(to: 0); return }
        if let id = queue.previous(), let track = tracks.first(where: { $0.id == id }) { select(track) }
        else { seek(to: 0) }
    }

    var hasNext: Bool { queue.hasNext }

    func seek(to seconds: Double) {
        guard let track = current else { return }
        position = min(max(0, seconds), track.duration)
        if preparingPlayback { select(track, startAt: position); return }
        if isPlaying, let player {
            do { try player.play(from: position) }
            catch { pause(); message = "Couldn’t seek. \(error.localizedDescription)" }
        }
        updateNowPlaying()
    }

    func remove(_ track: Track) {
        var updatedPlaylists = playlists
        for index in updatedPlaylists.indices { updatedPlaylists[index].remove(track.id) }
        if updatedPlaylists != playlists {
            do { try commitPlaylists(updatedPlaylists) }
            catch { message = "Couldn’t update playlists. \(error.localizedDescription)"; return }
        }
        player?.synchronizeQueueBoundary()
        watchedFolders.ignoredTrackIDs.insert(track.id)
        try? watchedFolders.save(to: foldersURL)
        if track.id == currentID {
            stopRendering()
            enqueueAudioOperation { [weak self] in await self?.restoreOutputRate() }
            currentID = nil
            lyricsTask?.cancel()
            lyrics = Lyrics()
            loadingLyrics = false
            position = 0
            artwork = nil
            artworkTask?.cancel()
        }
        tracks.removeAll { $0.id == track.id }
        favoriteIDs.remove(track.id)
        queue.remove(track.id)
        refreshScheduledNext()
        if currentID == nil, let first = tracks.first { select(first, autoplay: false) }
        updateNowPlaying()
        save()
    }

    func save() {
        do {
            try LibraryStorage.save(LibrarySnapshot(tracks: tracks, currentID: currentID, position: position, volume: 1, favoriteIDs: favoriteIDs, theme: theme, sortPreferences: sortPreferences), to: storageURL)
        } catch { message = "Your library couldn’t be saved. \(error.localizedDescription)" }
    }

    private func tick() {
        if isPlaying { position = player?.currentTime ?? 0 }
        ticks += 1
        if ticks >= 40 { ticks = 0; if isPlaying { save() } }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false { self?.togglePlayback() } }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }; return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }; return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }; return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }; return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }; return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }; return .success
        }
    }

    private func updateNowPlaying() {
        let info = MPNowPlayingInfoCenter.default()
        guard let track = current else { info.nowPlayingInfo = nil; info.playbackState = .stopped; return }
        var values: [String: Any] = [MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album, MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0]
        if let artwork { values[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork } }
        info.nowPlayingInfo = values
        info.playbackState = isPlaying ? .playing : .paused
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = hasNext
    }
}
