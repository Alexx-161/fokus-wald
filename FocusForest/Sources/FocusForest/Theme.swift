import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }

    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

struct AppTheme: Identifiable {
    enum Particles { case none, stars, snow, petals }

    let id: String
    let name: String
    /// nil follows the system light/dark setting.
    let scheme: ColorScheme?
    let bg: Color, card: Color, track: Color, ink: Color, muted: Color
    let skyTop: Color, skyBottom: Color, cloud: Color
    let grass: Color, grassDark: Color, earth: Color, earthDark: Color, pebble: Color
    let particles: Particles

    static let all: [AppTheme] = [
        AppTheme(id: "wiese", name: "Wiese", scheme: nil,
                 bg: Color(light: 0xFBF7F0, dark: 0x1D1E1B), card: Color(light: 0xFFFFFF, dark: 0x282A26),
                 track: Color(light: 0xEFE8DC, dark: 0x363832), ink: Color(light: 0x3E3A34, dark: 0xEEE9E0),
                 muted: Color(light: 0x948C80, dark: 0x9C978E),
                 skyTop: Color(light: 0xCFE8FA, dark: 0x1E2A44), skyBottom: Color(light: 0xFFF1E3, dark: 0x3A3350),
                 cloud: Color(light: 0xFFFFFF, dark: 0x5A5878),
                 grass: Color(hex: 0xA7DB9B), grassDark: Color(hex: 0x86C47C), earth: Color(hex: 0xC99A6E),
                 earthDark: Color(hex: 0x9C7050), pebble: Color(hex: 0xD8B48E), particles: .none),
        AppTheme(id: "mitternacht", name: "Mitternacht", scheme: .dark,
                 bg: Color(hex: 0x1B2033), card: Color(hex: 0x252B42), track: Color(hex: 0x333B59),
                 ink: Color(hex: 0xECEAF8), muted: Color(hex: 0x9C9AB8),
                 skyTop: Color(hex: 0x0E1430), skyBottom: Color(hex: 0x2E2754), cloud: Color(hex: 0x3C3F6A),
                 grass: Color(hex: 0x74B394), grassDark: Color(hex: 0x58977B), earth: Color(hex: 0x86607A),
                 earthDark: Color(hex: 0x5C4058), pebble: Color(hex: 0x9C7A92), particles: .stars),
        AppTheme(id: "sakura", name: "Kirschblüte", scheme: .light,
                 bg: Color(hex: 0xFFF4F6), card: Color(hex: 0xFFFFFF), track: Color(hex: 0xF9DFE6),
                 ink: Color(hex: 0x5A3A44), muted: Color(hex: 0xB08A96),
                 skyTop: Color(hex: 0xFFD6E2), skyBottom: Color(hex: 0xFFF3E8), cloud: Color(hex: 0xFFFFFF),
                 grass: Color(hex: 0xB8E2A6), grassDark: Color(hex: 0x98CE8A), earth: Color(hex: 0xD3A07E),
                 earthDark: Color(hex: 0xAE7A5C), pebble: Color(hex: 0xF0C6C6), particles: .petals),
        AppTheme(id: "herbst", name: "Herbst", scheme: .light,
                 bg: Color(hex: 0xFBF1E6), card: Color(hex: 0xFFFAF3), track: Color(hex: 0xF1DEC6),
                 ink: Color(hex: 0x4E3B2C), muted: Color(hex: 0xA68B72),
                 skyTop: Color(hex: 0xFFD3A0), skyBottom: Color(hex: 0xFFF1DE), cloud: Color(hex: 0xFFF8EE),
                 grass: Color(hex: 0xD8C67A), grassDark: Color(hex: 0xBFAA5C), earth: Color(hex: 0xB98A5E),
                 earthDark: Color(hex: 0x8C6442), pebble: Color(hex: 0xD9B48A), particles: .none),
        AppTheme(id: "winter", name: "Winter", scheme: .light,
                 bg: Color(hex: 0xF2F6FA), card: Color(hex: 0xFFFFFF), track: Color(hex: 0xDDE7F0),
                 ink: Color(hex: 0x34404D), muted: Color(hex: 0x8B98A6),
                 skyTop: Color(hex: 0xC9DCF0), skyBottom: Color(hex: 0xF3F7FC), cloud: Color(hex: 0xFFFFFF),
                 grass: Color(hex: 0xF5F9FC), grassDark: Color(hex: 0xD3E0EB), earth: Color(hex: 0x9EAABA),
                 earthDark: Color(hex: 0x737F90), pebble: Color(hex: 0xC2CCD8), particles: .snow),
    ]

    /// Set by `Preferences`; views re-render on theme change because the main view is re-identified.
    static var current = all[0]

    static func find(_ id: String) -> AppTheme { all.first { $0.id == id } ?? all[0] }
}

enum Theme {
    static var bg: Color { AppTheme.current.bg }
    static var card: Color { AppTheme.current.card }
    static var track: Color { AppTheme.current.track }
    static var ink: Color { AppTheme.current.ink }
    static var muted: Color { AppTheme.current.muted }
}

enum Palette {
    static let trunk = Color(hex: 0xB07F5F)
    static let trunkLight = Color(hex: 0xC99878)
    static let crystalTrunk = Color(hex: 0xA9B1C4)
    static let soil = Color(hex: 0xC9A27E)
    static let soilLight = Color(hex: 0xDABA97)
    static let sprout = Color(hex: 0x8ED68F)
    static let stem = Color(hex: 0x5FAF6A)
    static let leaf = Color(hex: 0x7CC48A)
    static let mushroomStem = Color(hex: 0xF7EEDD)
    static let gills = Color(hex: 0xE6D3B3)
    static let face = Color(hex: 0x4A3F38)
    static let blush = Color(hex: 0xF48FA8)
    static let star = Color(hex: 0xFFD66B)

    static var skyTop: Color { AppTheme.current.skyTop }
    static var skyBottom: Color { AppTheme.current.skyBottom }
    static var cloud: Color { AppTheme.current.cloud }
    static var grass: Color { AppTheme.current.grass }
    static var grassDark: Color { AppTheme.current.grassDark }
    static var earth: Color { AppTheme.current.earth }
    static var earthDark: Color { AppTheme.current.earthDark }
    static var pebble: Color { AppTheme.current.pebble }

    static let river = Color(hex: 0x8CCBEF)
    static let riverLight = Color(hex: 0xC4E6FA)
    static let pathEdge = Color(hex: 0xD2B07E)
    static let path = Color(hex: 0xE6CB9C)
    static let pathStone = Color(hex: 0xF4E2C0)
    static let wood = Color(hex: 0xC08A5B)
    static let woodDark = Color(hex: 0x8E6240)
    static let flag = Color(hex: 0xE07A99)
}

enum TimeFormat {
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}
