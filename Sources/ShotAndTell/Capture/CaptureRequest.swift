import Foundation

/// What to point the camera at.
enum CaptureMode: String, CaseIterable, Sendable {
    /// Drag a rectangle anywhere on any display.
    case region
    /// Hover to highlight a window, click to take it.
    case window
    /// A whole display, picked if there's more than one.
    case screen

    var menuTitle: String {
        switch self {
        case .region: "Capture Region"
        case .window: "Capture Window"
        case .screen: "Capture Screen"
        }
    }
}

/// A capture the user has asked for.
///
/// The timer is a property rather than a fourth `CaptureMode` case because it's
/// orthogonal to what you're capturing — "a window, ten seconds from now" is a
/// perfectly reasonable thing to want, and modelling it as a mode would have
/// made that unsayable.
struct CaptureRequest: Sendable {
    var mode: CaptureMode
    /// How long to wait before the picker appears, so the user can open a menu
    /// or hover something that vanishes when it loses focus.
    var delay: Duration = .zero

    static let region = CaptureRequest(mode: .region)
}
