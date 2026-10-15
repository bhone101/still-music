import AppKit
import StillCore
import SwiftUI

// Keep using the property wrapper when building with SDKs that also export a
// same-named State macro; the command line tools need no SwiftUI macro plugin.
private typealias ViewState<Value> = SwiftUI.State<Value>

private enum Palette {
    private static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    static let paper = adaptive(NSColor(white: 0.98, alpha: 1), .black)
    static let sidebar = adaptive(NSColor(white: 0.94, alpha: 1), NSColor(white: 0.09, alpha: 1))
    static let surface = adaptive(.white, NSColor(white: 0.075, alpha: 1))
    static let ink = adaptive(NSColor(white: 0.12, alpha: 1), NSColor(white: 0.94, alpha: 1))
    static let muted = adaptive(NSColor(white: 0.43, alpha: 1), NSColor(white: 0.60, alpha: 1))
    static let accent = adaptive(NSColor(white: 0.30, alpha: 1), NSColor(white: 0.82, alpha: 1))
    static let selected = adaptive(NSColor(white: 0.86, alpha: 1), NSColor(white: 0.22, alpha: 1))
    static let line = ink.opacity(0.10)
    static let playBlue = Color(.sRGB, red: 58 / 255, green: 107 / 255, blue: 169 / 255)
}

struct ContentView: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var dropTargeted = false
    @ViewState private var columnVisibility: NavigationSplitViewVisibility = .all
    @ViewState private var scrubbing = false
    @ViewState private var scrubPosition: Double = 0
    @ViewState private var detailsTrack: Track?
    @ViewState private var expandedNowPlaying = false
    @ViewState private var showPlaylistName = false
    @ViewState private var editingPlaylist: MusicPlaylist?
    @ViewState private var creatingPlaylistFrom: Track?
    @ViewState private var playlistSongs: MusicPlaylist?
    @ViewState private var deletingPlaylist: MusicPlaylist?

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
                    // Keep the contents laid out at their final width while the
                    // native split view reveals or hides the sidebar.
                    .frame(width: 210)
                    .frame(maxHeight: .infinity)
                    .clipped()
                    .background(.regularMaterial, ignoresSafeAreaEdges: .top)
                    .navigationSplitViewColumnWidth(210)
                    .toolbar(removing: .sidebarToggle)
            } detail: {
                VStack(spacing: 0) {
                    if let message = model.message {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "info.circle")
                            Text(message).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                            Button { model.message = nil } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).accessibilityLabel("Dismiss message")
                        }
                        .foregroundStyle(Palette.ink).padding(14).background(Palette.accent.opacity(0.09))
                    }
                    ZStack(alignment: .bottom) {
                        VStack(spacing: 0) {
                            if model.section == .settings { settings }
                            else if model.tracks.isEmpty && model.section != .playlist { emptyState }
                            else { library }
                            Rectangle().fill(Palette.line).frame(height: 1)
                            playbackBar
                        }
                        .allowsHitTesting(!expandedNowPlaying)
                        .accessibilityHidden(expandedNowPlaying)
                        if expandedNowPlaying {
                            expandedPlayer
                                .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                                .zIndex(1)
                        }
                    }
                    .clipped()
                    .ignoresSafeArea(.container, edges: expandedNowPlaying ? .top : [])
                    .animation(reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.32), value: expandedNowPlaying)
                }.background(Palette.paper.ignoresSafeArea(.container, edges: .top))
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar(removing: .sidebarToggle)
        }
        .frame(minWidth: 1000, minHeight: 620)
        .background(Palette.paper)
        .background(WindowBackground(isDark: model.theme == "black"))
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .preferredColorScheme(model.theme == "black" ? .dark : .light)
        .onChange(of: model.section) { _, _ in expandedNowPlaying = false }
        .onChange(of: model.selectedPlaylistID) { _, _ in expandedNowPlaying = false }
        .sheet(isPresented: $showPlaylistName) { PlaylistNameSheet(model: model, playlist: editingPlaylist, track: creatingPlaylistFrom) }
        .sheet(item: $playlistSongs) { PlaylistSongsSheet(model: model, playlist: $0) }
        .confirmationDialog("Delete playlist?", isPresented: Binding(get: { deletingPlaylist != nil }, set: { if !$0 { deletingPlaylist = nil } }), titleVisibility: .visible, presenting: deletingPlaylist) { playlist in
            Button("Delete playlist", role: .destructive) { model.deletePlaylist(playlist.id); deletingPlaylist = nil }
            Button("Cancel", role: .cancel) { deletingPlaylist = nil }
        } message: { _ in Text("Only the playlist will be deleted. Your songs and playback queue stay unchanged.") }
        .sheet(item: $detailsTrack) { track in TrackDetailsSheet(track: track) }
        // Let each column extend its own background behind the native title bar.
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Preserve toolbar geometry so AppKit does not reposition the window controls.
                HStack(spacing: 12) {
                Button {
                    withAnimation {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .controlSize(.large)
                .accessibilityLabel(columnVisibility == .detailOnly ? "Show sidebar" : "Hide sidebar")
                .help(columnVisibility == .detailOnly ? "Show sidebar" : "Hide sidebar")

                Button(action: model.chooseFiles) {
                    HStack(spacing: 6) {
                        if model.importing { ProgressView().controlSize(.small) }
                        else { Image(systemName: "plus") }
                        Text(model.importing ? "Adding music…" : "Add music")
                    }
                }
                .controlSize(.large)
                .disabled(model.importing)
                .help("Add music · ⌘O")

                Button { model.rescanFoldersIfNeeded(force: true) } label: {
                    HStack(spacing: 6) {
                        if model.scanningFolders { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.clockwise") }
                        Text(model.scanningFolders ? "Scanning…" : "Scan")
                    }
                }
                .controlSize(.large)
                .disabled(model.scanningFolders || model.importing)
                .help("Scan music folders for new songs")
                }
                .opacity(expandedNowPlaying ? 0 : 1)
                .allowsHitTesting(!expandedNowPlaying)
                .accessibilityHidden(expandedNowPlaying)
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .padding(10).allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.importing else { return false }
            model.add(urls)
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            RecordArtwork().frame(width: 142, height: 142).padding(.bottom, 28)
            Text("Just you and the music.")
                .font(.system(size: 30, weight: .regular, design: .default)).tracking(-0.8)
            Text("Drop your files or a folder here to get started.")
                .font(.system(size: 13)).foregroundStyle(Palette.muted).padding(.top, 10)
            Button(action: model.chooseFiles) {
                Text(model.importing ? "Adding your music…" : "Choose music")
                    .font(.system(size: 12, weight: .medium)).padding(.horizontal, 24).padding(.vertical, 11)
            }
            .buttonStyle(.plain).foregroundStyle(Palette.paper).background(Palette.ink, in: Capsule())
            .disabled(model.importing).padding(.top, 23)
            Text("FLAC  /  ALAC  /  WAV  /  AIFF  /  MP3  /  AAC")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1).foregroundStyle(Palette.muted).padding(.top, 20)
            Spacer(minLength: 20)
            Text("Your files. Their original quality.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.bottom, 23)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                if let group = model.selectedGroup {
                    Button { model.selectedGroupID = nil; model.search = "" } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain).accessibilityLabel("Back to \(model.section.rawValue)")
                    Text(group.title).font(.system(size: 22, weight: .semibold)).lineLimit(1)
                } else {
                    Text(model.selectedPlaylist?.name ?? model.section.rawValue).font(.system(size: 22, weight: .semibold)).lineLimit(1)
                }
                Spacer()
                Text(model.section.isGrouped && model.selectedGroup == nil ? "\(model.groups.count) groups" : "\(model.visibleTracks.count) songs")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                if let playlist = model.selectedPlaylist {
                    Button("Add songs") { playlistSongs = playlist }
                    Button("Play") { if let first = model.visibleTracks.first { model.play(first) } }.disabled(model.visibleTracks.isEmpty)
                    Menu { playlistActions(playlist) } label: { Image(systemName: "ellipsis") }.menuIndicator(.hidden).fixedSize()
                } else { sortMenu }
            }.padding(.bottom, 18)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Find in your music", text: $model.search).textFieldStyle(.plain)
                    .accessibilityLabel("Search music")
                if !model.search.isEmpty {
                    Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Clear search")
                }
            }
            .font(.system(size: 12)).padding(10).background(Palette.surface, in: RoundedRectangle(cornerRadius: 6))
            .padding(.bottom, 16)
            if model.section.isGrouped && model.selectedGroup == nil {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.visibleGroups) { group in
                            Button { model.selectedGroupID = group.id; model.search = "" } label: {
                                HStack(spacing: 14) {
                                    if model.section == .albums {
                                        ArtworkThumbnail(urls: group.tracks.map(\.url), size: 48, revision: model.artworkRevision)
                                    } else if model.section == .artists {
                                        ArtworkThumbnail(urls: group.tracks.map(\.url), size: 48, revision: model.artworkRevision, fallbackIcon: "person.fill")
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: model.section.icon).font(.system(size: 22))
                                            .foregroundStyle(Palette.accent).frame(width: 42, height: 42)
                                            .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 7))
                                    }
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(group.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                        Text(group.subtitle.isEmpty ? "\(group.tracks.count) songs" : "\(group.subtitle) · \(group.tracks.count) songs")
                                            .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Palette.muted)
                                }.padding(10).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("Open \(group.title), \(group.tracks.count) songs")
                                .contextMenu {
                                    if model.section == .albums, let track = group.tracks.first {
                                        Button("Choose Album Cover…") { model.chooseAlbumCover(track) }.disabled(model.savingCover)
                                    }
                                }
                        }
                        if model.visibleGroups.isEmpty { noResults }
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.visibleTracks) { track in trackRow(track) }
                        if model.visibleTracks.isEmpty {
                            if let playlist = model.selectedPlaylist, model.search.isEmpty {
                                VStack(spacing: 12) {
                                    Text("This playlist is empty.").font(.headline)
                                    Text("Add songs from your library, or right-click a song and choose Add to playlist.").foregroundStyle(Palette.muted)
                                    Button("Add songs") { playlistSongs = playlist }
                                }.frame(maxWidth: .infinity).padding(.vertical, 45)
                            } else { noResults }
                        }
                    }.padding(.vertical, 6)
                }
            }
        }.padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResults: some View {
        VStack(spacing: 10) {
            Image(systemName: model.section == .favorites ? "heart" : "magnifyingglass").font(.system(size: 24))
            Text(model.section == .favorites && model.search.isEmpty ? "Your favorites belong here." : "No matching music.")
                .font(.system(size: 13))
            if model.section == .favorites && model.search.isEmpty {
                Text("Tap the heart beside a song to save it.").font(.system(size: 11))
            }
        }.foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(.vertical, 45)
    }

    private var sortMenu: some View {
        Menu {
            Menu("Sort By") {
                ForEach(model.sortOptions) { field in
                    Button { model.setSortField(field) } label: {
                        if model.librarySort.field == field {
                            Label(field.rawValue, systemImage: "checkmark")
                        } else { Text(field.rawValue) }
                    }
                }
            }
            Menu("Order") {
                Button { model.setSortAscending(true) } label: {
                    if model.librarySort.ascending { Label("Ascending", systemImage: "checkmark") }
                    else { Text("Ascending") }
                }
                Button { model.setSortAscending(false) } label: {
                    if !model.librarySort.ascending { Label("Descending", systemImage: "checkmark") }
                    else { Text("Descending") }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 36, height: 36).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Sort \(model.selectedGroupID == nil ? model.section.rawValue.lowercased() : "songs")")
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Library").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                        .padding(.horizontal, 12).padding(.bottom, 7)
                    ForEach(LibrarySection.allCases.filter { $0 != .favorites && $0 != .settings && $0 != .playlist }) { section in navigationRow(section) }
                    HStack {
                        Text("Playlists").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                        Spacer()
                        Button {
                            editingPlaylist = nil
                            creatingPlaylistFrom = nil
                            showPlaylistName = true
                        } label: {
                            Image(systemName: "plus").font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Palette.ink).frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel("Create a playlist")
                            .help("Create a playlist")
                    }.padding(.horizontal, 12).padding(.top, 25).padding(.bottom, 7)
                    navigationRow(.favorites)
                    ForEach(model.playlists) { playlist in
                        Button { model.openPlaylist(playlist.id) } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "music.note.list").font(.system(size: 19)).foregroundStyle(Palette.playBlue).frame(width: 25)
                                Text(playlist.name).font(.system(size: 14)).lineLimit(1)
                                Spacer(minLength: 0)
                            }.padding(.horizontal, 12).frame(height: 46).contentShape(Rectangle())
                                .background(model.selectedPlaylistID == playlist.id ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(model.selectedPlaylistID == playlist.id ? .isSelected : [])
                            .contextMenu { playlistActions(playlist) }
                    }
                }
            }.scrollIndicators(.hidden)
            if model.refreshing {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.mini)
                    Text("Reading song details…").font(.system(size: 10))
                }.foregroundStyle(Palette.muted).padding(12)
            }
            Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 8)
            navigationRow(.settings)
        }.padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    settingsSectionTitle("Appearance")
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Theme").font(.system(size: 16, weight: .semibold))
                            Text("Choose your appearance").font(.system(size: 13)).foregroundStyle(Palette.muted)
                        }
                        Spacer(minLength: 12)
                        HStack(spacing: 2) {
                            ForEach(["light", "black"], id: \.self) { theme in
                                let title = theme == "light" ? "Light" : "Dark"
                                Button { model.theme = theme } label: {
                                    Text(title).font(.system(size: 14, weight: .medium))
                                        .frame(width: 66, height: 34)
                                        .foregroundStyle(model.theme == theme ? Palette.ink : Palette.muted)
                                        .background(model.theme == theme ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: 9))
                                }.buttonStyle(.plain).accessibilityLabel("\(title) theme")
                                    .accessibilityAddTraits(model.theme == theme ? .isSelected : [])
                            }
                        }.padding(3).background(Palette.paper, in: RoundedRectangle(cornerRadius: 12))
                    }.padding(20).frame(maxWidth: .infinity, minHeight: 86)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                VStack(alignment: .leading, spacing: 10) {
                    settingsSectionTitle("Lyrics")
                    settingsToggle("Find lyrics online",
                        description: "When local lyrics are missing or unsynced, search LRCLIB by title and artist. Synced results can replace plain lyrics in the player. Off by default.",
                        value: $model.findLyricsOnline)

                }
                VStack(alignment: .leading, spacing: 10) {
                    settingsSectionTitle("Artwork")
                    settingsToggle("Write covers into files",
                        description: "Also write a chosen album cover into that album’s FLAC files. Turning this off does not undo earlier writes.",
                        value: $model.writeCoversIntoFiles)
                }
                Text("LRCLIB receives the search metadata and normal connection information, including your IP address. Audio files and local paths are never uploaded. Automatic requests are off unless enabled. Find online performs a one-song search. Uploads and search results stay in the app until you choose Write lyrics to file.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.horizontal, 5)
            }.padding(24).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func settingsSectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.muted).padding(.horizontal, 5)
    }

    private func settingsToggle(_ title: String, description: String, value: Binding<Bool>) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(description).font(.system(size: 13)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).tint(Palette.playBlue)
                .controlSize(.large).accessibilityLabel(title).accessibilityHint(description)
        }.padding(20).frame(maxWidth: .infinity, minHeight: 86)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func navigationRow(_ section: LibrarySection) -> some View {
        Button {
            if section == .playlist { editingPlaylist = nil; creatingPlaylistFrom = nil; showPlaylistName = true }
            else { model.section = section }
        } label: {
            HStack(spacing: 13) {
                Image(systemName: section.icon).font(.system(size: 19)).foregroundStyle(Palette.playBlue).frame(width: 25)
                Text(section.rawValue).font(.system(size: 14, weight: model.section == section ? .semibold : .regular))
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).frame(height: 46).contentShape(Rectangle())
                .background(model.section == section && section != .playlist ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityLabel(section.rawValue)
            .accessibilityAddTraits(model.section == section && section != .playlist ? .isSelected : [])
    }

    @ViewBuilder
    private func playlistActions(_ playlist: MusicPlaylist) -> some View {
        Button("Add songs…") { playlistSongs = playlist }
        Button("Rename…") { editingPlaylist = playlist; creatingPlaylistFrom = nil; showPlaylistName = true }
        Button("Delete playlist…", role: .destructive) { deletingPlaylist = playlist }
    }

    private func trackRow(_ track: Track) -> some View {
        let selected = track.id == model.currentID
        return HStack(spacing: 0) {
            Button { model.play(track) } label: {
                HStack(spacing: 11) {
                    ArtworkThumbnail(urls: [track.url], size: 36, revision: model.artworkRevision)
                        .overlay(alignment: .bottomTrailing) {
                            if selected && model.isPlaying {
                                Image(systemName: "waveform").font(.system(size: 8, weight: .bold))
                                    .padding(3).foregroundStyle(Palette.paper).background(Palette.ink, in: Circle())
                            }
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).font(.system(size: 14, weight: selected ? .semibold : .medium)).lineLimit(1)
                        Text(track.album.isEmpty ? track.artist : "\(track.artist) · \(track.album)")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(track.codec).font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.muted).frame(width: 57, alignment: .leading)
                    Text(track.bitRateLabel).font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.muted).frame(width: 88, alignment: .trailing)
                    Text(timeLabel(track.duration)).font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.muted).frame(width: 44, alignment: .trailing)
                }.padding(.vertical, 12).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("Play \(track.title), \(track.artist), \(track.quality)")
            Button { model.toggleFavorite(track) } label: {
                Image(systemName: model.favoriteIDs.contains(track.id) ? "heart.fill" : "heart")
                    .font(.system(size: 17)).foregroundStyle(model.favoriteIDs.contains(track.id) ? Palette.accent : Palette.muted)
                    .frame(width: 36, height: 40).contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.leading, 11)
                .accessibilityLabel("\(model.favoriteIDs.contains(track.id) ? "Unfavorite" : "Favorite") \(track.title)")
        }.padding(.horizontal, 12)
            .background(selected ? Palette.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contextMenu {
                Button("Choose Album Cover…") { model.chooseAlbumCover(track) }.disabled(model.savingCover)
                Divider()
                Button("Play Next") { model.enqueue(track, next: true) }
                Button("Add to Queue") { model.enqueue(track, next: false) }
                Menu("Add to playlist") {
                    Button("Create a playlist…") { editingPlaylist = nil; creatingPlaylistFrom = track; showPlaylistName = true }
                    if !model.playlists.isEmpty { Divider() }
                    ForEach(model.playlists) { playlist in
                        Button(playlist.name) { model.addToPlaylist(track, id: playlist.id) }.disabled(playlist.trackIDs.contains(track.id))
                    }
                }
                if let playlist = model.selectedPlaylist {
                    Button("Remove from playlist") { model.removeFromPlaylist(track, id: playlist.id) }
                    Button("Move up") { model.movePlaylistSong(track, by: -1) }.disabled(playlist.trackIDs.first == track.id)
                    Button("Move down") { model.movePlaylistSong(track, by: 1) }.disabled(playlist.trackIDs.last == track.id)
                }
                Divider()
                Button("Details") { detailsTrack = track }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([track.url]) }
                Divider()
                Button("Remove from library") { model.remove(track) }
            }
    }

    private func playbackIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: expandedNowPlaying ? 24 : 20))
            .frame(width: expandedNowPlaying ? 40 : 36, height: expandedNowPlaying ? 48 : 40)
            .contentShape(Rectangle())
    }

    private var playbackBar: some View {
        HStack(spacing: 20) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Group {
                        if let artwork = model.artwork {
                            Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            ZStack {
                                Palette.sidebar
                                Image(systemName: "music.note").font(.system(size: 24)).foregroundStyle(Palette.muted)
                            }
                        }
                    }.frame(width: 56, height: 56).clipped().clipShape(RoundedRectangle(cornerRadius: 7))
                        .accessibilityLabel("Now playing artwork")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.current?.title ?? "Nothing playing")
                            .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            .help(model.current?.title ?? "Choose a song from your library")
                        Text(model.current.map { $0.album.isEmpty ? $0.artist : "\($0.artist) · \($0.album)" } ?? "Choose a song from your library")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(1)
                        if let current = model.current {
                            Text(current.quality).font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(Palette.accent)
                                .help("Source file quality. Playback uses the system audio output.")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                playbackProgress
            }.frame(minWidth: 0, maxWidth: .infinity)
            playbackControls
        }.padding(.horizontal, 24).padding(.vertical, 17).background(.regularMaterial)
            .contentShape(Rectangle())
            // A normal ancestor tap lets buttons and the slider consume their own input.
            .onTapGesture { if model.current != nil { expandedNowPlaying = true } }
            .accessibilityAction(named: "Expand now playing") {
                if model.current != nil { expandedNowPlaying = true }
            }
    }

    private var playbackProgress: some View {
        HStack(spacing: 8) {
            Text(timeLabel(scrubbing ? scrubPosition : model.position)).frame(width: 36, alignment: .leading)
            Slider(value: Binding(get: { scrubbing ? scrubPosition : model.position }, set: { scrubPosition = $0; if !scrubbing { model.seek(to: $0) } }),
                   in: 0...max(model.current?.duration ?? 1, 1), onEditingChanged: { editing in
                if editing { scrubPosition = model.position; scrubbing = true }
                else { model.seek(to: scrubPosition); scrubbing = false }
            })
            .controlSize(.mini).disabled(model.current == nil).accessibilityLabel("Playback position")
            Text(model.current == nil ? "0:00" : "−" + timeLabel(max(0, (model.current?.duration ?? 0) - (scrubbing ? scrubPosition : model.position))))
                .frame(width: 42, alignment: .trailing).accessibilityLabel("Time remaining")
        }.font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
    }

    private var playbackControls: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button(action: model.cyclePlaybackMode) {
                playbackIcon(model.queue.isLooping ? "repeat" : "shuffle").foregroundStyle(model.queue.isShuffled || model.queue.isLooping ? Palette.playBlue : Palette.muted)
            }.buttonStyle(.plain).accessibilityLabel("Playback mode").accessibilityValue(model.queue.isShuffled ? "Shuffle" : model.queue.isLooping ? "Loop" : "Off")
                .help("Playback mode: \(model.queue.isShuffled ? "Shuffle" : model.queue.isLooping ? "Loop" : "Off") · Click to cycle Shuffle, Loop, Off")
                .disabled(model.current == nil)
            Spacer(minLength: 8)
            Button(action: model.previous) { playbackIcon("backward.end.fill") }
                .buttonStyle(.plain).disabled(model.current == nil).help("Previous · ⌘←").accessibilityLabel("Previous track")
            Spacer(minLength: 8)
            Button(action: model.togglePlayback) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: expandedNowPlaying ? 28 : 20, weight: .semibold)).offset(x: model.isPlaying ? 0 : 1)
                        .frame(width: expandedNowPlaying ? 72 : 56, height: expandedNowPlaying ? 72 : 56).foregroundStyle(.white)
                        .background(Palette.playBlue.opacity(model.current == nil ? 0.3 : 1), in: Circle())
                        .contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.current == nil)
                .help("Play / pause · Space").accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            Spacer(minLength: 8)
            Button(action: model.next) { playbackIcon("forward.end.fill") }
                .buttonStyle(.plain).disabled(!model.hasNext).help("Next · ⌘→").accessibilityLabel("Next track")
            Spacer(minLength: 8)
            QueueButton(model: model, expanded: expandedNowPlaying)
            Spacer(minLength: 0)
            }.frame(minWidth: 0, maxWidth: .infinity)
    }


    private var expandedPlayer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                expandedNowPlaying = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse now playing")
            .keyboardShortcut(.escape, modifiers: [])

            GeometryReader { geometry in
                let columnWidth = min(480, geometry.size.width * 0.42)
                let columnSpacing = min(100, geometry.size.width * 0.08)
                let artworkHeight = min(columnWidth, max(120, geometry.size.height - 270))
                HStack(alignment: .top, spacing: columnSpacing) {
                        VStack(alignment: .leading, spacing: 16) {
                            Group {
                                if let artwork = model.artwork {
                                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Image(systemName: "music.note")
                                        .font(.system(size: 72)).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(Palette.surface)
                                }
                            }
                            .frame(width: columnWidth, height: artworkHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .accessibilityLabel("Now playing artwork")

                            if let track = model.current {
                                HStack {
                                    Text(track.title).font(.system(size: 24, weight: .bold)).lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 8)
                                    Button { model.toggleFavorite(track) } label: {
                                        playbackIcon(model.favoriteIDs.contains(track.id) ? "heart.fill" : "heart")
                                    }.buttonStyle(.plain)
                                        .accessibilityLabel(model.favoriteIDs.contains(track.id) ? "Remove from favorites" : "Add to favorites")
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(track.artist).font(.system(size: 20)).lineLimit(1)
                                    Text([track.quality, track.bitRate == nil ? "" : track.bitRateLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.system(size: 12, design: .monospaced)).lineLimit(1)
                                }.foregroundStyle(.secondary)
                            }
                            playbackProgress
                            playbackControls
                        }.frame(width: columnWidth, height: geometry.size.height, alignment: .center)
                    LyricsView(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }.padding(24)
            .padding(.top, columnVisibility == .detailOnly ? 40 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
            .background(Palette.paper)
    }

}

// Full-screen title bars can expose the NSWindow backing color even when
// SwiftUI supplies a toolbar background. Keep both surfaces in the same theme.
private struct WindowBackground: NSViewRepresentable {
    let isDark: Bool

    func makeNSView(context: Context) -> BackgroundView { BackgroundView() }
    func updateNSView(_ view: BackgroundView, context: Context) {
        view.color = isDark ? .black : NSColor(white: 0.98, alpha: 1)
        view.apply()
    }

    final class BackgroundView: NSView {
        var color: NSColor = .black
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }
        func apply() {
            window?.backgroundColor = color
            window?.titlebarAppearsTransparent = true
            window?.toolbar?.showsBaselineSeparator = false
        }
    }
}

private struct RecordArtwork: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.82))
                Circle().fill(Color(white: 0.18)).frame(width: size * 0.79, height: size * 0.79)
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 3, y: 7)
                ForEach(0..<8) { ring in
                    Circle().stroke(.white.opacity(0.065), lineWidth: 0.6)
                        .frame(width: size * (0.39 + Double(ring) * 0.049), height: size * (0.39 + Double(ring) * 0.049))
                }
                Circle().fill(Color(white: 0.64)).frame(width: size * 0.28, height: size * 0.28)
                Circle().fill(Color(white: 0.18)).frame(width: size * 0.035, height: size * 0.035)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.accessibilityHidden(true)
    }
}

private struct ArtworkThumbnail: View {
    let urls: [URL]
    let size: CGFloat
    var revision = 0
    var fallbackIcon = "music.note"
    @ViewState private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Palette.sidebar
                    Image(systemName: fallbackIcon).font(.system(size: size * 0.4)).foregroundStyle(Palette.muted)
                }
            }
        }
        .frame(width: size, height: size).clipped().clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityHidden(true)
        .task(id: urls.map(\.path).joined(separator: "\u{0}") + String(revision)) {
            image = nil
            for url in urls {
                let loaded = await ArtworkStore.shared.image(for: url)
                guard !Task.isCancelled else { return }
                if let loaded { image = loaded; return }
            }
        }
    }
}
