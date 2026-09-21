import CoreGraphics

/// Every colour the compositor draws with, resolved once from the background
/// style and the light/dark appearance.
///
/// Kept as plain `CGColor` rather than `NSColor`: the compositor renders into a
/// fixed sRGB context, so colours must be concrete values rather than anything
/// that resolves against the current appearance at draw time. An exported image
/// should look the same whoever opens it.
nonisolated struct Palette: Sendable {
    let canvasTop: CGColor
    let canvasBottom: CGColor
    let ink: CGColor
    let inkSecondary: CGColor
    let rule: CGColor
    let marker: CGColor
    let markerInk: CGColor
    let redaction: CGColor
    let captureBorder: CGColor

    var canvasIsGradient: Bool { canvasTop != canvasBottom }

    static func resolve(background: BackgroundStyle, appearance: Composition.Appearance) -> Palette {
        let dark = appearance == .dark

        // One accent for every mark. A single confident colour reads as
        // deliberate annotation; a palette of them reads as clip art, and makes
        // "the red one" an ambiguous thing to say.
        let marker = dark ? rgb(0xFF6B70) : rgb(0xE5484D)
        let ink = dark ? rgb(0xF2F2F5) : rgb(0x1C1C1E)
        let inkSecondary = dark ? rgb(0x9A9AA2) : rgb(0x6C6C72)
        let rule = dark ? rgb(0xFFFFFF, alpha: 0.12) : rgb(0x000000, alpha: 0.10)
        let border = dark ? rgb(0xFFFFFF, alpha: 0.10) : rgb(0x000000, alpha: 0.08)

        let (top, bottom): (CGColor, CGColor) = switch background {
        case .neutral:
            dark ? (rgb(0x1B1B1F), rgb(0x141417)) : (rgb(0xF7F7F9), rgb(0xEDEDF1))
        case let .gradient(gradient):
            gradientColours(gradient, dark: dark)
        case let .solid(tone):
            {
                let colour = solidColour(tone, dark: dark)
                return (colour, colour)
            }()
        case .bare:
            {
                let colour = dark ? rgb(0x141417) : rgb(0xFFFFFF)
                return (colour, colour)
            }()
        }

        return Palette(
            canvasTop: top,
            canvasBottom: bottom,
            ink: ink,
            inkSecondary: inkSecondary,
            rule: rule,
            marker: marker,
            markerInk: rgb(0xFFFFFF),
            // Redaction is deliberately flat and opaque rather than blurred:
            // a blur is a picture of the thing you're hiding, and at these sizes
            // it's often reversible enough to matter.
            redaction: dark ? rgb(0x2A2A30) : rgb(0x2B2B31),
            captureBorder: border
        )
    }

    private static func gradientColours(_ gradient: BackgroundStyle.Gradient, dark: Bool) -> (CGColor, CGColor) {
        switch (gradient, dark) {
        case (.dusk, false): (rgb(0xE8E4F5), rgb(0xD3D9F2))
        case (.dusk, true): (rgb(0x2A2540), rgb(0x1B1B33))
        case (.meadow, false): (rgb(0xE2F1E6), rgb(0xD2E9E4))
        case (.meadow, true): (rgb(0x1E3029), rgb(0x142623))
        case (.ember, false): (rgb(0xFBE9DF), rgb(0xF6D9D5))
        case (.ember, true): (rgb(0x3A241E), rgb(0x2A1719))
        case (.tide, false): (rgb(0xDFEDF7), rgb(0xD2E2F3))
        case (.tide, true): (rgb(0x16293A), rgb(0x101E2E))
        }
    }

    private static func solidColour(_ tone: BackgroundStyle.Tone, dark: Bool) -> CGColor {
        switch tone {
        case .paper: dark ? rgb(0x232326) : rgb(0xFFFFFF)
        case .slate: dark ? rgb(0x2C2C31) : rgb(0xE4E4E9)
        case .ink: dark ? rgb(0x0C0C0E) : rgb(0x1C1C1E)
        }
    }

    private static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
