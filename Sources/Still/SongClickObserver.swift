import AppKit
import SwiftUI

// Observe the click without claiming SwiftUI's gesture arena, so NSTableView
// retains its standard Command/Shift selection behavior.
struct SongClickObserver: NSViewRepresentable {
    var clicked: () -> Void
    var secondaryClicked: () -> Void
    func makeNSView(context: Context) -> ClickView { ClickView(clicked: clicked, secondaryClicked: secondaryClicked) }
    func updateNSView(_ view: ClickView, context: Context) {
        view.clicked = clicked
        view.secondaryClicked = secondaryClicked
    }
    final class ClickView: NSView {
        var clicked: () -> Void
        var secondaryClicked: () -> Void
        private var monitor: Any?
        init(clicked: @escaping () -> Void, secondaryClicked: @escaping () -> Void) {
            self.clicked = clicked
            self.secondaryClicked = secondaryClicked
            super.init(frame: .zero)
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
                [weak self] event in
                if let self, self.window != nil, event.window === self.window,
                    self.bounds.contains(self.convert(event.locationInWindow, from: nil))
                {
                    self.clicked()
                    if event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
                        self.secondaryClicked()
                    }
                }
                return event
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
