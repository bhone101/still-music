import AppKit
import SwiftUI
import StillCore

private typealias SheetState<Value> = SwiftUI.State<Value>

struct ArtworkSearchSheet: View {
    @ObservedObject var model: PlayerModel
    let track: Track
    @Environment(\.dismiss) private var dismiss
    @SheetState private var query = ""
    @SheetState private var results: [CoverSearch.Release] = []
    @SheetState private var busy = false
    @SheetState private var status = ""
    @SheetState private var selected: Data?
    @SheetState private var task: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Find Album Cover").font(.title2)
            Text(
                "Search sends this text to MusicBrainz. Previews load from Cover Art Archive. Your audio files are never uploaded."
            ).font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("Album and artist", text: $query).textFieldStyle(.roundedBorder)
                Button("Search") {
                    busy = true
                    selected = nil
                    status = ""
                    results = []
                    task = Task {
                        defer { busy = false }
                        do {
                            let found = try await CoverSearch.shared.search(query)
                            try Task.checkCancellation()
                            results = found
                            if found.isEmpty { status = "No releases found. Try another album or artist name." }
                        } catch { if !Task.isCancelled { status = "Search unavailable. Try again later." } }
                    }
                }.disabled(busy || query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))]) {
                    ForEach(results) { release in
                        Button {
                            guard let url = release.imageURL else { return }
                            busy = true
                            selected = nil
                            status = ""
                            task = Task {
                                defer { busy = false }
                                do {
                                    let data = try await CoverSearch.fetch(url)
                                    try Task.checkCancellation()
                                    guard NSImage(data: data) != nil else { throw URLError(.cannotDecodeContentData) }
                                    selected = data
                                } catch { if !Task.isCancelled { status = "No cover available for this release." } }
                            }
                        } label: {
                            VStack {
                                AsyncImage(url: release.imageURL) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Image(systemName: "opticaldisc").font(.largeTitle)
                                }.frame(height: 100)
                                Text(release.title).lineLimit(2)
                                Text([release.date, release.country].compactMap { $0 }.joined(separator: " · ")).font(
                                    .caption)
                            }.frame(maxWidth: .infinity).padding(8)
                        }.buttonStyle(.plain).disabled(busy)
                    }
                }
            }.frame(height: 260)
            if let selected, let image = NSImage(data: selected) {
                HStack {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 72, height: 72)
                    Text(
                        model.writeCoversIntoFiles
                            ? "Apply to this album and write to its supported audio files."
                            : "Apply to this album in Still Music. Enable cover writing in Settings to embed it into files."
                    ).font(.callout)
                }
            }
            if !status.isEmpty { Text(status).foregroundStyle(.secondary) }
            HStack {
                if busy || model.savingCover { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") {
                    task?.cancel()
                    dismiss()
                }.keyboardShortcut(.cancelAction)
                Button("Use Selected Cover") {
                    guard let selected else { return }
                    task = Task {
                        await model.applySelectedCover(selected, for: track)
                        dismiss()
                    }
                }.disabled(selected == nil || busy || model.savingCover || model.editingMetadata || model.savingLyrics)
            }
        }.padding(24).frame(width: 620)
            .onAppear { query = "\(track.album) \(track.displayAlbumArtist)" }
            .onDisappear { task?.cancel() }
            .interactiveDismissDisabled(model.savingCover)
    }
}
