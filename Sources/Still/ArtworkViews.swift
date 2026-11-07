import AppKit
import SwiftUI

private typealias ComponentState<Value> = SwiftUI.State<Value>

struct RecordArtwork: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.82))
                Circle().fill(Color(white: 0.18)).frame(width: size * 0.79, height: size * 0.79)
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 3, y: 7)
                ForEach(0..<8) { ring in
                    Circle().stroke(.white.opacity(0.065), lineWidth: 0.6)
                        .frame(
                            width: size * (0.39 + Double(ring) * 0.049), height: size * (0.39 + Double(ring) * 0.049))
                }
                Circle().fill(Color(white: 0.64)).frame(width: size * 0.28, height: size * 0.28)
                Circle().fill(Color(white: 0.18)).frame(width: size * 0.035, height: size * 0.035)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.accessibilityHidden(true)
    }
}

struct ArtworkThumbnail: View {
    let urls: [URL]
    let size: CGFloat
    var revision = 0
    var fallbackIcon = "music.note"
    @ComponentState private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Palette.sidebar
                    Image(systemName: fallbackIcon).font(.system(size: size * 0.4)).foregroundStyle(Palette.muted)
                }
            }
        }
        .frame(width: size, height: size).clipped().clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityHidden(true)
        .task(id: urls.map(\.path).joined(separator: "\u{0}") + String(revision)) {
            image = nil
            for url in urls {
                let loaded = await ArtworkStore.shared.image(for: url)
                guard !Task.isCancelled else { return }
                if let loaded {
                    image = loaded
                    return
                }
            }
        }
    }
}
