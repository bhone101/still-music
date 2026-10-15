import AppKit
import SwiftUI

@main
struct StillMusicApp: App {
    @NSApplicationDelegateAdaptor(StillMusicAppDelegate.self) private var appDelegate
    @StateObject private var model = PlayerModel()

    var body: some Scene {
        Window("Still Music", id: "main") {
            ContentView(model: model)
                .onAppear { appDelegate.model = model }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.rescanFoldersIfNeeded() }
                .onOpenURL { model.add([$0]) }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.save() }
        }
        .defaultSize(width: 1120, height: 720)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Music…") { model.chooseFiles() }.keyboardShortcut("o")
                    .disabled(model.importing)
                Button("Refresh Song Metadata") { model.refreshMetadata() }
                    .disabled(model.refreshing || model.tracks.isEmpty)
            }
            CommandMenu("Playback") {
                Button(model.isPlaying ? "Pause" : "Play") { model.togglePlayback() }
                    .keyboardShortcut(.space, modifiers: []).disabled(model.tracks.isEmpty)
                Button("Next Track") { model.next() }.keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(!model.hasNext)
                Button("Previous Track") { model.previous() }.keyboardShortcut(.leftArrow, modifiers: .command)
                    .disabled(model.tracks.isEmpty)
            }
        }
    }
}

@MainActor
final class StillMusicAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: PlayerModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load the bundled artwork directly, including after in-place development updates.
        if let url = Bundle.main.url(forResource: "StillRing", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        Task {
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
