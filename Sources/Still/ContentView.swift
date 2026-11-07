import AppKit
import StillCore
import SwiftUI

// Keep using the property wrapper when building with SDKs that also export a
// same-named State macro; the command line tools need no SwiftUI macro plugin.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct ContentView: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var dropTargeted = false
    @ViewState private var columnVisibility: NavigationSplitViewVisibility = .all
    @ViewState private var detailsTrack: Track?
    @ViewState private var expandedNowPlaying = false
    @ViewState private var returningToPlayer = false
    @AppStorage("StillLargerText") private var largerText = false
    @ViewState private var showPlaylistName = false
    @ViewState private var editingPlaylist: MusicPlaylist?
    @ViewState private var creatingPlaylistFrom: [Track] = []
    @ViewState private var playlistSongs: MusicPlaylist?
    @ViewState private var deletingPlaylist: MusicPlaylist?
    @ViewState private var deletingSong: Track?

    @ViewState private var compact = false
    @ViewState private var availableWidth: CGFloat = 1000
    @ViewState private var clickedSongID: String?

    var body: some View {
        GeometryReader { window in
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
                        if returningToPlayer && !expandedNowPlaying {
                            HStack {
                                Button { expandedNowPlaying = true; returningToPlayer = false } label: {
                                    Label("Return to Now Playing", systemImage: "arrow.uturn.backward")
                                }
                                Spacer()
                            }.padding(12)
                        }
                        if let message = model.message {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "info.circle")
                                Text(message).font(.system(size: largerText ? 15 : 12)).frame(maxWidth: .infinity, alignment: .leading)
                                Button {
                                    model.message = nil
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.plain).accessibilityLabel("Dismiss message")
                            }
                            .foregroundStyle(Palette.ink).padding(14).background(Palette.accent.opacity(0.09))
                        }
                        ZStack(alignment: .bottom) {
                            VStack(spacing: 0) {
                                if model.section == .settings {
                                    settings
                                } else if model.tracks.isEmpty && model.section != .playlist {
                                    emptyState
                                } else {
                                    library
                                }
                                Rectangle().fill(Palette.line).frame(height: 1)
                                playbackBar
                            }
                            .allowsHitTesting(!expandedNowPlaying)
                            .accessibilityHidden(expandedNowPlaying)
                            if expandedNowPlaying {
                                Group { if compact { compactExpandedPlayer } else { expandedPlayer } }
                                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                                    .zIndex(1)
                            }
                        }
                        .clipped()
                        .ignoresSafeArea(.container, edges: expandedNowPlaying ? .top : [])
                        .animation(
                            reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.32),
                            value: expandedNowPlaying)
                    }.background(Palette.paper.ignoresSafeArea(.container, edges: .top))
                }
                .navigationSplitViewStyle(.balanced)
                .toolbar(removing: .sidebarToggle)
            }
            .onChange(of: window.size.width, initial: true) { _, width in
                availableWidth = width
                compact = width < (largerText ? 1100 : 850)
                if compact { columnVisibility = .detailOnly }
            }
        }
        .onChange(of: largerText) { _, _ in
            compact = availableWidth < (largerText ? 1100 : 850)
            if compact { columnVisibility = .detailOnly }
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(Palette.paper)
        .background(WindowBackground(isDark: model.theme == "black"))
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .preferredColorScheme(model.theme == "black" ? .dark : .light)
        .onChange(of: model.section) { _, _ in expandedNowPlaying = false }
        .onChange(of: model.selectedPlaylistID) { _, _ in expandedNowPlaying = false }
        .sheet(isPresented: $showPlaylistName) {
            PlaylistNameSheet(model: model, playlist: editingPlaylist, tracks: creatingPlaylistFrom)
        }
        .sheet(item: $playlistSongs) { PlaylistSongsSheet(model: model, playlist: $0) }
        .confirmationDialog(
            "Delete playlist?",
            isPresented: Binding(get: { deletingPlaylist != nil }, set: { if !$0 { deletingPlaylist = nil } }),
            titleVisibility: .visible, presenting: deletingPlaylist
        ) { playlist in
            Button("Delete playlist", role: .destructive) {
                model.deletePlaylist(playlist.id)
                deletingPlaylist = nil
            }
            Button("Cancel", role: .cancel) { deletingPlaylist = nil }
        } message: { _ in
            Text("Only the playlist will be deleted. Your songs and playback queue stay unchanged.")
        }
        .alert(
            "Permanently delete song?",
            isPresented: Binding(get: { deletingSong != nil }, set: { if !$0 { deletingSong = nil } }),
            presenting: deletingSong
        ) { song in
            Button("Cancel", role: .cancel) { deletingSong = nil }
            Button("Delete File", role: .destructive) {
                model.deleteSongFile(song)
                deletingSong = nil
            }.disabled(!model.canDeleteSong)
        } message: { song in
            Text("Delete “\(song.title)”?\n\nThis permanently deletes the actual audio file from your Mac and removes it from Still’s library and playlists. It will not go to the Trash and cannot be undone in Still.\n\n\(song.url.path)")
        }
        .sheet(isPresented: $model.showingMetadataEditor) {
            MetadataEditor(model: model, songs: model.editingTracks, progress: model.metadataProgress)
        }
        .sheet(item: $model.artworkSearchTrack) { track in ArtworkSearchSheet(model: model, track: track) }
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
                            if model.importing { ProgressView().controlSize(.small) } else { Image(systemName: "plus") }
                            if !compact { Text(model.importing ? "Adding music…" : "Add music") }
                        }
                    }
                    .controlSize(.large)
                    .disabled(model.importing)
                    .help("Add music · ⌘O")

                    Button {
                        model.rescanFoldersIfNeeded(force: true)
                    } label: {
                        HStack(spacing: 6) {
                            if model.scanningFolders {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            if !compact { Text(model.scanningFolders ? "Scanning…" : "Scan") }
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
                RoundedRectangle(cornerRadius: 12).strokeBorder(
                    Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .padding(10).allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.importing else { return false }
            model.add(urls)
            return !urls.isEmpty
        } isTargeted: {
            dropTargeted = $0
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            RecordArtwork().frame(width: 142, height: 142).padding(.bottom, 28)
            Text("Just you and the music.")
                .font(.system(size: 30, weight: .regular, design: .default)).tracking(-0.8)
            Text("Drop your files or a folder here to get started.")
                .font(.system(size: largerText ? 16 : 13)).foregroundStyle(Palette.muted).padding(.top, 10)
            Button(action: model.chooseFiles) {
                Text(model.importing ? "Adding your music…" : "Choose music")
                    .font(.system(size: 12, weight: .medium)).padding(.horizontal, 24).padding(.vertical, 11)
            }
            .buttonStyle(.plain).foregroundStyle(Palette.paper).background(Palette.ink, in: Capsule())
            .disabled(model.importing).padding(.top, 23)
            Text("FLAC / ALAC / WAV / AIFF / MP3 / AAC / Opus / Ogg / APE / WavPack")
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
                    Button {
                        model.selectedGroupID = nil
                        model.search = ""
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain).accessibilityLabel("Back to \(model.section.rawValue)")
                    Text(group.title).font(.system(size: 22, weight: .semibold)).lineLimit(1)
                } else {
                    Text(model.selectedPlaylist?.name ?? model.section.rawValue).font(
                        .system(size: 22, weight: .semibold)
                    ).lineLimit(1)
                }
                Spacer()
                Text(
                    model.section.isGrouped && model.selectedGroup == nil
                        ? "\(model.groups.count) groups"
                        : "\(model.visibleTracks.count) \(model.visibleTracks.count == 1 ? "song" : "songs")"
                )
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                if let playlist = model.selectedPlaylist {
                    Button("Add songs") { playlistSongs = playlist }
                    Button("Play") { if let first = model.visibleTracks.first { model.play(first) } }.disabled(
                        model.visibleTracks.isEmpty)
                    Menu {
                        playlistActions(playlist)
                    } label: {
                        Image(systemName: "ellipsis")
                    }.menuIndicator(.hidden).fixedSize()
                } else {
                    if model.section == .favorites || model.section == .onRepeat {
                        Button("Play") { if let first = model.visibleTracks.first { model.play(first) } }
                            .disabled(model.visibleTracks.isEmpty)
                    }
                    if model.section != .onRepeat { sortMenu }
                }
            }.padding(.bottom, 10)
            if model.section == .onRepeat {
                Text("Your most-played songs from the last 30 days. Updates as you listen.")
                    .font(.system(size: largerText ? 15 : 12)).foregroundStyle(Palette.muted).padding(.bottom, 10)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Find in your music", text: $model.search).textFieldStyle(.plain)
                    .accessibilityLabel("Search music")
                if !model.search.isEmpty {
                    Button {
                        model.search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Clear search")
                }
            }
            .font(.system(size: largerText ? 15 : 12)).padding(10).background(Palette.surface, in: RoundedRectangle(cornerRadius: 6))
            .padding(.bottom, 8)
            if model.section.isGrouped && model.selectedGroup == nil {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.visibleGroups) { group in
                            Button {
                                model.selectedGroupID = group.id
                                model.search = ""
                            } label: {
                                HStack(spacing: 14) {
                                    if model.section == .albums {
                                        ArtworkThumbnail(
                                            urls: group.tracks.map(\.url), size: 48, revision: model.artworkRevision)
                                    } else if model.section == .artists {
                                        ArtworkThumbnail(
                                            urls: group.tracks.map(\.url), size: 48, revision: model.artworkRevision,
                                            fallbackIcon: "person.fill"
                                        )
                                        .clipShape(Circle())
                                    } else {
                                        Image(systemName: model.section.icon).font(.system(size: 22))
                                            .foregroundStyle(Palette.accent).frame(width: 42, height: 42)
                                            .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 7))
                                    }
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(group.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                        Text(
                                            group.subtitle.isEmpty
                                                ? "\(group.tracks.count) songs"
                                                : "\(group.subtitle) · \(group.tracks.count) songs"
                                        )
                                        .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(
                                        Palette.muted)
                                }.padding(10).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("Open \(group.title), \(group.tracks.count) songs")
                                .contextMenu {
                                    if model.section == .albums, let track = group.tracks.first {
                                        Button("Edit Album Info…") { model.editSongInfo(group.tracks) }.disabled(
                                            model.editingMetadata)
                                        Button("Find Album Cover…") { model.artworkSearchTrack = track }.disabled(
                                            model.savingCover)
                                        Button("Choose Album Cover…") { model.chooseAlbumCover(track) }.disabled(
                                            model.savingCover)
                                    }
                                }
                        }
                        if model.visibleGroups.isEmpty { noResults }
                    }
                }
            } else {
                List(selection: $model.selectedSongIDs) {
                    ForEach(model.visibleTracks) { track in
                        trackRow(track).tag(track.id)
                            .listRowSeparator(.hidden)
                    }
                    if model.visibleTracks.isEmpty {
                        if let playlist = model.selectedPlaylist, model.search.isEmpty {
                            VStack(spacing: 12) {
                                Text("This playlist is empty.").font(.headline)
                                Button("Add songs") { playlistSongs = playlist }
                            }.frame(maxWidth: .infinity).padding(.vertical, 30)
                        } else {
                            noResults
                        }
                    }
                }
                .listStyle(.inset)
                .contextMenu(forSelectionType: String.self) { ids in
                    let songs = model.visibleTracks.filter { ids.contains($0.id) }
                    if !songs.isEmpty { trackActions(songs) }
                } primaryAction: { ids in
                    let clicked = clickedSongID.flatMap { id in
                        ids.contains(id) ? model.visibleTracks.first(where: { $0.id == id }) : nil
                    }
                    if let track = clicked ?? model.visibleTracks.first(where: { ids.contains($0.id) }) {
                        model.play(track)
                    }
                }
                .scrollContentBackground(.hidden)

            }
        }.padding(.horizontal, compact ? 14 : 22).padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResults: some View {
        VStack(spacing: 10) {
            Image(
                systemName: model.section == .favorites
                    ? "heart" : (model.section == .onRepeat && model.search.isEmpty ? "repeat" : "magnifyingglass")
            ).font(.system(size: 24))
            Text(
                model.section == .onRepeat && model.search.isEmpty
                    ? "Your repeats start here."
                    : model.section == .favorites && model.search.isEmpty
                        ? "Your favorites belong here." : "No matching music."
            )
            .font(.system(size: largerText ? 16 : 13))
            if model.section == .onRepeat && model.search.isEmpty {
                Text("Keep listening. Your most-played songs will appear here automatically.").font(.system(size: 11))
            }
            if model.section == .favorites && model.search.isEmpty {
                Text("Tap the heart beside a song to save it.").font(.system(size: 11))
            }
        }.foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(.vertical, 45)
    }

    private var sortMenu: some View {
        Menu {
            Menu("Sort By") {
                ForEach(model.sortOptions) { field in
                    Button {
                        model.setSortField(field)
                    } label: {
                        if model.librarySort.field == field {
                            Label(field.rawValue, systemImage: "checkmark")
                        } else {
                            Text(field.rawValue)
                        }
                    }
                }
            }
            Menu("Order") {
                Button {
                    model.setSortAscending(true)
                } label: {
                    if model.librarySort.ascending {
                        Label("Ascending", systemImage: "checkmark")
                    } else {
                        Text("Ascending")
                    }
                }
                Button {
                    model.setSortAscending(false)
                } label: {
                    if !model.librarySort.ascending {
                        Label("Descending", systemImage: "checkmark")
                    } else {
                        Text("Descending")
                    }
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
                    ForEach(
                        LibrarySection.allCases.filter {
                            $0 != .favorites && $0 != .onRepeat && $0 != .settings && $0 != .playlist
                        }
                    ) { section in navigationRow(section) }
                    HStack {
                        Text("Playlists").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                        Spacer()
                        Button {
                            editingPlaylist = nil
                            creatingPlaylistFrom = []
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
                    navigationRow(.onRepeat)
                    ForEach(model.playlists) { playlist in
                        Button {
                            model.openPlaylist(playlist.id)
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "music.note.list").font(.system(size: 19)).foregroundStyle(
                                    model.selectedPlaylistID == playlist.id ? Palette.playBlue : Palette.muted
                                ).frame(width: 25)
                                Text(playlist.name).font(.system(size: 14)).lineLimit(1)
                                Spacer(minLength: 0)
                            }.padding(.horizontal, 12).frame(height: 46).contentShape(Rectangle())
                                .background(
                                    model.selectedPlaylistID == playlist.id ? Palette.selected : .clear,
                                    in: RoundedRectangle(cornerRadius: 12))
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
                    Toggle("Larger library text", isOn: $largerText)
                        .help("Use larger song text and the compact player layout.")
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Theme").font(.system(size: 16, weight: .semibold))
                            Text("Choose your appearance").font(.system(size: largerText ? 16 : 13)).foregroundStyle(Palette.muted)
                        }
                        Spacer(minLength: 12)
                        HStack(spacing: 2) {
                            ForEach(["light", "black"], id: \.self) { theme in
                                let title = theme == "light" ? "Light" : "Dark"
                                Button {
                                    model.theme = theme
                                } label: {
                                    Text(title).font(.system(size: 14, weight: .medium))
                                        .frame(width: 66, height: 34)
                                        .foregroundStyle(model.theme == theme ? Palette.ink : Palette.muted)
                                        .background(
                                            model.theme == theme ? Palette.selected : .clear,
                                            in: RoundedRectangle(cornerRadius: 9))
                                }.buttonStyle(.plain).accessibilityLabel("\(title) theme")
                                    .accessibilityAddTraits(model.theme == theme ? .isSelected : [])
                            }
                        }.padding(3).background(Palette.paper, in: RoundedRectangle(cornerRadius: 12))
                    }.padding(20).frame(maxWidth: .infinity, minHeight: 86)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                VStack(alignment: .leading, spacing: 10) {
                    settingsSectionTitle("Playback")
                    EqualizerView(model: model)
                }
                VStack(alignment: .leading, spacing: 10) {
                    settingsSectionTitle("Lyrics")
                    settingsToggle(
                        "Find lyrics online",
                        description:
                            "When local lyrics are missing or unsynced, search LRCLIB by title and artist. Synced results can replace plain lyrics in the player. Off by default.",
                        value: $model.findLyricsOnline)

                }
                VStack(alignment: .leading, spacing: 10) {
                    settingsSectionTitle("Artwork")
                    settingsToggle(
                        "Write covers into files",
                        description:
                            "Also write a chosen album cover into that album’s FLAC, MP3 and M4A files. Turning this off does not undo earlier writes.",
                        value: $model.writeCoversIntoFiles)
                }
                Text(
                    "LRCLIB receives the search metadata and normal connection information, including your IP address. Audio files and local paths are never uploaded. Automatic requests are off unless enabled. Find online performs a one-song search. Uploads and search results stay in the app until you choose Write lyrics to file."
                )
                .font(.system(size: largerText ? 15 : 12)).foregroundStyle(Palette.muted).padding(.horizontal, 5)
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
                Text(description).font(.system(size: largerText ? 16 : 13)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).tint(Palette.playBlue)
                .controlSize(.large).accessibilityLabel(title).accessibilityHint(description)
        }.padding(20).frame(maxWidth: .infinity, minHeight: 86)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func navigationRow(_ section: LibrarySection) -> some View {
        Button {
            if section == .playlist {
                editingPlaylist = nil
                creatingPlaylistFrom = []
                showPlaylistName = true
            } else {
                model.section = section
            }
        } label: {
            HStack(spacing: 13) {
                Image(systemName: section.icon).font(.system(size: 19)).foregroundStyle(
                    model.section == section ? Palette.playBlue : Palette.muted
                ).frame(width: 25)
                Text(section.rawValue).font(.system(size: largerText ? 17 : 14, weight: model.section == section ? .semibold : .regular))
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).frame(height: 46).contentShape(Rectangle())
                .background(
                    model.section == section && section != .playlist ? Palette.selected : .clear,
                    in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityLabel(section.rawValue)
            .accessibilityAddTraits(model.section == section && section != .playlist ? .isSelected : [])
    }

    @ViewBuilder
    private func playlistActions(_ playlist: MusicPlaylist) -> some View {
        Button("Add songs…") { playlistSongs = playlist }
        Button("Rename…") {
            editingPlaylist = playlist
            creatingPlaylistFrom = []
            showPlaylistName = true
        }
        Button("Delete playlist…", role: .destructive) { deletingPlaylist = playlist }
    }

    private func trackRow(_ track: Track) -> some View {
        let selected = track.id == model.currentID
        return HStack(spacing: 0) {
            HStack(spacing: 11) {
                ArtworkThumbnail(urls: [track.url], size: 28, revision: model.artworkRevision)
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            Image(systemName: "waveform").font(.system(size: 8, weight: .bold))
                                .padding(3).foregroundStyle(Palette.paper).background(Palette.ink, in: Circle())
                        }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).font(.system(size: largerText ? 18 : 14, weight: selected ? .semibold : .medium)).lineLimit(1)
                    Text(track.album.isEmpty ? track.artist : "\(track.artist) · \(track.album)")
                        .font(.system(size: largerText ? 15 : 12)).foregroundStyle(.secondary).lineLimit(1)
                    if largerText || compact {
                        Text(timeLabel(track.duration)).font(.caption).foregroundStyle(Palette.muted)
                    }
                }
                Spacer(minLength: 6)
                if !compact {
                    Text(track.codec).font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary).frame(width: 57, alignment: .leading)
                    Text(track.bitRateLabel).font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary).frame(width: 88, alignment: .trailing)
                }
                if !largerText && !compact {
                    Text(timeLabel(track.duration)).font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                }
            }.padding(.vertical, 4).contentShape(Rectangle())
                .accessibilityLabel("\(track.title), \(track.artist), \(track.quality)")
                .accessibilityAction(named: "Play") { model.play(track) }
            Button {
                model.toggleFavorite(track)
            } label: {
                Image(systemName: model.favoriteIDs.contains(track.id) ? "heart.fill" : "heart")
                    .font(.system(size: 17)).foregroundStyle(.secondary)
                    .frame(width: 36, height: 40).contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.leading, 11)
                .accessibilityLabel(
                    "\(model.favoriteIDs.contains(track.id) ? "Unfavorite" : "Favorite") \(track.title)")
            Menu {
                trackActions(track)
            } label: {
                Image(systemName: "ellipsis").frame(width: 28, height: 32).contentShape(Rectangle())
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .foregroundStyle(.secondary).help("Song actions").accessibilityLabel("Actions for \(track.title)")
        }.padding(.horizontal, 8)
            .foregroundStyle(.primary)
            .background(
                SongClickObserver(
                    clicked: { clickedSongID = track.id },
                    secondaryClicked: {
                        // Preserve batch selection only when the clicked song belongs to it.
                        if !model.selectedSongIDs.contains(track.id) { model.selectedSongIDs = [track.id] }
                    }))
    }

    private func trackActions(_ track: Track) -> some View {
        trackActions(model.selectedSongIDs.contains(track.id) ? model.selectedSongs : [track])
    }

    @ViewBuilder
    private func trackActions(_ songs: [Track]) -> some View {
        if let track = songs.first {
            let multiple = songs.count > 1
            Button(multiple ? "Edit Song Info for \(songs.count) Songs…" : "Edit Song Info…") {
                model.editSongInfo(songs)
            }.disabled(model.editingMetadata)
            if !multiple {
                Button("Find Album Cover…") { model.artworkSearchTrack = track }.disabled(model.savingCover)
                Button("Choose Album Cover…") { model.chooseAlbumCover(track) }.disabled(model.savingCover)
            }
            Divider()
            Button(multiple ? "Play \(songs.count) Songs Next" : "Play Next") { model.enqueue(songs, next: true) }
            Button(multiple ? "Add \(songs.count) Songs to Queue" : "Add to Queue") {
                model.enqueue(songs, next: false)
            }
            Menu(multiple ? "Add \(songs.count) Songs to Playlist" : "Add to Playlist") {
                Button("Create a playlist…") {
                    editingPlaylist = nil
                    creatingPlaylistFrom = songs
                    showPlaylistName = true
                }
                if !model.playlists.isEmpty { Divider() }
                ForEach(model.playlists) { playlist in
                    Button(playlist.name) { model.addToPlaylist(songs, id: playlist.id) }
                        .disabled(songs.allSatisfy { playlist.trackIDs.contains($0.id) })
                }
            }
            if let playlist = model.selectedPlaylist {
                Button(multiple ? "Remove \(songs.count) Songs from Playlist" : "Remove from Playlist") {
                    model.removeFromPlaylist(songs, id: playlist.id)
                }
                if !multiple {
                    Button("Move up") { model.movePlaylistSong(track, by: -1) }.disabled(
                        playlist.trackIDs.first == track.id)
                    Button("Move down") { model.movePlaylistSong(track, by: 1) }.disabled(
                        playlist.trackIDs.last == track.id)
                }
            }
            if !multiple {
                Divider()
                Button("Details") { detailsTrack = track }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([track.url]) }
                Divider()
                Button(role: .destructive) { deletingSong = track } label: {
                    Text("Delete Song…").foregroundStyle(.red)
                }
                    .disabled(!model.canDeleteSong)
            }
        }
    }

    private func playbackIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: expandedNowPlaying ? 24 : 20))
            .frame(width: expandedNowPlaying ? 40 : 36, height: expandedNowPlaying ? 48 : 40)
            .contentShape(Rectangle())
    }

    private var playbackBar: some View {
        let layout = compact ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 20))
        return layout {
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
                            .font(.system(size: largerText ? 19 : 15, weight: .semibold)).lineLimit(1)
                            .help(model.current?.title ?? "Choose a song from your library")
                        Text(
                            model.current.map { $0.album.isEmpty ? $0.artist : "\($0.artist) · \($0.album)" }
                                ?? "Choose a song from your library"
                        )
                        .font(.system(size: largerText ? 15 : 12)).foregroundStyle(Palette.muted).lineLimit(1)
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
        }.padding(.horizontal, 20).padding(.vertical, 17).background(.regularMaterial)
            .contentShape(Rectangle())
            // A normal ancestor tap lets buttons and the slider consume their own input.
            .onTapGesture { if model.current != nil { expandedNowPlaying = true } }
            .accessibilityAction(named: "Expand now playing") {
                if model.current != nil { expandedNowPlaying = true }
            }
    }

    private var playbackProgress: some View { PlaybackProgress(model: model, clock: model.clock) }

    private var shuffleButton: some View {
        let isActive = model.queue.isShuffled
        let mode = model.queue.isShuffled ? "On" : "Off"
        let nextMode = model.queue.isShuffled ? "off" : "on"
        return Button(action: model.toggleShuffle) {
            Image(systemName: "shuffle")
                .font(.system(size: expandedNowPlaying ? 22 : 18, weight: .medium))
                .frame(width: expandedNowPlaying ? 52 : 48, height: expandedNowPlaying ? 48 : 40)
                .foregroundStyle(isActive ? Palette.playBlue : Palette.muted)
                .background(
                    isActive ? Palette.playBlue.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shuffle")
        .accessibilityValue(mode)
        .accessibilityHint("Turn shuffle \(nextMode)")
        .help("Shuffle: \(mode). Click to turn shuffle \(nextMode).")
        .disabled(model.current == nil)
    }

    private var playbackControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
            Spacer(minLength: 0)
            shuffleButton
            Spacer(minLength: 8)
            Button(action: model.previous) { playbackIcon("backward.end.fill") }
                .buttonStyle(.plain).disabled(model.current == nil).help("Previous · ⌘←").accessibilityLabel(
                    "Previous track")
            Spacer(minLength: 8)
            Button(action: model.togglePlayback) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: expandedNowPlaying ? 28 : 20, weight: .semibold)).offset(
                        x: model.isPlaying ? 0 : 1
                    )
                    .frame(width: expandedNowPlaying ? 72 : 56, height: expandedNowPlaying ? 72 : 56).foregroundStyle(
                        .white
                    )
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
            if expandedNowPlaying { nowPlayingBrowseMenu }
        }
    }

    private var nowPlayingBrowseMenu: some View {
        Menu {
            Button("Go to album") { browseCurrent(.albums) }
            Button("Go to artist") { browseCurrent(.artists) }
        } label: {
            Label("Browse song", systemImage: "ellipsis.circle")
        }.menuStyle(.borderlessButton).fixedSize().disabled(model.current == nil)
            .accessibilityLabel("Browse current song’s album or artist")
    }

    private func browseCurrent(_ destination: LibrarySection) {
        returningToPlayer = true
        expandedNowPlaying = false
        model.browseCurrent(destination)
    }

    private var compactExpandedPlayer: some View {
        VStack(spacing: 8) {
            Button {
                expandedNowPlaying = false
            } label: {
                Label("Back to library", systemImage: "chevron.down")
            }
            .keyboardShortcut(.escape, modifiers: [])
            LyricsView(model: model, clock: model.clock)
            playbackBar
        }.padding(12).background(Palette.paper)
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
                                Button {
                                    model.toggleFavorite(track)
                                } label: {
                                    playbackIcon(model.favoriteIDs.contains(track.id) ? "heart.fill" : "heart")
                                }.buttonStyle(.plain)
                                    .accessibilityLabel(
                                        model.favoriteIDs.contains(track.id)
                                            ? "Remove from favorites" : "Add to favorites")
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(track.artist).font(.system(size: 20)).lineLimit(1)
                                Text(
                                    [track.quality, track.bitRate == nil ? "" : track.bitRateLabel].filter {
                                        !$0.isEmpty
                                    }.joined(separator: " · ")
                                )
                                .font(.system(size: 12, design: .monospaced)).lineLimit(1)
                            }.foregroundStyle(.secondary)
                        }
                        playbackProgress
                        playbackControls
                    }.frame(width: columnWidth, height: geometry.size.height, alignment: .center)
                    LyricsView(model: model, clock: model.clock)
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
