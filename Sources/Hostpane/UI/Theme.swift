import AppKit
import SwiftUI
import HostpaneCore

enum HostpaneTheme {
    static let accent = Color(red: 0.43, green: 0.35, blue: 0.98)
    static let page = Color(nsColor: NSColor(name: "HostpanePage", dynamicProvider: { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            return NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        }
        return NSColor(srgbRed: 0.965, green: 0.965, blue: 0.972, alpha: 1)
    }))
    static let cardStroke = Color(nsColor: NSColor(name: "HostpaneCardStroke", dynamicProvider: { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            return NSColor(srgbRed: 0.38, green: 0.36, blue: 0.55, alpha: 1)
        }
        return NSColor(srgbRed: 0.78, green: 0.76, blue: 1.0, alpha: 1)
    }))
    static let sftpTint = Color(red: 0.72, green: 0.90, blue: 0.78)
    static let total = Color(red: 0.20, green: 0.62, blue: 0.98)
    static let online = Color(red: 0.22, green: 0.76, blue: 0.42)
    static let connecting = Color(red: 0.98, green: 0.72, blue: 0.16)
    static let offline = Color(red: 0.94, green: 0.30, blue: 0.32)
    static let cpuRing = Color(red: 0.32, green: 0.78, blue: 0.72)
    static let memoryRing = Color(red: 0.28, green: 0.74, blue: 0.46)
    static let diskRing = Color(red: 0.22, green: 0.76, blue: 0.42)
    static let loadLow = Color(red: 0.22, green: 0.76, blue: 0.42)
    static let loadMedium = Color(red: 0.98, green: 0.62, blue: 0.16)
    static let loadHigh = Color(red: 0.94, green: 0.30, blue: 0.32)

    static func color(for band: MetricBand) -> Color {
        switch band {
        case .low: return loadLow
        case .medium: return loadMedium
        case .high: return loadHigh
        }
    }

    static func latencyColor(_ seconds: Double) -> Color {
        color(for: MetricBand.latency(seconds))
    }

    static func usageColor(_ ratio: Double?) -> Color {
        guard let ratio else { return Color.secondary.opacity(0.45) }
        return color(for: MetricBand.usage(ratio))
    }
    static let netUp = Color(red: 1.0, green: 0.55, blue: 0.22)
    static let netDown = Color(red: 0.22, green: 0.78, blue: 0.95)
    static let docker = Color(red: 0.13, green: 0.62, blue: 0.93)
    static let cpuUser = Color(red: 0.33, green: 0.72, blue: 0.98)
    static let cpuSystem = Color(red: 0.94, green: 0.36, blue: 0.36)
    static let cpuNice = Color(red: 0.35, green: 0.78, blue: 0.48)
    static let cpuIOWait = Color(red: 0.62, green: 0.48, blue: 0.95)
    static let cpuSteal = Color(red: 0.98, green: 0.62, blue: 0.28)
    static let loadOne = Color(red: 0.94, green: 0.32, blue: 0.32)
    static let loadFive = Color(red: 0.25, green: 0.62, blue: 0.98)
    static let loadFifteen = Color(red: 0.98, green: 0.72, blue: 0.18)
    static let memUsed = Color(red: 0.62, green: 0.38, blue: 0.98)
    static let memCached = Color(red: 0.55, green: 0.55, blue: 0.58)
    static let memFree = Color(red: 0.82, green: 0.82, blue: 0.84)
    static let terminalBackdrop = Color(nsColor: NSColor(name: "HostpaneTerminalBackdrop", dynamicProvider: { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            return NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1)
        }
        return NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    }))
    static let sidebarWidth: CGFloat = 232
}

extension AppearancePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}
