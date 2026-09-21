import CoreGraphics

/// What the user picked on the selection overlay.
///
/// Deliberately made of plain identifiers rather than `SCDisplay` / `SCWindow`:
/// those are reference types that aren't `Sendable`, and this value travels
/// through a continuation. The coordinator looks the real objects back up from
/// the shareable content it already has.
enum SelectionOutcome: Sendable, Equatable {
    /// A rectangle in AppKit global coordinates, and the display it began on.
    case region(CGRect, displayID: CGDirectDisplayID)
    case window(CGWindowID)
    case display(CGDirectDisplayID)
    case cancelled
}
