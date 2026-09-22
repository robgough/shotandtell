import AppKit
import CoreGraphics
import ImageIO

/// TEMPORARY — marketing-shot tooling, not shipped.
///
/// Opens the editor with a prepared capture and a fixed set of marks so the
/// App Store screenshots can be produced without hand-placing them.
enum DemoLoader {
    struct Spec: Decodable {
        struct Mark: Decodable {
            var kind: String
            var x: Double?, y: Double?
            var x2: Double?, y2: Double?
            var text: String?
        }
        var image: String
        var scale: Double
        var title: String
        var background: String?
        var marker: String?
        var appearance: String?
        var marks: [Mark]
    }

    private static func background(_ name: String?) -> BackgroundStyle {
        guard let name else { return .neutral }
        if let g = BackgroundStyle.Gradient(rawValue: name) { return .gradient(g) }
        if let t = BackgroundStyle.Tone(rawValue: name) { return .solid(t) }
        return name == "bare" ? .bare : .neutral
    }

    static func load() -> Composition? {
        guard let path = ProcessInfo.processInfo.environment["SHOTANDTELL_DEMO"],
              let data = FileManager.default.contents(atPath: path),
              let spec = try? JSONDecoder().decode(Spec.self, from: data),
              let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: spec.image) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let annotations: [Annotation] = spec.marks.map { m in
            let x = m.x ?? 0, y = m.y ?? 0, x2 = m.x2 ?? 0, y2 = m.y2 ?? 0
            let rect = CGRect(x: x, y: y, width: x2 - x, height: y2 - y)
            let kind: Annotation.Kind = switch m.kind {
            case "pin": .pin(at: CGPoint(x: x, y: y))
            case "arrow": .arrow(from: CGPoint(x: x, y: y), to: CGPoint(x: x2, y: y2))
            case "box": .box(rect)
            default: .redaction(rect)
            }
            return Annotation(kind: kind, text: m.text ?? "")
        }

        let capture = CapturedImage(image: image, source: .region,
                                    scale: spec.scale, sourceDescription: nil)
        return Composition(
            capture: capture,
            title: spec.title,
            background: background(spec.background),
            appearance: Composition.Appearance(rawValue: spec.appearance ?? "") ?? .light,
            markerColour: MarkerColour.Preset(rawValue: spec.marker ?? "").map(MarkerColour.preset) ?? .default,
            annotations: annotations
        )
    }
}
