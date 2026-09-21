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
        case .redact: "rectangle.fill.on.rectangle.fill"
        }
    }

    /// Creation tools are dragged out; the pin is a single click.
    var isDragged: Bool {
        switch self {
        case .select, .pin: false
        case .arrow, .box, .redact: true
        }
    }

    var help: String {
        switch self {
        case .select: "Select and move marks"
        case .pin: "Click to drop a numbered pin"
        case .arrow: "Drag to draw a numbered arrow"
        case .box: "Drag a numbered box around something"
        case .redact: "Drag a box over anything that should be hidden"
        }
    }
}
