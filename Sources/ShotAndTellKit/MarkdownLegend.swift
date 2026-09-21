import Foundation

/// The legend as text.
///
/// This is the quiet half of the app's purpose: a model reads words in the
/// prompt directly, but has to work the same words back out of the picture by
/// OCR. Shipping both means "the heading in ① is too large" is legible either
/// way, and costs nothing once the numbering already exists.
nonisolated enum MarkdownLegend {
    static func render(_ composition: Composition) -> String {
        var lines: [String] = []

        let title = composition.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            lines.append("## \(title)")
            lines.append("")
        }

        for (number, annotation) in composition.numbered {
            let text = annotation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Keep unlabelled marks in the list. They're still on the image, and
            // silently dropping them would make the numbering skip.
            lines.append("\(number). \(text.isEmpty ? "(no description)" : text)")
        }

        if !composition.redactions.isEmpty {
            if !lines.isEmpty { lines.append("") }
            let count = composition.redactions.count
            lines.append(count == 1
                ? "One area of this screenshot has been redacted."
                : "\(count) areas of this screenshot have been redacted.")
        }

        return lines.joined(separator: "\n")
    }
}
