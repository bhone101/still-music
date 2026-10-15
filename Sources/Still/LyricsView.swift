import AppKit
import SwiftUI

private typealias LyricsState<Value> = SwiftUI.State<Value>

struct LyricsView: View {
    @ObservedObject var model: PlayerModel
    @LyricsState private var following = true
    private var currentLine: Int? { model.lyrics.currentLine(at: model.position) }

    private var lyricsHeader: some View {
        LyricsActionsLayout() {
            Button { model.findCurrentLyricsOnline() } label: {
                Label("Find online", systemImage: "magnifyingglass")
                    .padding(.horizontal, 10).frame(height: 36).contentShape(Rectangle())
            }
            .disabled(model.current == nil || model.loadingLyrics || model.savingLyrics || model.uploadingLyrics)
            .help("Search LRCLIB using this song’s title and artist")
            Button { model.uploadLyrics() } label: {
                Label("Import lyrics", systemImage: "square.and.arrow.up")
                    .padding(.horizontal, 10).frame(height: 36).contentShape(Rectangle())
            }
            .disabled(model.current == nil || model.uploadingLyrics || model.savingLyrics)
            .help("Choose a local .lrc or .txt file for this song")
            Button { model.writeLyricsToFile() } label: {
                Label("Write lyrics to file", systemImage: "square.and.arrow.down")
                    .padding(.horizontal, 10).frame(height: 36).contentShape(Rectangle())
            }
            .disabled(!model.canWriteEmbeddedLyrics || model.lyrics.isEmpty || model.savingLyrics || model.loadingLyrics || model.uploadingLyrics || model.savingCover)
            .help("Replace embedded lyrics in this FLAC, MP3 or M4A file")
            Button {
                if model.hasUnsavedLyrics { model.discardLyricsChanges() }
                else { model.deleteLyrics() }
            } label: {
                Label(model.hasUnsavedLyrics ? "Discard changes" : "Delete lyrics",
                      systemImage: model.hasUnsavedLyrics ? "arrow.uturn.backward" : "trash")
                    .padding(.horizontal, 10).frame(height: 36).contentShape(Rectangle())
            }
            .disabled(model.loadingLyrics || model.savingLyrics || model.uploadingLyrics ||
                      (!model.hasUnsavedLyrics && (!model.canWriteEmbeddedLyrics || !model.canDeleteLyrics || model.savingCover)))
            .help(model.hasUnsavedLyrics
                  ? "Remove the app draft without changing the audio or sidecar files"
                  : "Remove embedded lyrics and clear this song’s lyrics in Still Music")
        }.font(.system(size: 14)).buttonStyle(.plain)
            .labelStyle(.titleAndIcon)
            .textSelection(.disabled)
            .onContinuousHover { phase in
                if case .active = phase { NSCursor.arrow.set() }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            lyricsHeader
            if model.hasUnsavedLyrics {
                Text("Unsaved changes").font(.system(size: 12)).foregroundStyle(.secondary)
                    .help("These lyrics are saved in Still Music, but have not been written into the song")
            }
            if model.loadingLyrics {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.lyrics.isEmpty {
                Text("No lyrics found").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.lyrics.lines.isEmpty {
                ScrollView { Text(model.lyrics.plainText).font(.system(size: 28)).lineSpacing(10).multilineTextAlignment(.leading).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            } else {
                ScrollViewReader { proxy in
                    GeometryReader { geometry in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 28) {
                                ForEach(model.lyrics.lines.indices, id: \.self) { index in
                                    let line = model.lyrics.lines[index]
                                    Button { model.seek(to: line.time); following = true } label: {
                                        Text(line.text.isEmpty ? " " : line.text)
                                            .font(.system(size: index == currentLine ? 40 : 28, weight: index == currentLine ? .bold : .medium))
                                            .multilineTextAlignment(.leading)
                                            .lineSpacing(8)
                                            .foregroundStyle(index == currentLine ? Color.primary : Color.secondary.opacity(0.65))
                                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }.buttonStyle(.plain).id(index)
                                }
                            }.padding(.vertical, geometry.size.height / 2)
                        }
                        .background(LyricsScrollObserver { following = false })
                        .simultaneousGesture(DragGesture(minimumDistance: 3).onChanged { _ in following = false })
                        .onChange(of: currentLine) { _, index in
                            if following, let index { withAnimation { proxy.scrollTo(index, anchor: .center) } }
                        }
                        .onChange(of: following) { _, value in
                            if value, let currentLine { withAnimation { proxy.scrollTo(currentLine, anchor: .center) } }
                        }
                        .onAppear { if let currentLine { proxy.scrollTo(currentLine, anchor: .center) } }
                    }
                }
                HStack {
                    if !following { Button("Resume following") { following = true } }
                    Spacer()

                }
            }
        }.padding(.top, 8).frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if model.savedLyricsTrackID != nil && model.savedLyricsTrackID == model.currentID {
                    Label("Lyrics written to file", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                        .padding(.bottom, 16)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.savedLyricsTrackID)
            .onChange(of: model.currentID) { _, _ in following = true }
    }
}

/// Observe only real user input within the lyrics area, never programmatic scrolling.
private struct LyricsScrollObserver: NSViewRepresentable {
    let onScroll: () -> Void
    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ view: ObserverView, context: Context) { view.onScroll = onScroll }
    final class ObserverView: NSView {
        var onScroll: (() -> Void)?
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDragged, .keyDown]) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                if event.type == .keyDown {
                    if [UInt16(116), 121, 125, 126].contains(event.keyCode), self.window?.firstResponder is NSView { self.onScroll?() }
                } else if self.bounds.contains(self.convert(event.locationInWindow, from: nil)) { self.onScroll?() }
                return event
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// Keep action names visible at every width, wrapping whole buttons when needed.
private struct LyricsActionsLayout: Layout {
    private let horizontalSpacing: CGFloat = 12
    private let verticalSpacing: CGFloat = 4

    private func arrangement(width: CGFloat?, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let finiteWidth = width.flatMap { $0.isFinite ? max(0, $0) : nil }
        let availableWidth = finiteWidth ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > availableWidth {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            contentWidth = max(contentWidth, x + size.width)
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: finiteWidth ?? contentWidth, height: y + rowHeight), origins)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = arrangement(width: bounds.width, subviews: subviews).origins
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + positions[index].x, y: bounds.minY + positions[index].y),
                          anchor: .topLeading, proposal: .unspecified)
        }
    }
}
