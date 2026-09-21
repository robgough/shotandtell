import Foundation

/// What a click on the canvas does.
enum EditorTool: String, CaseIterable, Identifiable, Sendable {
    case select
    case pin
    case arrow
    case box
    case redact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "Select"
        case .pin: "Pin"
        case .arrow: "Arrow"
        case .box: "Box"
        case .redact: "Redact"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .pin: "1.circle.fill"
        case .arrow: "arrow.up.right"
        case .box: "rectangle"
        // Not a filled rectangle, however literal that is: beside the box
        // tool's outlined one it becomes spot-the-difference at toolbar size.
        // A crossed-out eye says what the tool is *for* rather than what it
        // draws.
        case .redact: "eye.slash"
        }
    }

    /// Creation tools are dragged out; the pin is a single click.
    var isDragged: Bool {
        switch self {
        case .select, .pin: false
        case .arrow, .box, .redact: true
        }
    }

    /// A bare letter, plus its position as a digit. No modifier: the canvas
    /// only sees these when it has focus, and when focus is in a description
    /// field the same keys type, which is what you want.
    var shortcut: Character {
        switch self {
        case .select: "v"
        case .pin: "p"
        case .arrow: "a"
        case .box: "b"
        case .redact: "r"
        }
    }

    var shortcutDigit: Character {
        Character("\(Self.allCases.firstIndex(of: self)! + 1)")
    }

    static func named(by key: Character) -> EditorTool? {
        allCases.first { $0.shortcut == key || $0.shortcutDigit == key }
    }

    var help: String {
        switch self {
        case .select: "Select and move marks  (V)"
        case .pin: "Click to drop a numbered pin  (P)"
        case .arrow: "Drag to draw a numbered arrow  (A)"
        case .box: "Drag a numbered box around something  (B)"
        case .redact: "Drag a box over anything that should be hidden  (R)"
        }
    }
}
