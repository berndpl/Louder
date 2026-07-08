//
//  IndicatorPalette.swift
//  Louder
//
//  Semantic indicator colors (positive / caution / critical) for the
//  assessment cards, sourced from the OKLCH Style-Explorer palettes.
//
//  Each palette is a coherent triad drawn from perceptually-uniform OKLCH
//  hue ramps. Every role carries a light and a dark shade so the indicators
//  stay legible in both appearances. The selection lives in UserDefaults and
//  can be chosen in Settings ▸ Appearance or cycled with the "P" key.
//

import SwiftUI

// MARK: - OKLCH → sRGB

/// A single OKLCH color parsed from the `oklch(L C H)` string form used by the
/// Style Explorer, converted to sRGB for AppKit/SwiftUI.
struct OKLCH {
    let l: Double   // perceptual lightness 0…1
    let c: Double   // chroma
    let h: Double   // hue in degrees

    /// Parses `"oklch(0.623 0.178 145)"`. Returns a neutral gray on failure.
    init(_ string: String) {
        let scalars = string
            .replacingOccurrences(of: "oklch(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap { Double($0) }
        l = scalars.count > 0 ? scalars[0] : 0.5
        c = scalars.count > 1 ? scalars[1] : 0
        h = scalars.count > 2 ? scalars[2] : 0
    }

    /// sRGB components in 0…1, gamut-clamped.
    var srgb: (r: Double, g: Double, b: Double) {
        let hr = h * .pi / 180
        let a = c * cos(hr)
        let b = c * sin(hr)

        // OKLab → LMS (cube roots)
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let lC = l_ * l_ * l_
        let mC = m_ * m_ * m_
        let sC = s_ * s_ * s_

        // LMS → linear sRGB
        let rl =  4.0767416621 * lC - 3.3077115913 * mC + 0.2309699292 * sC
        let gl = -1.2684380046 * lC + 2.6097574011 * mC - 0.3413193965 * sC
        let bl = -0.0041960863 * lC - 0.7034186147 * mC + 1.7076147010 * sC

        func encode(_ v: Double) -> Double {
            let clamped = min(max(v, 0), 1)
            return clamped <= 0.0031308
                ? 12.92 * clamped
                : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        }
        return (encode(rl), encode(gl), encode(bl))
    }

    var nsColor: NSColor {
        let (r, g, b) = srgb
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

/// A color that resolves to a different OKLCH shade in light vs. dark mode.
private func dynamicColor(light: String, dark: String) -> Color {
    let lightNS = OKLCH(light).nsColor
    let darkNS = OKLCH(dark).nsColor
    let ns = NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua ? darkNS : lightNS
    }
    return Color(nsColor: ns)
}

// MARK: - Hue catalog

/// One perceptually-uniform hue from the Style-Explorer OKLCH palette set,
/// captured at its solid indicator shade (Radix step 9 in light, step 10 in
/// dark). These are the building blocks every indicator palette draws from.
struct IndicatorHue: Identifiable, Hashable {
    enum Role: String, CaseIterable, Identifiable {
        case positive, caution, critical, neutral
        var id: String { rawValue }
        var label: String {
            switch self {
            case .positive: return "Positive"
            case .caution:  return "Caution"
            case .critical: return "Critical"
            case .neutral:  return "Neutral"
            }
        }
    }

    let id: String          // slug, e.g. "teal"
    let name: String        // display name, e.g. "Teal"
    let lightOKLCH: String
    let darkOKLCH: String
    let role: Role

    var color: Color { dynamicColor(light: lightOKLCH, dark: darkOKLCH) }

    /// Every hue offered by the Style-Explorer OKLCH palettes (`oklchPalettes`,
    /// Radix group). Values are copied verbatim from the reference site.
    static let all: [IndicatorHue] = [
        // Positive-reading hues (greens through cyans)
        IndicatorHue(id: "green",  name: "Green",  lightOKLCH: "oklch(0.623 0.178 145)", darkOKLCH: "oklch(0.676 0.167 145)", role: .positive),
        IndicatorHue(id: "mint",   name: "Mint",   lightOKLCH: "oklch(0.609 0.192 165)", darkOKLCH: "oklch(0.662 0.178 165)", role: .positive),
        IndicatorHue(id: "teal",   name: "Teal",   lightOKLCH: "oklch(0.618 0.182 180)", darkOKLCH: "oklch(0.671 0.17 180)",  role: .positive),
        IndicatorHue(id: "cyan",   name: "Cyan",   lightOKLCH: "oklch(0.623 0.178 210)", darkOKLCH: "oklch(0.676 0.167 210)", role: .positive),
        IndicatorHue(id: "lime",   name: "Lime",   lightOKLCH: "oklch(0.703 0.205 120)", darkOKLCH: "oklch(0.761 0.186 120)", role: .positive),
        // Caution-reading hues (yellows / ambers / orange)
        IndicatorHue(id: "yellow", name: "Yellow", lightOKLCH: "oklch(0.725 0.187 91)",  darkOKLCH: "oklch(0.78 0.171 91)",   role: .caution),
        IndicatorHue(id: "amber",  name: "Amber",  lightOKLCH: "oklch(0.733 0.194 75)",  darkOKLCH: "oklch(0.788 0.177 75)",  role: .caution),
        IndicatorHue(id: "orange", name: "Orange", lightOKLCH: "oklch(0.67 0.185 55)",   darkOKLCH: "oklch(0.725 0.175 55)",  role: .caution),
        // Critical-reading hues (reds / pink)
        IndicatorHue(id: "red",    name: "Red",    lightOKLCH: "oklch(0.647 0.176 17)",  darkOKLCH: "oklch(0.699 0.166 17)",  role: .critical),
        IndicatorHue(id: "tomato", name: "Tomato", lightOKLCH: "oklch(0.657 0.183 25)",  darkOKLCH: "oklch(0.712 0.172 25)",  role: .critical),
        IndicatorHue(id: "pink",   name: "Pink",   lightOKLCH: "oklch(0.641 0.185 343)", darkOKLCH: "oklch(0.694 0.174 343)", role: .critical),
        // Neutral / informational hues (reference only)
        IndicatorHue(id: "blue",   name: "Blue",   lightOKLCH: "oklch(0.629 0.187 252)", darkOKLCH: "oklch(0.682 0.176 252)", role: .neutral),
        IndicatorHue(id: "indigo", name: "Indigo", lightOKLCH: "oklch(0.632 0.185 275)", darkOKLCH: "oklch(0.685 0.173 275)", role: .neutral),
        IndicatorHue(id: "purple", name: "Purple", lightOKLCH: "oklch(0.637 0.185 295)", darkOKLCH: "oklch(0.69 0.174 295)",  role: .neutral),
        IndicatorHue(id: "slate",  name: "Slate",  lightOKLCH: "oklch(0.645 0.018 256)", darkOKLCH: "oklch(0.716 0.016 256)", role: .neutral),
        IndicatorHue(id: "gray",   name: "Gray",   lightOKLCH: "oklch(0.649 0 0)",       darkOKLCH: "oklch(0.72 0 0)",        role: .neutral),
    ]

    static func hue(_ id: String) -> IndicatorHue { all.first { $0.id == id } ?? all[0] }

    static func hues(in role: Role) -> [IndicatorHue] { all.filter { $0.role == role } }
}

// MARK: - Indicator palette

/// A named triad of semantic indicator colors, each role drawn from one hue in
/// the Style-Explorer OKLCH palette set.
struct IndicatorPalette: Identifiable, Hashable {
    let id: String
    let name: String
    let positiveHue: String
    let cautionHue: String
    let criticalHue: String

    var positive: Color { IndicatorHue.hue(positiveHue).color }
    var caution:  Color { IndicatorHue.hue(cautionHue).color }
    var critical: Color { IndicatorHue.hue(criticalHue).color }

    var roleHues: [(role: IndicatorHue.Role, hue: IndicatorHue)] {
        [(.positive, IndicatorHue.hue(positiveHue)),
         (.caution,  IndicatorHue.hue(cautionHue)),
         (.critical, IndicatorHue.hue(criticalHue))]
    }

    static func == (lhs: IndicatorPalette, rhs: IndicatorPalette) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // Each palette pairs a positive / caution / critical hue from the catalog
    // above. The first five keep their original identity; the rest widen the
    // choice with other harmonious triads from the same OKLCH set.
    static let all: [IndicatorPalette] = [
        IndicatorPalette(id: "radix",  name: "Radix",   positiveHue: "green", cautionHue: "amber",  criticalHue: "red"),
        IndicatorPalette(id: "vivid",  name: "Vivid",   positiveHue: "lime",  cautionHue: "orange", criticalHue: "tomato"),
        IndicatorPalette(id: "ocean",  name: "Ocean",   positiveHue: "teal",  cautionHue: "yellow", criticalHue: "pink"),
        IndicatorPalette(id: "fresh",  name: "Fresh",   positiveHue: "mint",  cautionHue: "amber",  criticalHue: "tomato"),
        IndicatorPalette(id: "signal", name: "Signal",  positiveHue: "cyan",  cautionHue: "orange", criticalHue: "red"),
        IndicatorPalette(id: "forest", name: "Forest",  positiveHue: "green", cautionHue: "yellow", criticalHue: "tomato"),
        IndicatorPalette(id: "citrus", name: "Citrus",  positiveHue: "lime",  cautionHue: "yellow", criticalHue: "tomato"),
        IndicatorPalette(id: "lagoon", name: "Lagoon",  positiveHue: "teal",  cautionHue: "amber",  criticalHue: "red"),
        IndicatorPalette(id: "spring", name: "Spring",  positiveHue: "mint",  cautionHue: "yellow", criticalHue: "pink"),
        IndicatorPalette(id: "aqua",   name: "Aqua",    positiveHue: "cyan",  cautionHue: "amber",  criticalHue: "tomato"),
        IndicatorPalette(id: "jade",   name: "Jade",    positiveHue: "green", cautionHue: "orange", criticalHue: "pink"),
        IndicatorPalette(id: "neon",   name: "Neon",    positiveHue: "lime",  cautionHue: "orange", criticalHue: "pink"),
        IndicatorPalette(id: "coral",  name: "Coral",   positiveHue: "teal",  cautionHue: "orange", criticalHue: "tomato"),
        IndicatorPalette(id: "berry",  name: "Berry",   positiveHue: "mint",  cautionHue: "amber",  criticalHue: "red"),
        IndicatorPalette(id: "reef",   name: "Reef",    positiveHue: "cyan",  cautionHue: "yellow", criticalHue: "pink"),
        IndicatorPalette(id: "meadow", name: "Meadow",  positiveHue: "green", cautionHue: "amber",  criticalHue: "pink"),
    ]

    // MARK: Selection

    static let storageKey = "indicatorPaletteID"

    /// Palette used when the user hasn't chosen one yet.
    static let defaultID = "ocean"
    static var defaultPalette: IndicatorPalette { all.first { $0.id == defaultID } ?? all[0] }

    static var current: IndicatorPalette {
        let id = UserDefaults.standard.string(forKey: storageKey)
        return all.first { $0.id == id } ?? defaultPalette
    }

    /// Moves the stored selection by `delta` steps, wrapping around.
    static func step(_ delta: Int) {
        let index = all.firstIndex { $0.id == current.id } ?? 0
        let count = all.count
        let next = all[((index + delta) % count + count) % count]
        UserDefaults.standard.set(next.id, forKey: storageKey)
    }

    /// Advances the stored selection to the next palette, wrapping around.
    static func cycle() { step(1) }
}

// MARK: - Semantic colors

extension Color {
    /// Prominent brand tint reused for every generated version.
    static let generated = Color.accentColor
    /// Positive assessment — on target / low noise.
    static var positive: Color { IndicatorPalette.current.positive }
    /// Caution assessment — slightly off / some noise.
    static var caution: Color { IndicatorPalette.current.caution }
    /// Negative assessment — problematic / distracting.
    static var critical: Color { IndicatorPalette.current.critical }
}
