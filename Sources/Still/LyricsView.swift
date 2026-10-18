import AppKit
import SwiftUI

private typealias LyricsState<Value> = SwiftUI.State<Value>

struct LyricsView: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LyricsState private var following = true
    private var currentLine: Int? { model.lyrics.currentLine(at: model.position) }

    private var lyricsHeader: some View {
        Menu {
            Button { model.findCurrentLyricsOnline() } label: {
                Label("Find online", systemImage: "magnifyingglass")
            }
            .disabled(model.current == nil || model.loadingLyrics || model.savingLyrics || model.uploadingLyrics)
            .help("Search LRCLIB using this song’s title and artist")
            Button { model.uploadLyrics() } label: {
                Label("Import lyrics", systemImage: "square.and.arrow.up")
            }
            .disabled(model.current == nil || model.uploadingLyrics || model.savingLyrics)
            .help("Choose a local .lrc or .txt file for this song")
            Button { model.writeLyricsToFile() } label: {
                Label("Write lyrics to file", systemImage: "square.and.arrow.down")
            }
            .disabled(!model.canWriteEmbeddedLyrics || model.lyrics.isEmpty || model.savingLyrics || model.loadingLyrics || model.uploadingLyrics || model.savingCover)
            .help("Replace embedded lyrics in this FLAC, MP3 or M4A file")
            Button {
                if model.hasUnsavedLyrics { model.discardLyricsChanges() }
                else { model.deleteLyrics() }
            } label: {
                Label(model.hasUnsavedLyrics ? "Discard changes" : "Delete lyrics",
                      systemImage: model.hasUnsavedLyrics ? "arrow.uturn.backward" : "trash")
            }
            .disabled(model.loadingLyrics || model.savingLyrics || model.uploadingLyrics ||
                      (!model.hasUnsavedLyrics && (!model.canWriteEmbeddedLyrics || !model.canDeleteLyrics || model.savingCover)))
            .help(model.hasUnsavedLyrics
                  ? "Remove the app draft without changing the audio or sidecar files"
                  : "Remove embedded lyrics and clear this song’s lyrics in Still Music")
        } label: {
            Text("Lyrics actions")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .controlSize(.small)
        .font(.system(size: 13))
        .labelStyle(.titleAndIcon)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Find, import, write or remove lyrics for this song")
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
                ScrollView { Text(model.lyrics.plainText).font(.system(size: 28)).lineSpacing(10).multilineTextAlignment(.center).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .center) }
            } else {
                ScrollViewReader { proxy in
                    GeometryReader { geometry in
                        ScrollView {
                            LazyVStack(alignment: .center, spacing: 28) {
                                ForEach(model.lyrics.lines.indices, id: \.self) { index in
                                    let line = model.lyrics.lines[index]
                                    Button { model.seek(to: line.time); following = true } label: {
                                        Text(line.text.isEmpty ? " " : line.text)
                                            // Keep wrapping and row heights stable as the highlighted line changes.
                                            .font(.system(size: 34, weight: .semibold))
                                            .multilineTextAlignment(.center)
                                            .lineSpacing(8)
                                            .foregroundStyle(index == currentLine ? Color.primary : Color.secondary.opacity(0.65))
                                            .frame(maxWidth: .infinity, alignment: .center)
                                            .scaleEffect(index == currentLine || reduceMotion ? 1 : 0.94)
                                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: index == currentLine)
                                            .contentShape(Rectangle())
                                    }.buttonStyle(.plain).id(index)
                                }
                            }.padding(.vertical, geometry.size.height / 2)
                        }
                        .background(LyricsScrollObserver { following = false })
                        .simultaneousGesture(DragGesture(minimumDistance: 3).onChanged { _ in following = false })
                        .onChange(of: currentLine) { _, index in
                            if following, let index {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
                                    proxy.scrollTo(index, anchor: .center)
                                }
                            }
                        }
                        .onChange(of: following) { _, value in
                            if value, let currentLine {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
                                    proxy.scrollTo(currentLine, anchor: .center)
                                }
                            }
                        }
                        .onAppear { if let currentLine { proxy.scrollTo(currentLine, anchor: .center) } }
                    }
                }
                HStack {
                    if !following { Button("Resume following") { following = true } }
                    Spacer()
                }.frame(height: 28)
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
