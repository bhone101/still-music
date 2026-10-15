import StillCore
import SwiftUI

private typealias PlaylistState<Value> = SwiftUI.State<Value>

struct PlaylistNameSheet: View {
    @ObservedObject var model: PlayerModel
    let playlist: MusicPlaylist?
    let track: Track?
    @Environment(\.dismiss) private var dismiss
    @PlaylistState private var name = ""
    @PlaylistState private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(playlist == nil ? "Create a playlist" : "Rename playlist").font(.title2.weight(.semibold))
            TextField("Playlist name", text: $name).textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit(save)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(playlist == nil ? "Create" : "Save", action: save).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 360)
            .onAppear { name = playlist?.name ?? ""; focused = true }
    }
    private func save() {
        do { try model.editPlaylistName(name, id: playlist?.id, adding: track); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct PlaylistSongsSheet: View {
    @ObservedObject var model: PlayerModel
    let playlist: MusicPlaylist
    @Environment(\.dismiss) private var dismiss
    @PlaylistState private var selected: Set<String> = []
    @PlaylistState private var search = ""
    @PlaylistState private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Songs in \(playlist.name)").font(.title2.weight(.semibold)).lineLimit(1)
            TextField("Find songs", text: $search).textFieldStyle(.roundedBorder)
            List(model.tracks.filter { search.isEmpty || "\($0.title) \($0.artist) \($0.album)".localizedCaseInsensitiveContains(search) }) { track in
                Toggle(isOn: Binding(get: { selected.contains(track.id) }, set: { if $0 { selected.insert(track.id) } else { selected.remove(track.id) } })) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title).lineLimit(1)
                        Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.toggleStyle(.checkbox).padding(.vertical, 3)
            }
            if model.tracks.isEmpty { Text("Add music to your library first.").foregroundStyle(.secondary) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Text(songCountLabel(selected.count)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Done") {
                    do { try model.updatePlaylistSongs(playlist.id, selected: selected); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 480, height: 480)
            .onAppear { selected = Set(playlist.trackIDs) }
    }
}
