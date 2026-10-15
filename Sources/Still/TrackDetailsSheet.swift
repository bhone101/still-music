import StillCore
import SwiftUI

private typealias DetailsState<Value> = SwiftUI.State<Value>

struct TrackDetailsSheet: View {
    let track: Track
    @Environment(\.dismiss) private var dismiss
    @DetailsState private var details: TrackDetails?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details").font(.title2)
            Form {
                Section("Tags") {
                    row("Title", details?.taggedTitle)
                    row("Artist", details?.taggedArtist)
                    row("Album artist", track.albumArtist)
                    row("Album", track.album)
                    row("Genre", track.genre)
                    row("Composer", track.composer)
                    row("Track number", track.trackNumber.map(String.init))
                    row("Disc number", track.discNumber.map(String.init))
                    row("Date", details?.date)
                }
                Section("Audio") {
                    if track.sampleRate > 0 { row("Sample rate", "\(Int(track.sampleRate)) Hz") }
                    if track.bitDepth > 0 { row("Bit depth", "\(track.bitDepth)-bit") }
                    row("Channels", details?.channels.map(String.init))
                    if track.duration > 0 { row("Duration", String(format: "%.3f seconds", track.duration)) }
                    if let rate = track.bitRate, rate > 0 { row("Average bit rate", track.bitRateLabel) }
                    row("Format", track.codec)
                }
                Section("File") {
                    if let size = details?.fileSize {
                        row("File size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    }
                    row("File path", track.url.path)
                }
            }.formStyle(.grouped).textSelection(.enabled)
            HStack {
                if details == nil { ProgressView().controlSize(.small) }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(20).frame(width: 560, height: 620)
            .task {
                let track = track
                let result = await Task.detached(priority: .userInitiated) { await TrackDetails.read(for: track) }.value
                if !Task.isCancelled { details = result }
            }
    }

    @ViewBuilder private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            LabeledContent(label) { Text(value).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
