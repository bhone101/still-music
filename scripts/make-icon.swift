import AppKit

// Native artwork matching the supplied Still logo reference.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}
func render(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 184, yRadius: 184)
    NSGradient(starting: color(7, 8, 10), ending: color(27, 31, 43))!.draw(in: tile, angle: 90)
    color(40, 46, 59).setStroke()
    tile.lineWidth = 3
    tile.stroke()
    let blue = color(111, 147, 216)
    blue.setStroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: 367, y: 367, width: 290, height: 290))
    ring.lineWidth = 32
    ring.stroke()
    let bars = NSBezierPath()
    bars.lineWidth = 32
    bars.lineCapStyle = .round
    bars.move(to: NSPoint(x: 276, y: 512)); bars.line(to: NSPoint(x: 328, y: 512))
    bars.move(to: NSPoint(x: 696, y: 512)); bars.line(to: NSPoint(x: 748, y: 512))
    bars.stroke()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: 469, y: 469, width: 86, height: 86)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try render(pixels: size * scale).write(to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
// Source preview artwork is maintained separately; builds only write to destination.
