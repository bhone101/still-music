import AppKit
import SwiftUI

// Full-screen title bars can expose the NSWindow backing color even when
// SwiftUI supplies a toolbar background. Keep both surfaces in the same theme.
struct WindowBackground: NSViewRepresentable {
    let isDark: Bool

    func makeNSView(context: Context) -> BackgroundView { BackgroundView() }
    func updateNSView(_ view: BackgroundView, context: Context) {
        view.color = isDark ? .black : NSColor(white: 0.98, alpha: 1)
        view.apply()
    }

    final class BackgroundView: NSView {
        var color: NSColor = .black
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }
        func apply() {
            window?.backgroundColor = color
            window?.titlebarAppearsTransparent = true
            window?.toolbar?.showsBaselineSeparator = false
        }
    }
}
