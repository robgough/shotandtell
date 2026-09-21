import CoreGraphics
import Foundation

/// Everything needed to render one finished image: the capture, what's been
/// marked on it, and how it should be framed.
///
/// A value type, and `Sendable`, so the compositor can be handed a snapshot and
/// render it off the main thread while the editor carries on mutating its own
/// copy.
nonisolated struct Composition: @unchecked Sendable {
    var capture: CapturedImage
    /// The legend's heading. Prefilled from the captured app's name, editable,
    /// and allowed to be empty — some shots don't need a title.
    var title: String
    var background: BackgroundStyle
    var appearance: Appearance
    var markerColour: MarkerColour
    var annotations: [Annotation]

    nonisolated enum Appearance: String, Codable, Sendable, CaseIterable {
        case light, dark
    }

    init(
        capture: CapturedImage,
        title: String = "",
        background: BackgroundStyle = .neutral,
        appearance: Appearance = .light,
        markerColour: MarkerColour = .default,
        annotations: [Annotation] = []
    ) {
        self.capture = capture
        self.title = title
        self.background = background
        self.appearance = appearance
        self.markerColour = markerColour
        self.annotations = annotations
    }

    /// The numbered annotations in order, paired with the number they show.
    ///
    /// Numbering is derived from position in the array rather than stored, so
    /// deleting the second marker renumbers everything after it in the canvas
    /// and the legend at once, with nothing to keep in sync.
    var numbered: [(number: Int, annotation: Annotation)] {
        var number = 0
        return annotations.compactMap { annotation in
            guard annotation.isNumbered else { return nil }
            number += 1
            return (number, annotation)
        }
    }

    var redactions: [Annotation] {
        annotations.filter { !$0.isNumbered }
    }

    /// True when there's nothing to put in the legend column — no title and no
    /// described markers. The compositor drops the column entirely rather than
    /// leaving an empty gutter.
    var legendIsEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && numbered.isEmpty
    }
}
