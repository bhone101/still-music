import AppKit
import StillCore
import SwiftUI

private typealias ComponentState<Value> = SwiftUI.State<Value>

struct PlaybackProgress: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var clock: PlaybackClock
    @ComponentState private var scrubbing = false
    @ComponentState private var scrubPosition: Double = 0
    var body: some View {
        HStack(spacing: 8) {
            Text(timeLabel(scrubbing ? scrubPosition : clock.position)).frame(width: 36, alignment: .leading)
            Slider(
                value: Binding(
                    get: { scrubbing ? scrubPosition : clock.position },
                    set: {
                        scrubPosition = $0
                        if !scrubbing { model.seek(to: $0) }
                    }),
                in: 0...max(model.current?.duration ?? 1, 1),
                onEditingChanged: { editing in
                    if editing {
                        scrubPosition = clock.position
                        scrubbing = true
                    } else {
                        model.seek(to: scrubPosition)
                        scrubbing = false
                    }
                }
            )
            .controlSize(.mini).disabled(model.current == nil).accessibilityLabel("Playback position")
            Text(
                model.current == nil
                    ? "0:00"
                    : "−"
                        + timeLabel(
                            max(0, (model.current?.duration ?? 0) - (scrubbing ? scrubPosition : clock.position)))
            )
            .frame(width: 42, alignment: .trailing).accessibilityLabel("Time remaining")
        }.font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
    }
}
