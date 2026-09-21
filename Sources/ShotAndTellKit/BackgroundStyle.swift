import CoreGraphics

/// The canvas a capture gets composed onto.
///
/// Lives in ShotAndTellKit — it's pure description, no drawing. The compositor
/// (phase 4) turns it into pixels; the editor's picker turns it into a control.
/// Nothing here may import AppKit, so this stays usable from an iOS target.
enum BackgroundStyle: Equatable, Hashable, Sendable, CaseIterable, Codable {
    /// The default: a near-white or near-black canvas following the system
    /// appearance, with the capture inset, softly shadowed and slightly rounded.
    case neutral
    /// One of a small set of curated gradients.
    case gradient(Gradient)
    /// A single flat tone. No shadow, no rounding, smallest files.
    case solid(Tone)
    /// No canvas at all — the capture and the legend, edge to edge.
    case none

    enum Gradient: String, CaseIterable, Sendable, Codable {
        case dusk, meadow, ember, tide
    }

    enum Tone: String, CaseIterable, Sendable, Codable {
        case paper, slate, ink
    }

    static let allCases: [BackgroundStyle] =
        [.neutral]
        + Gradient.allCases.map(BackgroundStyle.gradient)
        + Tone.allCases.map(BackgroundStyle.solid)
        + [.none]

    /// Whether the capture should be inset with a shadow and rounded corners.
    /// False for the flat styles, where that framing would just look like an
    /// unwanted border.
    var insetsCapture: Bool {
        switch self {
        case .neutral, .gradient: true
        case .solid, .none: false
        }
    }
}
