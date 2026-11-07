import SwiftUI
import StillCore

private typealias SheetState<Value> = SwiftUI.State<Value>

struct MetadataEditor: View {
    @ObservedObject var model: PlayerModel
    let songs: [Track]
    @ObservedObject var progress: MetadataProgress
    @Environment(\.dismiss) private var dismiss
    @SheetState private var values: [String: String] = [:]
    @SheetState private var applied: Set<String> = []
    @SheetState private var saving = false
    @SheetState private var confirm = false
    @SheetState private var error: String?
    private let labels = [
        "TITLE": "Title", "ARTIST": "Artist", "ALBUM": "Album", "ALBUMARTIST": "Album artist", "TRACKNUMBER": "Track",
        "DISCNUMBER": "Disc", "GENRE": "Genre", "DATE": "Year", "COMPOSER": "Composer",
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Song Info").font(.title2)
            Text(songs.count == 1 ? songs[0].title : "\(songs.count) selected songs")
                .foregroundStyle(.secondary).lineLimit(2)
            Text("Only checked fields will change. A checked empty field removes that tag.").font(.callout)
                .foregroundStyle(.secondary)
            ScrollView {
                Grid(alignment: .leading) {
                    ForEach(FileMetadata.fields, id: \.self) { key in
                        GridRow {
                            Toggle(
                                labels[key] ?? key,
                                isOn: Binding(
                                    get: { applied.contains(key) },
                                    set: { if $0 { applied.insert(key) } else { applied.remove(key) } })
                            ).frame(width: 130, alignment: .leading)
                            TextField(
                                "Unchanged",
                                text: Binding(
                                    get: { values[key] ?? "" },
                                    set: {
                                        if $0 != (values[key] ?? "") {
                                            values[key] = $0
                                            applied.insert(key)
                                        }
                                    })
                            ).textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }.frame(maxHeight: 240)
                .disabled(saving)
            if let error {
                ScrollView {
                    Text(error).foregroundStyle(progress.failureCount > 0 ? Color.red : Color.secondary).textSelection(
                        .enabled)
                }.frame(maxHeight: 90)
            }
            HStack {
                if saving {
                    ProgressView(value: Double(progress.completed), total: Double(max(1, progress.total))).frame(
                        width: 90)
                    Text(
                        progress.cancellationRequested
                            ? "Finishing current song…"
                            : "Updating \(min(progress.completed + 1, progress.total)) of \(progress.total) songs")
                }
                Spacer()
                if saving {
                    Button("Cancel Update") { model.cancelMetadataUpdate() }
                        .disabled(progress.cancellationRequested).keyboardShortcut(.cancelAction)
                } else {
                    Button(error == nil ? "Cancel" : "Done") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Review Changes…") { confirm = true }.disabled(applied.isEmpty || songs.isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }.padding(24).frame(width: 550).frame(maxHeight: 440).interactiveDismissDisabled(saving)
            .onAppear {
                if songs.count == 1, let song = songs.first {
                    values = [
                        "TITLE": song.title, "ARTIST": song.artist, "ALBUM": song.album,
                        "ALBUMARTIST": song.albumArtist ?? "", "GENRE": song.genre ?? "",
                        "COMPOSER": song.composer ?? "", "TRACKNUMBER": song.trackNumber.map(String.init) ?? "",
                        "DISCNUMBER": song.discNumber.map(String.init) ?? "", "DATE": song.year.map(String.init) ?? "",
                    ]
                }
            }
            .confirmationDialog("Write changes into \(songs.count) audio file(s)?", isPresented: $confirm) {
                Button("Write Changes") {
                    saving = true
                    let fields = Dictionary(uniqueKeysWithValues: applied.map { ($0, values[$0] ?? "") })
                    Task {
                        error = await model.writeSongInfo(fields, songs: songs)
                        saving = false
                        if error == nil { dismiss() }
                    }
                }
            } message: {
                Text(
                    applied.sorted().map {
                        "\(labels[$0] ?? $0): \(values[$0].flatMap { $0.isEmpty ? nil : $0 } ?? "(remove)")"
                    }.joined(separator: "\n"))
            }
    }
}
