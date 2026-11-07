import AppKit
import AVFoundation
import MediaPlayer
import StillCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PlaybackClock: ObservableObject { @Published var position: Double = 0 }

@MainActor
final class MetadataProgress: ObservableObject {
    @Published var completed = 0
    @Published var total = 0
    @Published var failureCount = 0
    @Published var cancellationRequested = false
}

@MainActor
final class PlayerModel: NSObject, ObservableObject {
    @Published private(set) var tracks: [Track] = [] {
        didSet {
            libraryDirty = true
            trackIndex = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            invalidateLibraryViews()
            ArtworkStore.shared.configure(
                tracks: tracks, root: storageURL.deletingPathExtension().appendingPathExtension("covers"))
        }
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
    @Published private(set) var equalizer: EqualizerSettings = {
        guard let data = UserDefaults.standard.data(forKey: "StillEqualizer"),
              let settings = try? JSONDecoder().decode(EqualizerSettings.self, from: data) else { return .init() }
        return settings.normalized
    }()

    func applyEqualizer(_ settings: EqualizerSettings) {
        let value = settings.normalized
        guard value != equalizer else { return }
        let wasEnabled = equalizer.enabled
        equalizer = value
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "StillEqualizer") }
        if !wasEnabled && !value.enabled { return }
        if player?.updateEqualizer(value) == true { return }
        guard let track = current else { return }
        let resume = isPlaying || preparingPlayback
        let position = player?.currentTime ?? self.position
        select(track, autoplay: resume, startAt: position, continuingListen: true)
    }

    func browseCurrent(_ destination: LibrarySection) {
        guard let track = current, destination == .albums || destination == .artists else { return }
        let group = LibraryGrouping.groups(tracks, by: destination).first { $0.tracks.contains { $0.id == track.id } }
        search = ""
        section = destination
        selectedGroupID = group?.id
    }

    @Published private(set) var savingCover = false
    private var choosingCover = false
    private let onlineMetadata = OnlineMetadata()

    @Published private(set) var currentID: String? { didSet { libraryDirty = true } }
    @Published private(set) var isPlaying = false
    let clock = PlaybackClock()
    var position: Double {
        get { clock.position }
        set { clock.position = newValue }
    }
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
    @Published var selectedSongIDs: Set<String> = []
    var selectedSongs: [Track] { visibleTracks.filter { selectedSongIDs.contains($0.id) } }
    @Published var search = "" {
        didSet {
            cachedVisibleGroups = nil
            cachedVisibleTracks = nil
        }
    }
    @Published var section: LibrarySection = .songs {
        didSet {
            selectedSongIDs.removeAll()
            selectedGroupID = nil
            selectedPlaylistID = nil
            search = ""
            invalidateLibraryViews()
        }
    }
    @Published var selectedGroupID: String? {
        didSet {
            selectedSongIDs.removeAll()
            cachedVisibleTracks = nil
        }
    }
    @Published private(set) var playlists: [MusicPlaylist] = [] { didSet { cachedVisibleTracks = nil } }
    @Published private(set) var selectedPlaylistID: UUID? {
        didSet {
            selectedSongIDs.removeAll()
            cachedVisibleTracks = nil
        }
    }
    private var playlistsReadable = true
    private var playlistsURL: URL { storageURL.deletingPathExtension().appendingPathExtension("playlists.json") }
    var selectedPlaylist: MusicPlaylist? { playlists.first { $0.id == selectedPlaylistID } }
    // MARK: - Playlists

    func openPlaylist(_ id: UUID) {
        section = .playlist
        selectedPlaylistID = id
    }
    private func commitPlaylists(_ updated: [MusicPlaylist]) throws {
        guard playlistsReadable else {
            throw NSError(
                domain: "StillPlaylists", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "The saved playlists could not be read. Restore the playlist file before editing it."
                ])
        }
        try PlaylistStorage.save(updated, to: playlistsURL)
        playlists = updated
    }
    func editPlaylistName(_ name: String, id: UUID? = nil, adding songs: [Track] = []) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            throw NSError(
                domain: "StillPlaylists", code: 2, userInfo: [NSLocalizedDescriptionKey: "Enter a playlist name."])
        }
        guard !playlists.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(clean) == .orderedSame })
        else {
            throw NSError(
                domain: "StillPlaylists", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "A playlist with that name already exists."])
        }
        var updated = playlists
        if let id {
            guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
            updated[index].name = clean
            try commitPlaylists(updated)
        } else {
            let playlist = MusicPlaylist(name: clean, trackIDs: songs.map(\.id))
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
    func addToPlaylist(_ track: Track, id: UUID) { addToPlaylist([track], id: id) }
    func addToPlaylist(_ songs: [Track], id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        var updated = playlists
        for song in songs { updated[index].add(song.id) }
        do { try commitPlaylists(updated) } catch {
            message = "Couldn’t add song to playlist. \(error.localizedDescription)"
        }
    }
    func removeFromPlaylist(_ songs: [Track], id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        var updated = playlists
        for song in songs { updated[index].remove(song.id) }
        do { try commitPlaylists(updated) } catch {
            message = "Couldn’t update playlist. \(error.localizedDescription)"
        }
    }
    func movePlaylistSong(_ track: Track, by offset: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == selectedPlaylistID }) else { return }
        var updated = playlists
        updated[index].move(track.id, by: offset)
        do { try commitPlaylists(updated) } catch {
            message = "Couldn’t reorder playlist. \(error.localizedDescription)"
        }
    }
    @Published private var sortPreferences: [String: LibrarySort] = [:] {
        didSet {
            libraryDirty = true
            invalidateLibraryViews()
        }
    }
    @Published private(set) var favoriteIDs: Set<String> = [] {
        didSet {
            libraryDirty = true
            cachedVisibleTracks = nil
        }
    }
    @Published private(set) var refreshing = false
    @Published private(set) var artworkRevision = 0
    @Published var theme = "light" {
        didSet {
            libraryDirty = true
            save()
        }
    }

    @Published private(set) var preparingPlayback = false
    // Hidden debugging override; existing UI preferences no longer disable matching.
    private var matchOutputRate: Bool {
        UserDefaults.standard.object(forKey: "StillDebugMatchOutputSampleRate") as? Bool ?? true
    }
    private var retiringPlayers: [any AudioPlayback] = []
    private var deviceMonitor: OutputDeviceMonitor?
    private var shuttingDown = false
    private var player: (any AudioPlayback)?
    private let diagnostics: AudioDiagnostics
    private let outputRate: OutputSampleRate
    private var audioOperation: Task<Void, Never>?

    // MARK: - Audio lifecycle

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
        listenSession.interrupt()
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
        cancelPrefetch()
        save()
        await persistence.flush()
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
    private let persistence: LibraryPersistence
    private var listeningHistory = ListeningHistory()
    private var listenSession = ListenSession()
    private var historyRefreshTicks = 0
    private var libraryDirty = true
    private var loadingLibrary = true
    private var libraryReadable = true
    private var ticks = 0
    @Published private(set) var queue = PlaybackQueue() { didSet { libraryDirty = true } }
    private var choosingFiles = false
    private var trackIndex: [String: Track] = [:]
    private var cachedGroups: [LibraryGroup]?
    private var cachedVisibleGroups: [LibraryGroup]?
    private var cachedVisibleTracks: [Track]?
    // MARK: - Library browsing and sorting

    private func invalidateLibraryViews() {
        cachedGroups = nil
        cachedVisibleGroups = nil
        cachedVisibleTracks = nil
    }
    var current: Track? { currentID.flatMap { trackIndex[$0] } }
    var groups: [LibraryGroup] {
        if let cachedGroups { return cachedGroups }
        let result = LibraryGrouping.groups(tracks, by: section)
        cachedGroups = result
        return result
    }
    var selectedGroup: LibraryGroup? { groups.first { $0.id == selectedGroupID } }
    private var sortKey: String { section.rawValue + (selectedGroupID == nil ? "" : ".tracks") }
    var sortOptions: [LibrarySortField] { LibrarySortField.options(for: section, inGroup: selectedGroupID != nil) }
    var librarySort: LibrarySort {
        sortPreferences[sortKey]
            ?? LibrarySort(
                field: selectedGroupID != nil && section == .albums
                    ? .trackNumber
                    : (section.isGrouped && selectedGroupID == nil ? (section == .albums ? .title : .name) : .dateAdded)
            )
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
        if let cachedVisibleGroups { return cachedVisibleGroups }
        let result = librarySort.groups(
            groups.filter {
                search.isEmpty || "\($0.title) \($0.subtitle)".localizedCaseInsensitiveContains(search)
                    || $0.tracks.contains(where: matchesSearch)
            })
        cachedVisibleGroups = result
        return result
    }
    private func matchesSearch(_ track: Track) -> Bool {
        search.isEmpty
            || "\(track.title) \(track.artist) \(track.album) \(track.albumArtist ?? "") \(track.genre ?? "") \(track.composer ?? "")"
                .localizedCaseInsensitiveContains(search)
    }
    var visibleTracks: [Track] {
        if let cachedVisibleTracks { return cachedVisibleTracks }
        if section == .onRepeat {
            let result = listeningHistory.rankedIDs(available: Set(trackIndex.keys)).compactMap { trackIndex[$0] }
                .filter(matchesSearch)
            cachedVisibleTracks = result
            return result
        }
        if section == .playlist {
            let result = (selectedPlaylist?.trackIDs ?? []).compactMap { trackIndex[$0] }.filter(matchesSearch)
            cachedVisibleTracks = result
            return result
        }
        let base =
            selectedGroup?.tracks ?? (section == .favorites ? tracks.filter { favoriteIDs.contains($0.id) } : tracks)
        let result = librarySort.tracks(base.filter(matchesSearch), library: tracks)
        cachedVisibleTracks = result
        return result
    }
    // MARK: - Queue and playback commands

    func play(_ track: Track) {
        queue.reset(visibleTracks.map(\.id), startingAt: track.id)
        select(track)
    }
    func enqueue(_ track: Track, next: Bool) { enqueue([track], next: next) }
    func enqueue(_ songs: [Track], next: Bool) {
        guard !songs.isEmpty else { return }
        player?.synchronizeQueueBoundary()
        if let current, queue.current?.trackID != current.id { queue.reset(tracks.map(\.id), startingAt: current.id) }
        // Inserting next repeatedly reverses order, so visit the selection backwards.
        for song in next ? Array(songs.reversed()) : songs { queue.enqueue(song.id, next: next) }
        refreshScheduledNext()
    }
    func toggleShuffle() {
        player?.synchronizeQueueBoundary()
        queue.toggleShuffle()
        refreshScheduledNext()
    }
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
    private var prefetch: (url: URL, task: Task<(StreamingAudio, AVAudioPCMBuffer?), Error>)?
    private func cancelPrefetch() {
        prefetch?.task.cancel()
        prefetch = nil
    }
    private func preloadNext(on audio: any AudioPlayback) {
        guard let entry = queue.nextEntry, let track = trackIndex[entry.trackID] else {
            audio.clearNext()
            cancelPrefetch()
            return
        }
        if ExtendedAudio.extensions.contains(track.url.pathExtension.lowercased()) {
            audio.clearNext()
            guard prefetch?.url != track.url else { return }
            cancelPrefetch()
            prefetch = (
                track.url,
                Task {
                    let decoder = try StreamingAudio(source: track.url)
                    do {
                        let first = try await decoder.read()
                        try Task.checkCancellation()
                        return (decoder, first)
                    } catch {
                        decoder.cancel()
                        throw error
                    }
                }
            )
            return
        }
        cancelPrefetch()
        guard audio.upcomingEntryID != entry.id else { return }
        guard let file = try? ExtendedAudio.readyFile(track.url) else {
            audio.clearNext()
            return
        }
        _ = audio.preload(file, id: entry.id)
    }
    private func refreshScheduledNext() {
        save()
        guard let player, isPlaying || preparingPlayback else { return }
        preloadNext(on: player)
        diagnostics.record(.queueEdited)
    }

    func exportAudioDiagnostics() {
        let panel = NSSavePanel()
        panel.title = "Export Audio Diagnostics"
        panel.nameFieldStringValue = "Still-Music-audio-diagnostics.json"
        panel.allowedContentTypes = [.json]
        panel.message =
            "Contains recent audio events and numeric device/rate information. No song names or file paths. Nothing is uploaded."
        panel.begin { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            do { try self.diagnostics.exportData().write(to: url, options: .atomic) } catch {
                self.message = "Couldn’t export audio diagnostics. \(error.localizedDescription)"
            }
        }
    }

    func toggleFavorite(_ track: Track) {
        if favoriteIDs.contains(track.id) { favoriteIDs.remove(track.id) } else { favoriteIDs.insert(track.id) }
        save()
    }

    // MARK: - Metadata refresh

    func refreshMetadata(onlyUnindexed: Bool = false) {
        guard !refreshing, !editingMetadata else { return }
        let candidates = tracks.filter { !onlyUnindexed || $0.metadataVersion != 3 }
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
        persistence = LibraryPersistence(url: storageURL)
        diagnostics = AudioDiagnostics(
            storageURL: storageURL.deletingPathExtension().appendingPathExtension("audio-diagnostics.json"))
        outputRate = OutputSampleRate(diagnostics: diagnostics)
        super.init()
        diagnostics.record(.sessionStarted)
        do { playlists = try PlaylistStorage.load(from: playlistsURL) } catch {
            playlistsReadable = false
            message = "Your playlists couldn’t be opened. \(error.localizedDescription)"
        }
        do {
            var saved = try LibraryStorage.load(from: storageURL)
            if let resume = try? PlaybackPosition.load(beside: storageURL), resume.currentID == saved.currentID {
                saved.position = resume.position
            }
            listeningHistory = saved.listeningHistory ?? ListeningHistory()
            listeningHistory.prune()
            tracks = saved.tracks
            queue = saved.queue ?? PlaybackQueue()
            sortPreferences = saved.sortPreferences ?? [:]
            favoriteIDs = saved.favoriteIDs ?? []
            theme = saved.theme == "black" ? "black" : "light"
            // Volume is controlled by macOS now. Ignore legacy app-volume values
            // so a removed control cannot silently attenuate playback.
            if let track = tracks.first(where: { $0.id == saved.currentID }) ?? tracks.first {
                select(track, autoplay: false, startAt: saved.currentID == track.id ? saved.position : 0)
            }
        } catch {
            libraryReadable = false
            message = "Your saved library couldn’t be opened. \(error.localizedDescription)"
        }
        loadingLibrary = false
        save()
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

    // MARK: - Folder scanning and import

    func rescanFoldersIfNeeded(force: Bool = false) {
        guard !shuttingDown, !importing, folderScanTask == nil,
            (force || Date().timeIntervalSince(lastFolderScan) >= 300), !watchedFolders.paths.isEmpty
        else { return }
        scanningFolders = true
        lastFolderScan = Date()
        let urls = watchedFolders.urls
        let excluded = Set(tracks.map(\.id))
        folderScanTask = Task {
            let worker = Task.detached(priority: .utility) { await LibraryImporter.scan(urls, excluding: excluded) }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            defer {
                folderScanTask = nil
                scanningFolders = false
            }
            guard !Task.isCancelled, !shuttingDown else { return }
            // Recheck at merge time: a manual import/removal can happen during the scan.
            let existing = Set(tracks.map(\.id))
            let additions = result.tracks.filter { !existing.contains($0.id) }
            tracks.append(contentsOf: additions)
            let snapshot = tracks
            let repair = Task.detached(priority: .utility) { LibraryReconciliation.replacements(in: snapshot) }
            let replacements = await withTaskCancellationHandler {
                await repair.value
            } onCancel: {
                repair.cancel()
            }
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
                try LibraryStorage.save(
                    LibrarySnapshot(
                        tracks: tracks, currentID: currentID, position: position,
                        volume: 1, favoriteIDs: favoriteIDs, theme: theme, sortPreferences: sortPreferences,
                        queue: queue, listeningHistory: listeningHistory), to: backup)
            }
        } catch {
            message = "Couldn’t back up the library before repairing moved songs."
            return
        }
        var updatedPlaylists = playlists
        for index in updatedPlaylists.indices { updatedPlaylists[index].reconcilePaths(valid) }
        do { try commitPlaylists(updatedPlaylists) } catch {
            message = "Couldn’t update playlists for moved songs. \(error.localizedDescription)"
            return
        }
        favoriteIDs = Set(favoriteIDs.map { valid[$0] ?? $0 })
        queue.reconcilePaths(valid)
        listeningHistory.reconcilePaths(valid)
        libraryDirty = true
        if let id = currentID, let replacement = valid[id] { currentID = replacement }
        tracks.removeAll { valid[$0.id] != nil }
        // The currently open audio file can continue playing; no graph restart.
        refreshScheduledNext()
    }

    var canDeleteSong: Bool {
        libraryReadable && playlistsReadable && !loadingLibrary && !importing && !scanningFolders
            && !refreshing && !editingMetadata && !savingCover && !savingLyrics && !shuttingDown
    }

    func deleteSongFile(_ song: Track) {
        guard canDeleteSong, trackIndex[song.id] != nil else {
            message = "Wait for the current library operation to finish before deleting a song."
            return
        }
        // Synchronize a gapless transition before deciding whether this is the current song.
        player?.synchronizeQueueBoundary()
        let deletingCurrent = currentID == song.id
        if deletingCurrent { stop() }
        do {
            try SongFileDeletion.delete(song.url)
        } catch {
            message = "Couldn’t delete “\(song.title)”. Its library entry was kept. \(error.localizedDescription)"
            return
        }

        var updated = playlists
        for index in updated.indices { updated[index].remove(song.id) }
        var persistenceWarning: String?
        do { try commitPlaylists(updated) } catch {
            playlists = updated
            persistenceWarning = "The file was deleted, but playlist changes couldn’t be saved. \(error.localizedDescription)"
        }
        queue.remove(song.id)
        favoriteIDs.remove(song.id)
        selectedSongIDs.remove(song.id)
        if deletingCurrent {
            currentID = nil
            position = 0
            artworkTask?.cancel()
            lyricsTask?.cancel()
            artwork = nil
            lyrics = Lyrics()
            loadingLyrics = false
            canDeleteLyrics = false
            hasUnsavedLyrics = false
            savedLyricsTrackID = nil
        }
        tracks.removeAll { $0.id == song.id }
        cancelPrefetch()
        refreshScheduledNext()
        updateNowPlaying()
        save()
        message = persistenceWarning ?? "Deleted “\(song.title)” and its audio file."
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
        panel.allowedContentTypes =
            [.audio, .folder] + ["opus", "ogg", "oga", "ape", "wv"].compactMap { UTType(filenameExtension: $0) }
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
            guard !shuttingDown else {
                importing = false
                return
            }
            let currentIDs = Set(tracks.map(\.id))
            tracks.append(contentsOf: result.tracks.filter { !currentIDs.contains($0.id) })
            try? watchedFolders.save(to: foldersURL)
            importing = false
            if currentID == nil, let first = tracks.first { select(first, autoplay: false) }
            if !result.failed.isEmpty {
                let names = result.failed.prefix(3).joined(separator: ", ")
                message =
                    "Couldn’t read \(names)\(result.failed.count > 3 ? " and \(result.failed.count - 3) more" : ""). Check that the files are readable and use a supported audio format."
            } else if result.tracks.isEmpty {
                message = "No new music found. These files may already be in your library."
            }
            save()
        }
    }

    // MARK: - Track selection and playback preparation

    func select(_ track: Track, autoplay: Bool = true, startAt: Double = 0, continuingListen: Bool = false) {
        if !continuingListen { listenSession.reset() } else { listenSession.interrupt() }
        if queue.current?.trackID != track.id { queue.reset(tracks.map(\.id), startingAt: track.id) }
        let changingTrack = currentID != track.id
        stopRendering()
        currentID = track.id
        position = min(max(0, startAt), track.duration)
        // Resume/reseek the audio without replacing visible artwork or lyrics.
        // In-flight metadata loads can also finish normally for this same song.
        if changingTrack {
            loadLyrics(track)
            artwork = nil
            artworkTask?.cancel()
            loadArtwork(track)
        }
        preparingPlayback = autoplay
        enqueueAudioOperation { [weak self] in
            guard let self else { return }
            if autoplay { await self.startPlayback(track, at: startAt) } else { await self.restoreOutputRate() }
        }
        updateNowPlaying()
        save()
    }

    private func startPlayback(_ track: Track, at seconds: Double, matchRate: Bool = true) async {
        preparingPlayback = true
        do {
            let extended = ExtendedAudio.extensions.contains(track.url.pathExtension.lowercased())
            let startSeconds = seconds >= track.duration - 0.05 ? 0 : max(0, seconds)
            var stream: (StreamingAudio, AVAudioPCMBuffer?)?
            var file: AVAudioFile?
            if extended {
                if startSeconds == 0, let prepared = prefetch, prepared.url == track.url {
                    prefetch = nil
                    stream = try await withTaskCancellationHandler {
                        try await prepared.task.value
                    } onCancel: {
                        prepared.task.cancel()
                    }
                } else {
                    cancelPrefetch()
                    let decoder = try await Task.detached(priority: .userInitiated) { try StreamingAudio(source: track.url, seconds: startSeconds) }.value
                    if Task.isCancelled { decoder.cancel(); throw CancellationError() }
                    stream = (decoder, try await decoder.read())
                }
            } else {
                cancelPrefetch()
                file = try await Task.detached(priority: .userInitiated) { try OpenedAudioFile(url: track.url) }.value.file
            }
            // Dispose an unadopted decoder if cancellation occurs during device setup.
            var adoptedStream = false
            defer { if !adoptedStream { stream?.0.cancel() } }
            try Task.checkCancellation()
            let sourceRate = stream?.0.format.sampleRate ?? file!.processingFormat.sampleRate
            if !matchOutputRate { await restoreOutputRate() }
            guard !Task.isCancelled else { return }
            // Rendering is stopped and faded to silence before any device write.
            // Failure leaves us using the device's current format without user-facing noise.
            // Recover at the current hardware rate after a mid-song configuration
            // change. Reasserting our rate here can fight another client/device
            // change and provoke another reset. New tracks/routes still match.
            _ = try? await outputRate.match(source: sourceRate, enabled: matchOutputRate && matchRate)
            guard !Task.isCancelled, currentID == track.id else { return }
            let audio: any AudioPlayback
            if let stream {
                let streaming = try StreamPlayback(decoder: stream.0, first: stream.1, duration: track.duration, equalizer: equalizer)
                streaming.onFailure = { [weak self, weak streaming] error in
                    guard let self, let streaming, self.player === streaming else { return }
                    self.pause()
                    self.message = "Couldn’t play this song. \(error.localizedDescription)"
                }
                audio = streaming
                adoptedStream = true
            } else {
                audio = try EnginePlayback(file: file!, equalizer: equalizer)
            }
            audio.volume = 1
            audio.onNeedsNext = { [weak self, weak audio] in
                guard let self, let audio, self.player === audio else { return }
                self.preloadNext(on: audio)
            }
            audio.onAdvance = { [weak self, weak audio] entryID in
                guard let self, let audio, self.player === audio, self.queue.nextEntry?.id == entryID,
                    let id = self.queue.advance(), let track = self.tracks.first(where: { $0.id == id })
                else { return }
                self.diagnostics.record(.gaplessAdvance)
                self.listenSession.reset()
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
                if self.hasNext {
                    self.next()
                } else {
                    self.stopRendering()
                    self.position = audio.duration
                    self.enqueueAudioOperation { [weak self] in await self?.restoreOutputRate() }
                    self.updateNowPlaying()
                    self.save()
                }
            }
            audio.onConfigurationChange = { [weak self, weak audio] in
                guard let self, let audio, self.player === audio, self.isPlaying || self.preparingPlayback else {
                    return
                }
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
            // Ignore an obsolete file-open failure after the user chose another song.
            guard !Task.isCancelled, currentID == track.id else { return }
            message = "Couldn’t play this song. \(error.localizedDescription)"
            diagnostics.record(.playbackFailed, status: AudioDiagnostics.statusCode(error))
            stopRendering()
            await drainPlayers()
            await restoreOutputRate()
        }
        updateNowPlaying()
        save()
    }

    func togglePlayback() {
        if isPlaying || preparingPlayback {
            pause()
            return
        }
        if let track = current ?? tracks.first {
            select(track, startAt: position, continuingListen: position < track.duration - 0.05)
        }
    }

    var canWriteEmbeddedLyrics: Bool {
        current.map { EmbeddedLyricsWriter.supports($0.url) } ?? false
    }

    // MARK: - Lyrics actions and loading

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
            guard response == .OK, let url = panel.url else {
                self.uploadingLyrics = false
                return
            }
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
                    self.message =
                        "Couldn’t import lyrics. Choose a nonempty .lrc or .txt file under 8 MB. \(error.localizedDescription)"
                }
            }
        }
    }

    func deleteLyrics() {
        guard let track = current, canWriteEmbeddedLyrics, !lyrics.isEmpty,
            !savingLyrics, !uploadingLyrics, !savingCover, !editingMetadata, !loadingLyrics
        else { return }
        let alert = NSAlert()
        alert.messageText = "Delete lyrics?"
        alert.informativeText =
            "Remove embedded lyrics from \(track.url.lastPathComponent) and clear this song’s lyrics in Still Music? This cannot be undone. Separate .lrc and .txt files will remain on disk and may still show lyrics in other players. To remove only your unsaved changes, use Discard changes instead."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard currentID == track.id, !savingLyrics, !uploadingLyrics, !savingCover else { return }
        editEmbeddedLyrics(nil, track: track)
    }

    func writeLyricsToFile() {
        guard let track = current, canWriteEmbeddedLyrics, !lyrics.isEmpty,
            !savingLyrics, !uploadingLyrics, !savingCover, !editingMetadata, !loadingLyrics
        else { return }
        let snapshot = lyrics
        let alert = NSAlert()
        alert.messageText = "Write lyrics to file?"
        alert.informativeText =
            "Replace all embedded lyrics in \(track.url.lastPathComponent) with the lyrics currently displayed? Existing embedded lyrics will be overwritten. Audio and other song tags are preserved."
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
                    message =
                        "The audio file was updated, but Still couldn’t update its lyrics preference. \(error.localizedDescription)"
                }
                if currentID == track.id {
                    lyrics = replacement ?? Lyrics()
                    hasUnsavedLyrics = false
                    canDeleteLyrics = replacement != nil
                    if replacement != nil {
                        savedLyricsTrackID = track.id
                        savedLyricsNoticeTask = Task { [weak self] in
                            do { try await Task.sleep(for: .seconds(3)) } catch { return }
                            self?.savedLyricsTrackID = nil
                        }
                    }
                }
            } catch {
                message =
                    "Couldn’t \(replacement == nil ? "delete" : "write") embedded lyrics. \(error.localizedDescription)"
            }
        }
    }

    func discardLyricsChanges() {
        guard let track = current, hasUnsavedLyrics, !loadingLyrics,
            !savingLyrics, !uploadingLyrics
        else { return }
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
            let (loaded, skipAutomaticLookup, loadedDraft) = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
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

    // MARK: - Artwork

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
    func applySelectedCover(_ data: Data, for track: Track) async {
        guard !savingCover, !savingLyrics, !editingMetadata else { return }
        savingCover = true
        defer { savingCover = false }
        let album = albumTracks(track)
        do { try ArtworkStore.shared.setCover(data, tracks: album) } catch {
            message = "Couldn’t save the selected cover. \(error.localizedDescription)"
            return
        }
        if writeCoversIntoFiles {
            var failures = 0
            for song in album where FileMetadata.supports(song.url) {
                guard writeCoversIntoFiles, !shuttingDown else { break }
                let succeeded = await Task.detached(priority: .utility) {
                    do {
                        try FileMetadata.writeArtwork(data, to: song.url)
                        return true
                    } catch { return false }
                }.value
                if !succeeded { failures += 1 }
            }
            if failures > 0 {
                message =
                    "The cover is saved in Still Music, but couldn’t be written to \(failures) audio file(s). Check file permissions and available disk space."
            }
        }
        ArtworkStore.shared.clear()
        artworkRevision += 1
        if let current { loadArtwork(current) }
    }

    // MARK: - Transport controls

    func pause() {
        listenSession.interrupt()
        cancelPrefetch()
        diagnostics.record(.playbackPaused)
        stopRendering()
        // A temporary pause retains the matched rate; terminal stop restores it.
        enqueueAudioOperation {}
        updateNowPlaying()
        save()
    }

    func stop() {
        cancelPrefetch()
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
        if position > 3 {
            listenSession.reset()
            seek(to: 0)
            return
        }
        if let id = queue.previous(), let track = tracks.first(where: { $0.id == id }) {
            select(track)
        } else {
            seek(to: 0)
        }
    }

    var hasNext: Bool { queue.hasNext }

    func seek(to seconds: Double) {
        listenSession.interrupt()
        guard let track = current else { return }
        position = min(max(0, seconds), track.duration)
        if preparingPlayback {
            select(track, startAt: position, continuingListen: true)
            return
        }
        if isPlaying, let player {
            if player is StreamPlayback {
                select(track, startAt: position, continuingListen: true)
                return
            }
            do { try (player as? EnginePlayback)?.play(from: position) } catch {
                pause()
                message = "Couldn’t seek. \(error.localizedDescription)"
            }
        }
        updateNowPlaying()
    }

    // MARK: - Persistence and listening history

    func save() {
        guard !loadingLibrary, libraryReadable else { return }
        let snapshot =
            libraryDirty
            ? LibrarySnapshot(
                tracks: tracks, currentID: currentID, position: position, volume: 1, favoriteIDs: favoriteIDs,
                theme: theme, sortPreferences: sortPreferences, queue: queue, listeningHistory: listeningHistory) : nil
        libraryDirty = false
        persistence.submit(library: snapshot, position: PlaybackPosition(currentID: currentID, position: position)) {
            [weak self] error in
            if let error {
                Task { @MainActor in
                    self?.libraryDirty = true
                    self?.message = "Your library couldn’t be saved. \(error)"
                }
            }
        }
    }

    private func tick() {
        if isPlaying { position = player?.currentTime ?? 0 }
        if let current,
            listenSession.observe(
                position: position, duration: current.duration, playing: isPlaying,
                uptime: ProcessInfo.processInfo.systemUptime)
        {
            listeningHistory.record(current.id)
            libraryDirty = true
            if section == .onRepeat {
                cachedVisibleTracks = nil
                objectWillChange.send()
            }
            save()
        } else if !isPlaying {
            listenSession.interrupt()
        }
        historyRefreshTicks += 1
        if historyRefreshTicks >= 240 {
            historyRefreshTicks = 0
            if section == .onRepeat {
                cachedVisibleTracks = nil
                objectWillChange.send()
            }
        }
        ticks += 1
        if ticks >= 40 {
            ticks = 0
            if isPlaying { save() }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false { self?.togglePlayback() } }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        let info = MPNowPlayingInfoCenter.default()
        guard let track = current else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            return
        }
        var values: [String: Any] = [
            MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album, MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let artwork {
            values[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        info.nowPlayingInfo = values
        info.playbackState = isPlaying ? .playing : .paused
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = hasNext
    }
    @Published var editingTracks: [Track] = []
    @Published var showingMetadataEditor = false
    @Published var artworkSearchTrack: Track?
    @Published private(set) var editingMetadata = false

    func editSongInfo(_ songs: [Track]) {
        editingTracks = songs.filter { FileMetadata.supports($0.url) }
        showingMetadataEditor = !editingTracks.isEmpty
        if editingTracks.isEmpty { message = "Tag editing supports FLAC, MP3 and M4A files." }
    }

    let metadataProgress = MetadataProgress()
    func cancelMetadataUpdate() { metadataProgress.cancellationRequested = true }

    func writeSongInfo(_ fields: [String: String], songs: [Track]) async -> String? {
        guard !editingMetadata, !refreshing, !savingCover, !savingLyrics else {
            return "Another file edit is in progress."
        }
        editingMetadata = true
        metadataProgress.completed = 0
        metadataProgress.total = songs.count
        metadataProgress.failureCount = 0
        metadataProgress.cancellationRequested = false
        defer { editingMetadata = false }
        var failures: [String] = []
        var edits: [String: Track] = [:]
        for song in songs {
            if metadataProgress.cancellationRequested { break }
            do {
                let updated = try await Task.detached(priority: .utility) {
                    try FileMetadata.write(fields, to: song.url)
                    return try await Track.read(song.url)
                }.value
                edits[song.id] = updated
            } catch { failures.append("\(song.title): \(error.localizedDescription)") }
            metadataProgress.completed += 1
            metadataProgress.failureCount = failures.count
        }
        if !edits.isEmpty {
            tracks = tracks.map { edits[$0.id] ?? $0 }
            artworkRevision += 1
            if let current { loadArtwork(current) }
        }
        updateNowPlaying()
        save()
        if let current { loadLyrics(current) }
        if metadataProgress.cancellationRequested || !failures.isEmpty {
            return
                "Updated \(edits.count) of \(songs.count) songs. \(failures.count) failed. \(songs.count - metadataProgress.completed) not attempted."
                + (failures.isEmpty ? "" : "\n" + failures.joined(separator: "\n"))
        }
        return nil
    }

}
