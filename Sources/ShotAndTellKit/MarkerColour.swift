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

        /// One value each, whatever the appearance.
        ///
        /// There used to be a paler variant for dark compositions, on the
        /// reasoning that a dark canvas wants lighter marks. But the marks sit on
        /// the *screenshot*, which is as light or as dark as it was when it was
        /// taken, regardless of the canvas around it. The pale variants came out
        /// washed-out pink and lilac on exactly the screenshots they were meant to
        /// stand out on, and were pale enough that white numerals failed on them,
        /// so dark compositions got black numbers in a white ring. The ring and
        /// the drop shadow are what keep a mark visible on the canvas margin.
        fileprivate var hex: UInt32 {
            switch self {
            case .red: 0xE5484D
            case .orange: 0xE0651E
            case .amber: 0xC98A00
            case .green: 0x2E9B57
            case .teal: 0x1C8C8C
            case .blue: 0x2668E0
            case .purple: 0x7B44C9
            case .pink: 0xD63384
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

    /// The colour to draw with.
    var resolved: CGColor {
        switch self {
        case let .preset(preset):
            return Self.colour(preset.hex)
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
    var ink: CGColor {
        let white = Self.colour(0xFFFFFF)
        let marker = Self.relativeLuminance(resolved)
        let againstWhite = Self.contrastRatio(marker, Self.relativeLuminance(white))

        return againstWhite >= 3 ? white : Self.colour(0x1C1C1E)
    }

    /// WCAG relative luminance: sRGB components linearised first, then weighted
    /// for the eye's sensitivity. The linearisation is the part a naive
    /// weighted average leaves out, and it's most of the error.
    static func relativeLuminance(_ colour: CGColor) -> Double {
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
