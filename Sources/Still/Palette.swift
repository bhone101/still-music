import AppKit
import SwiftUI

enum Palette {
    private static func adaptive(_ light: NSColor, _ dark: NSColor, contrastLight: NSColor? = nil, contrastDark: NSColor? = nil) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [.accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua, .darkAqua, .aqua])
                let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
                let color = isDark ? dark : light
                guard match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua else { return color }
                if let override = isDark ? contrastDark : contrastLight { return override }
                // Increase separation of neutral text and background shades.
                let value = color.usingColorSpace(.deviceRGB)?.redComponent ?? 0.5
                let stronger = value < 0.5 ? max(0, value - 0.12) : min(1, value + 0.12)
                return NSColor(white: stronger, alpha: 1)
            })
    }
    static let paper = adaptive(NSColor(white: 0.98, alpha: 1), .black)
    static let sidebar = adaptive(NSColor(white: 0.94, alpha: 1), NSColor(white: 0.09, alpha: 1))
    static let surface = adaptive(.white, NSColor(white: 0.075, alpha: 1))
    static let ink = adaptive(NSColor(white: 0.12, alpha: 1), NSColor(white: 0.94, alpha: 1))
    static let muted = adaptive(NSColor(white: 0.43, alpha: 1), NSColor(white: 0.60, alpha: 1))
    static let accent = adaptive(NSColor(white: 0.30, alpha: 1), NSColor(white: 0.82, alpha: 1))
    static let selected = adaptive(NSColor(white: 0.86, alpha: 1), NSColor(white: 0.22, alpha: 1),
        contrastLight: NSColor(white: 0.70, alpha: 1), contrastDark: NSColor(white: 0.36, alpha: 1))
    static let line = adaptive(NSColor(white: 0.88, alpha: 1), NSColor(white: 0.16, alpha: 1),
        contrastLight: NSColor(white: 0.55, alpha: 1), contrastDark: NSColor(white: 0.45, alpha: 1))
    static let playBlue = Color(.sRGB, red: 58 / 255, green: 107 / 255, blue: 169 / 255)
}
