import SwiftUI
import Combine
import StillCore

private typealias QueueState<Value> = SwiftUI.State<Value>

struct QueueView: View {
    let model: PlayerModel
    @StateObject private var presentation: QueuePresentation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: PlayerModel) {
        self.model = model
        _presentation = StateObject(wrappedValue: QueuePresentation(model: model))
    }

    private func edit(_ action: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12), action)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Queue").font(.headline)
                Spacer()
                Button("Close") { withoutQueueAnimation { dismiss() } }
            }
            if let current = presentation.snapshot.current {
                Text("Now playing").font(.caption).foregroundStyle(.secondary)
                Text(current.title).lineLimit(1)
                Text(current.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Divider()
            }
            HStack {
                Text("Up next").font(.headline)
                Spacer()
                Button("Clear All") { edit { model.clearQueue() } }
                    .disabled(presentation.snapshot.rows.isEmpty && !presentation.snapshot.isLooping)
            }
            if presentation.snapshot.isLooping { Text("The queue repeats after the last song.").font(.caption).foregroundStyle(.secondary) }
            if presentation.snapshot.rows.isEmpty {
                Text("No songs queued").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                        ForEach(presentation.snapshot.rows) { row in
                            let track = row.track
                              HStack(spacing: 10) {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.tertiary).accessibilityHidden(true)
                                Button { model.playQueueEntry(row.id) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(track.title).lineLimit(1)
                                        Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Button { edit { model.removeQueueEntry(row.id) } } label: {
                                    Image(systemName: "minus").frame(width: 28, height: 28)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .help("Remove from queue")
                                    .accessibilityLabel("Remove \(track.title) from queue")
                              }.padding(.vertical, 4)
                                .listRowBackground(Color.clear)
                        }
                        .onMove { offsets, destination in
                            edit { model.moveQueueEntries(from: offsets, to: destination) }
                        }
                }.listStyle(.plain)
                    .scrollContentBackground(.hidden)
            }
        }.padding(20).frame(width: 420, height: 520)
            .background(Color(nsColor: .windowBackgroundColor))
            .presentationBackground(Color(nsColor: .windowBackgroundColor))
    }
}

// Each player owns its presentation; the compact player remains underneath the expanded one.
struct QueueButton: View {
    let model: PlayerModel
    let expanded: Bool
    @QueueState private var showingQueue = false

    var body: some View {
        Button { withoutQueueAnimation { showingQueue.toggle() } } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: expanded ? 24 : 20))
                .frame(width: expanded ? 40 : 36, height: expanded ? 48 : 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Queue")
        .popover(isPresented: $showingQueue) { QueueView(model: model) }
    }
}

// Observe only queue/metadata changes, not the player's four-times-a-second clock.
@MainActor private final class QueuePresentation: ObservableObject {
    struct Row: Identifiable, Equatable {
        let id: UUID
        let track: Track
    }
    struct Snapshot: Equatable {
        var current: Track?
        var rows: [Row] = []
        var isLooping = false
    }
    @Published private(set) var snapshot = Snapshot()
    private var subscription: AnyCancellable?

    init(model: PlayerModel) {
        subscription = Publishers.CombineLatest3(model.$tracks, model.$queue, model.$currentID)
            .map { tracks, queue, currentID in
                let index = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                return Snapshot(current: currentID.flatMap { index[$0] }, rows: queue.upcoming.compactMap { entry in
                    index[entry.trackID].map { Row(id: entry.id, track: $0) }
                }, isLooping: queue.isLooping)
            }
            .removeDuplicates()
            .sink { [weak self] in self?.snapshot = $0 }
    }
}

private func withoutQueueAnimation(_ action: () -> Void) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction, action)
}
