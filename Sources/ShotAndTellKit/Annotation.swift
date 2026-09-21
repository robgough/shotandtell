import CoreGraphics
import Foundation

/// One mark on a capture.
///
/// All geometry is in **normalised image coordinates**: 0…1 across the capture,
/// with the origin at its top-left. Not points, not pixels, and not view
/// coordinates. That's what lets the editor preview at whatever size fits the
/// window while the export renders at 2x from the same numbers, and it's why
/// nothing here needs to know about display scale.
nonisolated struct Annotation: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var kind: Kind
    /// The legend entry. Empty is allowed — a marker with nothing written
    /// against it yet is a normal intermediate state, not an error.
    var text: String

    nonisolated enum Kind: Equatable, Codable, Sendable {
        /// A numbered dot placed on a point.
        case pin(at: CGPoint)
        /// A numbered arrow. The number sits at `from`; the head lands on `to`.
        case arrow(from: CGPoint, to: CGPoint)
        /// A numbered rectangle around a region.
        case box(CGRect)
        /// An opaque rectangle. Not numbered, and not described — its whole job
        /// is that nobody can see what was underneath.
        case redaction(CGRect)
    }

    init(id: UUID = UUID(), kind: Kind, text: String = "") {
        self.id = id
        self.kind = kind
        self.text = text
    }

    /// Redactions are the odd one out: they carry no number and no description,
    /// so they never take a place in the legend's sequence.
    var isNumbered: Bool {
        if case .redaction = kind { false } else { true }
    }

    /// Where the number badge sits, normalised.
    var anchor: CGPoint {
        switch kind {
        case let .pin(point): point
        case let .arrow(from, _): from
        case let .box(rect): CGPoint(x: rect.minX, y: rect.minY)
        case let .redaction(rect): CGPoint(x: rect.midX, y: rect.midY)
        }
    }

    /// The normalised rectangle this annotation occupies, for hit testing.
    var bounds: CGRect {
        switch kind {
        case let .pin(point):
            CGRect(x: point.x, y: point.y, width: 0, height: 0)
        case let .arrow(from, to):
            CGRect(x: min(from.x, to.x), y: min(from.y, to.y),
                   width: abs(to.x - from.x), height: abs(to.y - from.y))
        case let .box(rect), let .redaction(rect):
            rect
        }
    }

    /// Moves the whole annotation by a normalised delta.
    mutating func move(by delta: CGVector) {
        switch kind {
        case let .pin(point):
            kind = .pin(at: point.offset(by: delta))
        case let .arrow(from, to):
            kind = .arrow(from: from.offset(by: delta), to: to.offset(by: delta))
        case let .box(rect):
            kind = .box(rect.offsetBy(dx: delta.dx, dy: delta.dy))
        case let .redaction(rect):
            kind = .redaction(rect.offsetBy(dx: delta.dx, dy: delta.dy))
        }
    }
}

// `nonisolated` on the extension as well as on the types: the module's
// MainActor isolation default applies to extensions of imported types too, and
// these are called from the compositor.
nonisolated extension CGPoint {
    func offset(by delta: CGVector) -> CGPoint {
        CGPoint(x: x + delta.dx, y: y + delta.dy)
    }

    /// Keeps a normalised point inside the capture. Dragging a marker off the
    /// edge would put its number somewhere the legend can't explain.
    func clampedToUnitSquare() -> CGPoint {
        CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }
}
