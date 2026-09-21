import CoreGraphics
import Foundation

/// The colour the numbers, arrows and boxes are drawn in.
///
/// Worth choosing per shot rather than fixing: a red marker on a screenshot of
/// something red is invisible, and that's precisely the screenshot you were
/// trying to point at something in.
nonisolated enum MarkerColour: Equatable, Hashable, Codable, Sendable {
    case preset(Preset)
    /// sRGB components, 0…1, from the colour picker.
    case custom(red: Double, green: Double, blue: Double)

    nonisolated enum Preset: String, CaseIterable, Codable, Sendable, Identifiable {
        case red, orange, amber, green, teal, blue, purple, pink

        var id: String { rawValue }

        var name: String {
            switch self {
            case .red: "Red"
            case .orange: "Orange"
            case .amber: "Amber"
            case .green: "Green"
            case .teal: "Teal"
            case .blue: "Blue"
            case .purple: "Purple"
            case .pink: "Pink"
            }
        }

        /// Two values each: the darker one reads on a light background, the
        /// lighter one on a dark background. A single value that worked on both
        /// would be a compromise on each.
        fileprivate var hexes: (light: UInt32, dark: UInt32) {
            switch self {
            case .red: (0xE5484D, 0xFF6B70)
            case .orange: (0xE0651E, 0xFF8A3D)
            case .amber: (0xC98A00, 0xF5C542)
            case .green: (0x2E9B57, 0x46C97B)
            case .teal: (0x1C8C8C, 0x3CC0C0)
            case .blue: (0x2668E0, 0x5B95FF)
            case .purple: (0x7B44C9, 0xA87BF0)
            case .pink: (0xD63384, 0xFF6FB1)
            }
        }
    }

    static let `default` = MarkerColour.preset(.red)

    static let presets: [MarkerColour] = Preset.allCases.map(MarkerColour.preset)

    var name: String {
        switch self {
        case let .preset(preset): preset.name
        case .custom: "Custom"
        }
    }

    /// The colour to draw with, in the composition's light or dark treatment.
    func resolved(for appearance: Composition.Appearance) -> CGColor {
        switch self {
        case let .preset(preset):
            let hex = appearance == .dark ? preset.hexes.dark : preset.hexes.light
            return Self.colour(hex)
        case let .custom(red, green, blue):
            // A chosen colour is used exactly as chosen. Nudging it towards the
            // appearance would mean the swatch in the picker and the mark on the
            // image disagreed, which is worse than it being a little dark.
            return CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        }
    }

    /// What the numeral inside the badge should be: white unless the marker is
    /// light enough that white stops being readable on it.
    ///
    /// Deliberately not "whichever contrasts better". Strict WCAG comparison
    /// puts near-black on red, because #E5484D scores 3.5:1 against white and
    /// 5.9:1 against black — correct arithmetic, wrong answer. A white numeral
    /// on a red badge is the universal convention and is perfectly legible at
    /// 11pt bold; swapping it looks broken.
    ///
    /// So: keep white, and fall back to near-black only when white drops below
    /// 3:1 — WCAG's large-text floor, which is where legibility genuinely starts
    /// to go. That catches the amber and the bright custom colours, which are
    /// the cases that actually fail, and leaves the rest alone.
    func ink(for appearance: Composition.Appearance) -> CGColor {
        let white = Self.colour(0xFFFFFF)
        let marker = Self.relativeLuminance(resolved(for: appearance))
        let againstWhite = Self.contrastRatio(marker, Self.relativeLuminance(white))

        return againstWhite >= 3 ? white : Self.colour(0x1C1C1E)
    }

    /// WCAG relative luminance: sRGB components linearised first, then weighted
    /// for the eye's sensitivity. The linearisation is the part a naive
    /// weighted average leaves out, and it's most of the error.
    private static func relativeLuminance(_ colour: CGColor) -> Double {
        let components = colour.components ?? [0, 0, 0, 1]
        guard components.count >= 3 else { return 0 }

        func linear(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(components[0])
            + 0.7152 * linear(components[1])
            + 0.0722 * linear(components[2])
    }

    private static func contrastRatio(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func colour(_ hex: UInt32) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
