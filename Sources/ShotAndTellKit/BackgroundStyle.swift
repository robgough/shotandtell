import CoreGraphics

/// The canvas a capture gets composed onto.
///
/// Lives in ShotAndTellKit — it's pure description, no drawing. The compositor
/// (phase 4) turns it into pixels; the editor's picker turns it into a control.
///
/// `nonisolated` is not optional here: the target builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would otherwise make this
/// type — and its synthesised `Codable` and `CaseIterable` conformances —
/// main-actor-isolated, and unusable from the background work that composes and
/// encodes the image. Every type in this folder needs the same treatment.
nonisolated enum BackgroundStyle: Equatable, Hashable, Sendable, CaseIterable, Codable {
    /// The default: a near-white or near-black canvas following the system
    /// appearance, with the capture inset, softly shadowed and slightly rounded.
    case neutral
    /// One of a small set of curated gradients.
    case gradient(Gradient)
    /// A single flat tone. No shadow, no rounding, smallest files.
    case solid(Tone)
    /// No canvas at all — the capture and the legend, edge to edge.
    ///
    /// Deliberately not called `none`: `let style: BackgroundStyle? = .none`
    /// would then silently mean `nil` rather than this case, and `case .none`
    /// in a switch over the optional would match the wrong thing.
    case bare

    nonisolated enum Gradient: String, CaseIterable, Sendable, Codable {
        case dusk, meadow, ember, tide
    }

    nonisolated enum Tone: String, CaseIterable, Sendable, Codable {
        case paper, slate, ink
    }

    /// Written out by hand because `CaseIterable` can't be synthesised for an
    /// enum with associated values.
    static let allCases: [BackgroundStyle] =
        [.neutral]
        + Gradient.allCases.map(BackgroundStyle.gradient)
        + Tone.allCases.map(BackgroundStyle.solid)
        + [.bare]

    /// Whether the capture should be inset with a shadow and rounded corners.
    /// False for the flat styles, where that framing would just look like an
    /// unwanted border.
    var insetsCapture: Bool {
        switch self {
        case .neutral, .gradient: true
        case .solid, .bare: false
        }
    }
}
